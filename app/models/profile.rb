# The single user profile. Exactly one row is expected to exist — see
# .current. Always created at a fixed id so that two requests racing to
# create it for the first time collide on the primary key (recoverable)
# rather than silently producing two distinct singleton rows.
class Profile < ApplicationRecord
  SINGLETON_ID = 1

  def self.current
    find(SINGLETON_ID)
  rescue ActiveRecord::RecordNotFound
    begin
      create!(id: SINGLETON_ID)
    rescue ActiveRecord::RecordNotUnique
      find(SINGLETON_ID)
    end
  end
end
