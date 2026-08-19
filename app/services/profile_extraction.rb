# The structured output LlmClient asks the model to fill in for Profilizer:
# a resume's characteristics plus the target_roles list to search for.
class ProfileExtraction
  include ActiveModel::Model

  attr_accessor :characteristics, :target_roles

  def self.json_schema
    {
      type: "object",
      properties: {
        characteristics: Characteristics.json_schema,
        target_roles: { type: "array", items: { type: "string" } }
      },
      required: %w[characteristics target_roles],
      additionalProperties: false
    }
  end

  def self.from_hash(hash)
    new(
      characteristics: Characteristics.from_hash(hash["characteristics"]),
      target_roles: hash["target_roles"] || []
    )
  end
end
