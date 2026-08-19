require "test_helper"

class SearcherTest < ActiveSupport::TestCase
  class FakeSearchClient
    attr_reader :search_calls, :max_results_calls, :days_calls, :extract_calls

    def initialize(results_per_call, content_by_url = {})
      @results_per_call = results_per_call.dup
      @content_by_url = content_by_url
      @search_calls = []
      @max_results_calls = []
      @days_calls = []
      @extract_calls = []
    end

    def search(query:, max_results:, days: nil)
      @search_calls << query
      @max_results_calls << max_results
      @days_calls << days
      @results_per_call.shift
    end

    def extract(url:)
      @extract_calls << url
      content = @content_by_url[url]
      raise content if content.is_a?(Exception)
      content
    end
  end

  class FakeLlm
    def initialize(response_by_url, content_by_url)
      @response_by_url = response_by_url
      @content_by_url = content_by_url
    end

    def extract(prompt:, schema:)
      url, content = @content_by_url.find { |_, c| c.is_a?(String) && prompt.include?(c) }
      raise "No canned response matches prompt: #{prompt.inspect}" unless url
      response = @response_by_url[url]
      raise response if response.is_a?(Exception)
      response
    end
  end

  def listing(overrides = {})
    JobListingExtraction.new({
      company: "Acme Corp",
      title: "Senior Engineer",
      location: "Remote",
      mode: "remote",
      published_date: "2026-08-10",
      description_summary: "Build things.",
      minimum_requirements: "5+ years Ruby",
      salary: "$150k-$180k"
    }.merge(overrides))
  end

  test "does one search per target role" do
    search_client = FakeSearchClient.new(
      [
        [ SearchResult.new(url: "https://a/1", title: "A") ],
        [ SearchResult.new(url: "https://b/1", title: "B") ]
      ],
      { "https://a/1" => "content-a", "https://b/1" => "content-b" }
    )
    llm = FakeLlm.new(
      { "https://a/1" => listing(company: "A"), "https://b/1" => listing(company: "B") },
      { "https://a/1" => "content-a", "https://b/1" => "content-b" }
    )

    jobs = Searcher.call(
      target_roles: [ "Engineer", "Developer" ], preferred_cities: [ "Remote" ], mode_filter: [],
      limit: 10, freshness_days: 14, llm: llm, search_client: search_client
    )

    assert_equal 2, search_client.search_calls.length
    assert_equal Set["A", "B"], jobs.map { |j| j[:company] }.to_set
  end

  test "passes freshness_days as a real recency filter" do
    search_client = FakeSearchClient.new(
      [ [ SearchResult.new(url: "https://a/1", title: "A") ] ],
      { "https://a/1" => "content-a" }
    )
    llm = FakeLlm.new({ "https://a/1" => listing }, { "https://a/1" => "content-a" })

    Searcher.call(
      target_roles: [ "Engineer" ], preferred_cities: [ "Remote" ], mode_filter: [],
      limit: 10, freshness_days: 21, llm: llm, search_client: search_client
    )

    assert_equal [ 21 ], search_client.days_calls
  end

  test "dedupes the same url across roles before extracting" do
    search_client = FakeSearchClient.new(
      [
        [ SearchResult.new(url: "https://a/1", title: "A") ],
        [ SearchResult.new(url: "https://a/1", title: "A") ]
      ],
      { "https://a/1" => "content-a" }
    )
    llm = FakeLlm.new({ "https://a/1" => listing }, { "https://a/1" => "content-a" })

    jobs = Searcher.call(
      target_roles: [ "Engineer", "Developer" ], preferred_cities: [ "Remote" ], mode_filter: [],
      limit: 10, freshness_days: 14, llm: llm, search_client: search_client
    )

    assert_equal [ "https://a/1" ], search_client.extract_calls
    assert_equal 1, jobs.length
  end

  test "caps total results at limit" do
    urls = (0...5).map { |i| "https://a/#{i}" }
    search_client = FakeSearchClient.new(
      [ urls.map { |u| SearchResult.new(url: u, title: u) } ],
      urls.to_h { |u| [ u, "content-#{u}" ] }
    )
    llm = FakeLlm.new(
      urls.to_h { |u| [ u, listing(title: u) ] },
      urls.to_h { |u| [ u, "content-#{u}" ] }
    )

    jobs = Searcher.call(
      target_roles: [ "Engineer" ], preferred_cities: [ "Remote" ], mode_filter: [],
      limit: 3, freshness_days: 14, llm: llm, search_client: search_client
    )

    assert_equal 3, jobs.length
    assert_equal 3, search_client.extract_calls.length
  end

  test "requests only the remaining budget from each subsequent role" do
    search_client = FakeSearchClient.new(
      [
        [ SearchResult.new(url: "https://a/1", title: "A"), SearchResult.new(url: "https://a/2", title: "A2") ],
        [ SearchResult.new(url: "https://b/1", title: "B") ]
      ],
      { "https://a/1" => "c1", "https://a/2" => "c2", "https://b/1" => "c3" }
    )
    llm = FakeLlm.new(
      { "https://a/1" => listing, "https://a/2" => listing, "https://b/1" => listing },
      { "https://a/1" => "c1", "https://a/2" => "c2", "https://b/1" => "c3" }
    )

    Searcher.call(
      target_roles: [ "Engineer", "Developer" ], preferred_cities: [ "Remote" ], mode_filter: [],
      limit: 10, freshness_days: 14, llm: llm, search_client: search_client
    )

    assert_equal [ 10, 8 ], search_client.max_results_calls
  end

  test "skips a candidate whose extraction fails and keeps the rest" do
    search_client = FakeSearchClient.new(
      [ [ SearchResult.new(url: "https://a/1", title: "A"), SearchResult.new(url: "https://a/2", title: "A2") ] ],
      { "https://a/1" => RuntimeError.new("Tavily extract timed out"), "https://a/2" => "content-a2" }
    )
    llm = FakeLlm.new(
      { "https://a/2" => listing(company: "Survivor") },
      { "https://a/2" => "content-a2" }
    )

    jobs = Searcher.call(
      target_roles: [ "Engineer" ], preferred_cities: [ "Remote" ], mode_filter: [],
      limit: 10, freshness_days: 14, llm: llm, search_client: search_client
    )

    assert_equal [ "Survivor" ], jobs.map { |j| j[:company] }
  end

  test "builds job attributes from structured output" do
    url = "https://boards.acme.com/jobs/1"
    search_client = FakeSearchClient.new([ [ SearchResult.new(url: url, title: "A") ] ], { url => "content-a" })
    llm = FakeLlm.new(
      { url => listing(company: "Acme Corp", title: "Senior Engineer", location: "Remote", mode: "remote",
                        published_date: "2026-08-10", salary: "$150k-$180k") },
      { url => "content-a" }
    )

    jobs = Searcher.call(
      target_roles: [ "Engineer" ], preferred_cities: [ "Remote" ], mode_filter: [],
      limit: 10, freshness_days: 14, llm: llm, search_client: search_client
    )
    job = jobs.first

    assert_equal "Acme Corp", job[:company]
    assert_equal "Senior Engineer", job[:title]
    assert_equal "remote", job[:mode]
    assert_equal url, job[:url]
    assert_equal "boards.acme.com", job[:website]
    assert_equal Date.new(2026, 8, 10), job[:published_date]
    assert_equal "$150k-$180k", job[:salary]
  end

  test "falls back gracefully on an unparseable published date" do
    url = "https://a/1"
    search_client = FakeSearchClient.new([ [ SearchResult.new(url: url, title: "A") ] ], { url => "content-a" })
    llm = FakeLlm.new({ url => listing(published_date: "not a date") }, { url => "content-a" })

    jobs = Searcher.call(
      target_roles: [ "Engineer" ], preferred_cities: [ "Remote" ], mode_filter: [],
      limit: 10, freshness_days: 14, llm: llm, search_client: search_client
    )

    assert_nil jobs.first[:published_date]
  end

  test "parse_mode recognizes common on-site phrasings" do
    assert_equal "on_site", Searcher.send(:parse_mode, "Onsite")
    assert_equal "on_site", Searcher.send(:parse_mode, "In Office")
    assert_equal "on_site", Searcher.send(:parse_mode, "on-site")
  end

  test "parse_mode recognizes common remote phrasings" do
    assert_equal "remote", Searcher.send(:parse_mode, "Remote")
    assert_equal "remote", Searcher.send(:parse_mode, "Work From Home")
  end

  test "parse_mode recognizes hybrid" do
    assert_equal "hybrid", Searcher.send(:parse_mode, "Hybrid (2 days/week in office)")
  end

  test "parse_mode defaults unrecognized text to on_site, not remote" do
    assert_equal "on_site", Searcher.send(:parse_mode, "flexible")
  end

  test "parse_mode does not match a negated 'remote' as remote" do
    assert_equal "on_site", Searcher.send(:parse_mode, "On-site role, not remote")
    assert_equal "on_site", Searcher.send(:parse_mode, "Not a remote position")
    assert_equal "on_site", Searcher.send(:parse_mode, "Non-remote, in-office role")
  end

  test "build_query includes a minimum salary hint when given" do
    query = Searcher.send(:build_query, "Engineer", [], [], 150_000)
    assert_includes query, "150000"
  end

  test "build_query omits the salary hint when not given" do
    query = Searcher.send(:build_query, "Engineer", [], [], nil)
    assert_not_includes query.downcase, "salary"
  end
end
