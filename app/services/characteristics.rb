# Part of the structured output LlmClient asks the model to fill in for
# Profilizer. See ProfileExtraction.
class Characteristics
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :skills, default: -> { [] }
  attribute :years_experience, :float
  attribute :seniority, :string
  attribute :summary, :string

  def self.json_schema
    {
      type: "object",
      properties: {
        skills: { type: "array", items: { type: "string" } },
        years_experience: { type: %w[number null] },
        seniority: { type: %w[string null] },
        summary: { type: %w[string null] }
      },
      required: %w[skills years_experience seniority summary],
      additionalProperties: false
    }
  end

  def self.from_hash(hash)
    new((hash || {}).symbolize_keys)
  end
end
