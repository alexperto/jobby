require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "renders a real link for an http(s) url" do
    html = safe_external_link_to("View", "https://example.com/jobs/1")
    assert_match %r{<a .*href="https://example\.com/jobs/1"}, html
  end

  # Defense in depth: JobOpportunity validates the url format, but that
  # validation is bypassable (e.g. insert!/insert_all!/update_columns,
  # which our own test suite uses to simulate a race — see
  # test/models/job_opportunity_test.rb). This is the backstop for any
  # url that reaches a view without having gone through validation.
  test "renders plain text, not a link, for a non-http(s) url" do
    html = safe_external_link_to("View", "javascript:alert(1)")
    assert_no_match(/<a /, html)
    assert_match(/View/, html)
  end

  test "renders plain text for a blank url" do
    html = safe_external_link_to("View", nil)
    assert_no_match(/<a /, html)
  end
end
