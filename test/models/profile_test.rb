require "test_helper"

class ProfileTest < ActiveSupport::TestCase
  test "current creates the singleton profile on first access" do
    assert_equal 0, Profile.count
    profile = Profile.current
    assert profile.persisted?
    assert_equal 1, Profile.count
  end

  test "current returns the same row on subsequent calls, not a new one" do
    first = Profile.current
    second = Profile.current

    assert_equal first.id, second.id
    assert_equal 1, Profile.count
  end

  test "current always creates at a fixed id, so a genuine race collides on the PK instead of silently duplicating" do
    profile = Profile.current
    assert_equal Profile::SINGLETON_ID, profile.id
  end

  test "recovers from a create race (another request wins) without raising or duplicating the row" do
    # The "other process" already created the singleton row.
    Profile.create!(id: Profile::SINGLETON_ID)

    # Simulate the TOCTOU window: this caller's first `find` doesn't see
    # that row yet, so it proceeds to `create!` — which then collides with
    # the real row on the PK. The second `find` (inside the rescue) should
    # succeed normally.
    real_find = Profile.method(:find)
    call_count = 0
    racy_find = lambda do |id|
      call_count += 1
      call_count == 1 ? raise(ActiveRecord::RecordNotFound) : real_find.call(id)
    end

    Profile.stub :find, racy_find do
      profile = Profile.current
      assert_equal Profile::SINGLETON_ID, profile.id
    end

    assert_equal 1, Profile.count
  end

  test "characteristics and list fields round-trip through JSON columns" do
    profile = Profile.current
    profile.update!(
      characteristics: { "seniority" => "senior", "skills" => [ "ruby", "rails" ] },
      target_roles: [ "Senior Backend Engineer", "Staff Engineer" ],
      preferred_cities: [ "Remote", "Austin" ],
      preferred_modes: [ "hybrid" ]
    )

    reloaded = Profile.find(profile.id)
    assert_equal "senior", reloaded.characteristics["seniority"]
    assert_equal [ "Senior Backend Engineer", "Staff Engineer" ], reloaded.target_roles
    assert_equal [ "Remote", "Austin" ], reloaded.preferred_cities
    assert_equal [ "hybrid" ], reloaded.preferred_modes
  end
end
