# Step 2: turn target_roles into stored-ready JobOpportunity attribute
# Hashes.
#
# One Tavily search per target_role (seeded with well-known job-board
# hints), candidate URLs deduped before extraction to control cost, capped
# at `limit`, then one structured-output LLM call per surviving candidate.
# A candidate whose extract/LLM call fails is skipped, not fatal to the run.
#
# Persisting + the (company, title, location) dedup-on-store check is the
# caller's job — see JobOpportunity.add_if_new.
class Searcher
  JOB_BOARD_HINTS = "site:linkedin.com OR site:indeed.com OR site:glassdoor.com " \
                     "OR site:remoteok.com OR site:weworkremotely.com"

  EXTRACTION_PROMPT_TEMPLATE = <<~PROMPT
    Extract the job listing's attributes from the page content below:
    company, title, location, mode (remote, on_site, or hybrid), published
    date (ISO format if determinable), a short description summary, minimum
    requirements, and salary if stated.

    Page content:
    ---
    %<content>s
    ---
  PROMPT

  # Substrings that identify a mode from free-text LLM output. Checked in
  # this order, so "hybrid" wins over an incidental "office" mention, etc.
  MODE_ALIASES = [
    [ "hybrid", "hybrid" ],
    [ "remote", "remote" ],
    [ "wfh", "remote" ],
    [ "work from home", "remote" ],
    [ "on-site", "on_site" ],
    [ "onsite", "on_site" ],
    [ "on site", "on_site" ],
    [ "in-office", "on_site" ],
    [ "in office", "on_site" ],
    [ "in-person", "on_site" ],
    [ "in person", "on_site" ],
    [ "office", "on_site" ]
  ].freeze

  class << self
    def call(target_roles:, preferred_cities:, mode_filter:, limit:, freshness_days:, llm:, search_client:, min_salary: nil)
      candidates = collect_candidate_urls(
        target_roles: target_roles, preferred_cities: preferred_cities, mode_filter: mode_filter,
        freshness_days: freshness_days, limit: limit, search_client: search_client, min_salary: min_salary
      )

      candidates.filter_map do |url|
        begin
          content = search_client.extract(url: url)
          prompt = format(EXTRACTION_PROMPT_TEMPLATE, content: content)
          listing = llm.extract(prompt: prompt, schema: JobListingExtraction)
          build_attributes(listing, url)
        rescue StandardError
          # One bad candidate (a timed-out extract, an unparseable
          # response) shouldn't discard every candidate already found.
          nil
        end
      end
    end

    private

    def collect_candidate_urls(target_roles:, preferred_cities:, mode_filter:, freshness_days:, limit:, search_client:, min_salary:)
      seen = Set.new
      urls = []
      target_roles.each do |role|
        break if urls.length >= limit

        query = build_query(role, preferred_cities, mode_filter, min_salary)
        remaining = limit - urls.length
        search_client.search(query: query, max_results: remaining, days: freshness_days).each do |result|
          next if seen.include?(result.url)

          seen << result.url
          urls << result.url
          break if urls.length >= limit
        end
      end
      urls
    end

    def build_query(role, preferred_cities, mode_filter, min_salary)
      parts = [ role ]
      modes = [ *mode_filter, "remote" ]
      parts << "(#{modes.join(' OR ')})"
      parts << "in #{preferred_cities.join(' OR ')}" if preferred_cities.present?
      parts << "salary at least $#{min_salary}" if min_salary.present?
      parts << JOB_BOARD_HINTS
      parts.join(" ")
    end

    def build_attributes(listing, url)
      {
        company: listing.company,
        title: listing.title,
        location: listing.location,
        mode: parse_mode(listing.mode),
        website: URI.parse(url).host,
        url: url,
        published_date: parse_date(listing.published_date),
        description_summary: listing.description_summary,
        minimum_requirements: listing.minimum_requirements,
        salary: listing.salary
      }
    end

    # A negated "remote" ("not remote", "non-remote") must not match the
    # remote alias — that inverts the very safety goal below (a wrongly
    # remote-labeled job is worse than a wrongly on_site-labeled one).
    NEGATED_REMOTE_PATTERN = /\bnot\s+(a\s+)?remote\b|\bnon-?remote\b/

    def parse_mode(value)
      normalized = value.to_s.strip.downcase
      aliases = MODE_ALIASES
      aliases = aliases.reject { |_, mode| mode == "remote" } if normalized.match?(NEGATED_REMOTE_PATTERN)

      _, mode = aliases.find { |alias_, _| normalized.include?(alias_) }
      # Genuinely unrecognized: default to the less specific claim. Falsely
      # labeling a job "remote" is worse than falsely labeling it
      # "on_site", since users may filter/trust the remote label directly.
      mode || "on_site"
    end

    def parse_date(value)
      return nil if value.blank?

      Date.iso8601(value)
    rescue ArgumentError
      nil
    end
  end
end
