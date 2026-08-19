require "test_helper"

class ProfilizerTest < ActiveSupport::TestCase
  class FakeLlm
    attr_reader :calls

    def initialize(response)
      @response = response
      @calls = []
    end

    def extract(prompt:, schema:)
      @calls << [ prompt, schema ]
      @response
    end
  end

  test "returns the llm's structured extraction" do
    canned = ProfileExtraction.new(
      characteristics: Characteristics.new(
        skills: %w[ruby rails], years_experience: 8, seniority: "senior", summary: "Backend engineer."
      ),
      target_roles: [ "Senior Backend Engineer", "Staff Engineer" ]
    )
    llm = FakeLlm.new(canned)

    result = Profilizer.call(resume_text: "Senior backend engineer, 8 years Ruby.", llm: llm)

    assert_same canned, result
  end

  test "sends the resume text and the ProfileExtraction schema" do
    llm = FakeLlm.new(ProfileExtraction.new(characteristics: Characteristics.new(skills: []), target_roles: []))

    Profilizer.call(resume_text: "Senior backend engineer, 8 years Ruby.", llm: llm)

    assert_equal 1, llm.calls.length
    prompt, schema = llm.calls.first
    assert_includes prompt, "Senior backend engineer, 8 years Ruby."
    assert_equal ProfileExtraction, schema
  end
end
