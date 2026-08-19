class OpportunitiesController < ApplicationController
  DEFAULT_LIMIT = 10
  DEFAULT_FRESHNESS_DAYS = 14

  def index
    @profile = Profile.current
    @target_roles = @profile.target_roles
    @jobs = @target_roles.present? ? JobOpportunity.backlog.order(created_at: :desc) : JobOpportunity.none
    @default_limit = DEFAULT_LIMIT
    @default_freshness_days = DEFAULT_FRESHNESS_DAYS
    @default_modes = @profile.preferred_modes
  end

  # Rendered inside a <turbo-frame id="opportunities-list">, so Turbo swaps
  # just this fragment in place of a full page navigation — the "spinner"
  # is the submit button's data-turbo-submits-with state while this runs.
  #
  # This does one Tavily search per target_role, then one Tavily extract +
  # one LLM call per surviving candidate, fully sequentially — a deliberate
  # choice (see the grilling session: staying synchronous, no background
  # jobs, was reconsidered and reaffirmed even knowing Rails makes the
  # alternative cheap). A large target_roles list or limit can make a
  # single click take a while; revisit only if that proves genuinely
  # annoying in practice.
  def search
    profile = Profile.current

    if profile.target_roles.present?
      found = Searcher.call(
        target_roles: profile.target_roles,
        preferred_cities: profile.preferred_cities,
        mode_filter: Array(params[:mode_filter]).reject(&:blank?),
        limit: positive_int_param(:limit, DEFAULT_LIMIT),
        freshness_days: positive_int_param(:freshness_days, DEFAULT_FRESHNESS_DAYS),
        llm: LlmClient.new,
        search_client: TavilyClient.new,
        min_salary: profile.min_salary
      )
      found.each { |attrs| JobOpportunity.add_if_new(attrs) }
    end

    @jobs = JobOpportunity.backlog.order(created_at: :desc)
    render partial: "opportunities_frame", locals: { jobs: @jobs }
  end

  # Responds to Turbo Stream requests from each job card's state buttons:
  # replace the card in place if it's still in the backlog (e.g. "saved"),
  # or remove it entirely once it leaves the backlog (applied/discarded/
  # irrelevant) — mirrors the HTMX swap-to-empty behavior from the Python
  # version.
  def update_state
    job = JobOpportunity.find(params[:id])
    return head :unprocessable_entity unless JobOpportunity::STATES.include?(params[:new_state])

    job.update!(state: params[:new_state])

    respond_to do |format|
      format.turbo_stream do
        if JobOpportunity::BACKLOG_STATES.include?(job.state)
          render turbo_stream: turbo_stream.replace(job, partial: "job_card", locals: { job: job })
        else
          render turbo_stream: turbo_stream.remove(job)
        end
      end
      format.html { redirect_to opportunities_path }
    end
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  private

  # `params[:limit].presence&.to_i || DEFAULT_LIMIT` only falls back to
  # the default when the param is absent — a param of "0" or a
  # non-numeric string both parse to 0 via #to_i and would otherwise pass
  # straight through, silently producing a zero-result search.
  def positive_int_param(key, default)
    value = params[key].presence&.to_i
    value.nil? || value <= 0 ? default : value
  end
end
