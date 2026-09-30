require "test_helper"

class OpportunitiesControllerTest < ActionDispatch::IntegrationTest
  class FakeLlm
    def initialize(response) = @response = response
    def extract(**) = @response
  end

  class FakeSearchClient
    attr_reader :queries, :max_results_calls

    def initialize(results)
      @results = results
      @queries = []
      @max_results_calls = []
    end

    def search(query:, max_results:, **)
      @queries << query
      @max_results_calls << max_results
      @results
    end

    def extract(**) = "content"
  end

  def save_profile_with_target_roles(min_salary: nil)
    extraction = ProfileExtraction.new(characteristics: Characteristics.new(skills: []), target_roles: [ "Engineer" ])
    LlmClient.stub :new, FakeLlm.new(extraction) do
      post save_resume_path, params: { resume_text: "Backend engineer." }
    end
    post save_preferences_path, params: { min_salary: min_salary } if min_salary
  end

  test "opportunities page prompts to complete profile when empty" do
    get opportunities_path
    assert_response :success
    assert_includes response.body, "Complete your profile first"
  end

  test "searching persists and renders a job card" do
    save_profile_with_target_roles

    listing = JobListingExtraction.new(
      company: "Acme Corp", title: "Senior Engineer", location: "Remote",
      mode: "remote", description_summary: "Build things."
    )
    search_client = FakeSearchClient.new([ SearchResult.new(url: "https://a/1", title: "A") ])

    LlmClient.stub :new, FakeLlm.new(listing) do
      TavilyClient.stub :new, search_client do
        post search_opportunities_path, params: { limit: 10, freshness_days: 14 }
      end
    end

    assert_response :success
    assert_includes response.body, "Acme Corp"
    assert_equal 1, JobOpportunity.count

    get history_path
    assert_includes response.body, "Acme Corp"
  end

  test "search passes the profile's min_salary through to the search query" do
    save_profile_with_target_roles(min_salary: 150_000)

    listing = JobListingExtraction.new(
      company: "Acme Corp", title: "Senior Engineer", location: "Remote",
      mode: "remote", description_summary: "Build things."
    )
    search_client = FakeSearchClient.new([ SearchResult.new(url: "https://a/1", title: "A") ])

    LlmClient.stub :new, FakeLlm.new(listing) do
      TavilyClient.stub :new, search_client do
        post search_opportunities_path, params: { limit: 10, freshness_days: 14 }
      end
    end

    assert(search_client.queries.any? { |q| q.include?("150000") })
  end

  test "updating a job's state to applied removes it from the backlog response" do
    save_profile_with_target_roles
    listing = JobListingExtraction.new(
      company: "Acme Corp", title: "Senior Engineer", location: "Remote",
      mode: "remote", description_summary: "Build things."
    )
    search_client = FakeSearchClient.new([ SearchResult.new(url: "https://a/1", title: "A") ])
    LlmClient.stub :new, FakeLlm.new(listing) do
      TavilyClient.stub :new, search_client do
        post search_opportunities_path, params: { limit: 10, freshness_days: 14 }
      end
    end
    job = JobOpportunity.first

    post opportunity_state_path(job, new_state: "applied"), as: :turbo_stream

    assert_response :success
    assert_includes response.body, "turbo-stream action=\"remove\""
    assert_equal "applied", job.reload.state
  end

  test "updating state of a nonexistent job returns 404" do
    post opportunity_state_path(999_999, new_state: "applied"), as: :turbo_stream
    assert_response :not_found
  end

  test "updating state to an invalid value returns 422 instead of raising" do
    save_profile_with_target_roles
    listing = JobListingExtraction.new(
      company: "Acme Corp", title: "Senior Engineer", location: "Remote",
      mode: "remote", description_summary: "Build things."
    )
    LlmClient.stub :new, FakeLlm.new(listing) do
      TavilyClient.stub :new, FakeSearchClient.new([ SearchResult.new(url: "https://a/1", title: "A") ]) do
        post search_opportunities_path, params: { limit: 10, freshness_days: 14 }
      end
    end
    job = JobOpportunity.first

    post opportunity_state_path(job, new_state: "not-a-real-state"), as: :turbo_stream

    assert_response :unprocessable_content
    assert_equal "new", job.reload.state
  end

  test "a limit of 0 falls back to the default instead of silently returning zero jobs" do
    save_profile_with_target_roles
    search_client = FakeSearchClient.new([])

    LlmClient.stub :new, FakeLlm.new(nil) do
      TavilyClient.stub :new, search_client do
        post search_opportunities_path, params: { limit: 0, freshness_days: 14 }
      end
    end

    assert_equal [ OpportunitiesController::DEFAULT_LIMIT ], search_client.max_results_calls
  end
end
