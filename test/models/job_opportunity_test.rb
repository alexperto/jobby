require "test_helper"

class JobOpportunityTest < ActiveSupport::TestCase
  test "requires company, title, location, website, and url" do
    job = JobOpportunity.new
    assert_not job.valid?
    %w[company title location website url].each do |attr|
      assert_includes job.errors.attribute_names, attr.to_sym
    end
  end

  test "rejects a url that isn't http(s) — e.g. a javascript: scheme from untrusted search data" do
    job = JobOpportunity.new(make_job(url: "javascript:alert(1)"))
    assert_not job.valid?
    assert_includes job.errors.attribute_names, :url
  end

  test "accepts http and https urls" do
    assert JobOpportunity.new(make_job(url: "http://example.com/jobs/1")).valid?
    assert JobOpportunity.new(make_job(url: "https://example.com/jobs/1")).valid?
  end

  test "dedup_key is derived from company, title, and location" do
    job = JobOpportunity.new(make_job(company: "Acme Corp", title: "Senior Engineer", location: "Remote"))
    job.valid?
    assert_equal "acme corp|senior engineer|remote", job.dedup_key
  end

  test "dedup_key normalizes case and whitespace" do
    job = JobOpportunity.new(make_job(company: "  ACME   Corp ", title: "SENIOR ENGINEER", location: "remote"))
    job.valid?
    assert_equal "acme corp|senior engineer|remote", job.dedup_key
  end

  test "add_if_new inserts a job that does not exist yet" do
    assert JobOpportunity.add_if_new(make_job)
    assert_equal 1, JobOpportunity.count
  end

  test "add_if_new skips a duplicate on company/title/location and leaves the existing row untouched" do
    JobOpportunity.add_if_new(make_job(state: "applied", score: 0.9))

    duplicate = make_job(
      company: "  ACME corp ",
      title: "senior engineer",
      location: "REMOTE",
      url: "https://linkedin.com/jobs/1-repost",
      description_summary: "A different description."
    )
    inserted = JobOpportunity.add_if_new(duplicate)

    assert_not inserted
    assert_equal 1, JobOpportunity.count
    original = JobOpportunity.first
    assert_equal "applied", original.state
    assert_equal 0.9, original.score
    assert_equal "Build things.", original.description_summary
  end

  test "add_if_new allows the same title at a different location" do
    JobOpportunity.add_if_new(make_job(location: "Remote"))
    inserted = JobOpportunity.add_if_new(make_job(location: "New York", url: "https://x/2"))

    assert inserted
    assert_equal 2, JobOpportunity.count
  end

  test "the DB-level unique index is the actual dedup guarantee, not just the validation" do
    # insert! bypasses validations/callbacks entirely — simulating two
    # concurrent requests that both raced past the validation's own
    # check-then-insert before either committed. Only the DB constraint
    # can stop the second one.
    attrs = make_job.merge(dedup_key: "acme corp|senior engineer|remote")
    JobOpportunity.insert!(attrs)

    assert_raises(ActiveRecord::RecordNotUnique) do
      JobOpportunity.insert!(attrs.merge(url: "https://linkedin.com/jobs/1-repost"))
    end
    assert_equal 1, JobOpportunity.count
  end

  test "backlog only returns new and saved jobs" do
    JobOpportunity.create!(make_job(url: "https://x/1", state: "new"))
    JobOpportunity.create!(make_job(url: "https://x/2", state: "saved", title: "B"))
    JobOpportunity.create!(make_job(url: "https://x/3", state: "applied", title: "C"))
    JobOpportunity.create!(make_job(url: "https://x/4", state: "discarded", title: "D"))

    assert_equal [ "B", "Senior Engineer" ], JobOpportunity.backlog.pluck(:title).sort
  end

  test "history_page paginates newest published first" do
    3.times do |i|
      JobOpportunity.create!(make_job(url: "https://x/#{i}", title: "Job #{i}", published_date: Date.new(2026, 8, 1 + i)))
    end

    page, total, current_page = JobOpportunity.history_page(page: 1, page_size: 2)
    assert_equal 3, total
    assert_equal 1, current_page
    assert_equal [ "Job 2", "Job 1" ], page.map(&:title)

    page2, total2, current_page2 = JobOpportunity.history_page(page: 2, page_size: 2)
    assert_equal 3, total2
    assert_equal 2, current_page2
    assert_equal [ "Job 0" ], page2.map(&:title)
  end

  test "history_page breaks ties on id for stable ordering" do
    same_date = Date.new(2026, 8, 1)
    3.times do |i|
      JobOpportunity.create!(make_job(url: "https://x/#{i}", title: "Job #{i}", published_date: same_date))
    end

    page, total, = JobOpportunity.history_page(page: 1, page_size: 10)
    assert_equal 3, total
    assert_equal [ "Job 2", "Job 1", "Job 0" ], page.map(&:title)
  end

  test "history_page clamps a too-low page (0, negative, or non-numeric) up to page 1" do
    JobOpportunity.create!(make_job)

    [ 0, -5 ].each do |bad_page|
      page, _total, current_page = JobOpportunity.history_page(page: bad_page, page_size: 10)
      assert_equal 1, current_page, "page #{bad_page.inspect} should clamp to 1"
      assert_equal 1, page.length
    end
  end

  test "history_page clamps a too-high page down to the last real page, instead of returning an empty, misleading result" do
    3.times { |i| JobOpportunity.create!(make_job(url: "https://x/#{i}", title: "Job #{i}")) }

    page, total, current_page = JobOpportunity.history_page(page: 999, page_size: 2)

    assert_equal 3, total
    assert_equal 2, current_page # last page given page_size 2 and 3 records
    assert_equal 1, page.length
  end

  test "state defaults to new" do
    job = JobOpportunity.create!(make_job)
    assert_equal "new", job.state
  end
end
