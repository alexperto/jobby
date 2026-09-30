# The structured output LlmClient asks the model to fill in for Searcher,
# one per candidate job listing.
class JobListingExtraction
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :company, :string
  attribute :title, :string
  attribute :location, :string
  attribute :mode, :string
  attribute :published_date, :string # best-effort ISO date string
  attribute :description_summary, :string
  attribute :minimum_requirements, :string
  attribute :salary, :string

  def self.json_schema
    {
      type: "object",
      properties: {
        company: { type: "string" },
        title: { type: "string" },
        location: { type: "string" },
        mode: { type: "string" },
        published_date: { type: %w[string null] },
        description_summary: { type: "string" },
        minimum_requirements: { type: %w[string null] },
        salary: { type: %w[string null] }
      },
      required: %w[company title location mode published_date description_summary
                    minimum_requirements salary],
      additionalProperties: false
    }
  end

  def self.from_hash(hash)
    new((hash || {}).symbolize_keys)
  end
end
