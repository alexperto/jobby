# A search result. Deduplicated on (company, title, location) — see
# #set_dedup_key. The unique index on dedup_key is the actual dedup
# guarantee (atomic at the DB level); the uniqueness validation just gives
# a fast, friendly path that avoids a round-trip to the DB in the common
# (non-racing) case.
class JobOpportunity < ApplicationRecord
  BACKLOG_STATES = %w[new saved].freeze
  MODES = %w[remote on_site hybrid].freeze
  # Deliberately a plain array + inclusion validation, not `enum :state`:
  # Rails' enum macro defines a class method named after each value, and
  # `enum :state, { new: "new", ... }` would silently replace
  # ActiveRecord::Base.new itself. A remapped key (e.g. `pending: "new"`)
  # avoids that collision but makes `job.state` return "pending" instead
  # of "new" — drifting from the canonical vocabulary used throughout
  # plan.md and the rest of this app.
  STATES = %w[new applied saved discarded irrelevant].freeze

  before_validation :set_dedup_key

  validates :company, :title, :location, :website, :url, presence: true
  # url is rendered as a link_to href in two views. It comes from
  # web-scraped/LLM-extracted data, so it's untrusted — reject anything
  # that isn't an http(s) URL (e.g. a javascript: scheme) before it can
  # ever be persisted, rather than relying on escaping at render time.
  validates :url, format: { with: %r{\Ahttps?://\S+\z}i, message: "must be an http(s) URL" }
  validates :mode, inclusion: { in: MODES }
  validates :state, inclusion: { in: STATES }
  validates :dedup_key, uniqueness: true

  scope :backlog, -> { where(state: BACKLOG_STATES) }

  # Returns true if the job was newly inserted, false if it was a duplicate
  # (either caught by the validation, or — under a race — by the DB's
  # unique index raising RecordNotUnique). An existing row is never
  # touched: a background search run must not clobber a user-set state or
  # score.
  def self.add_if_new(attributes)
    new(attributes).save
  rescue ActiveRecord::RecordNotUnique
    false
  end

  # Returns [records, total, clamped_page]. The requested page is clamped
  # to [1, last_page] rather than trusted as-is — an out-of-range page
  # (0, negative, or past the end) would otherwise silently return an
  # empty result, which the History view can't distinguish from "no jobs
  # recorded yet" at all.
  def self.history_page(page:, page_size:)
    total = count
    last_page = [ 1, (total.to_f / page_size).ceil ].max
    current_page = page.to_i.clamp(1, last_page)

    # published_date is nullable and not unique — id as a secondary key
    # keeps page ordering stable even when dates tie or a new row is
    # inserted between two page requests.
    records = order(published_date: :desc, id: :desc)
      .offset((current_page - 1) * page_size)
      .limit(page_size)
    [ records.to_a, total, current_page ]
  end

  private

  def set_dedup_key
    self.dedup_key = [ company, title, location ]
      .map { |value| value.to_s.strip.downcase.gsub(/\s+/, " ") }
      .join("|")
  end
end
