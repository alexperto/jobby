ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock" # Object#stub, used to fake LlmClient/TavilyClient in controller tests

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...

    # Returns a plain attributes Hash (not a persisted/instantiated record) —
    # pass to JobOpportunity.new(...) or .add_if_new(...) as needed.
    def make_job(overrides = {})
      {
        company: "Acme Corp",
        title: "Senior Engineer",
        location: "Remote",
        mode: "remote",
        website: "linkedin.com",
        url: "https://linkedin.com/jobs/1",
        published_date: Date.new(2026, 8, 1),
        description_summary: "Build things."
      }.merge(overrides)
    end
  end
end
