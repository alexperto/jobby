from app.profilize import profilize
from app.schemas import Characteristics, ProfileExtraction


class FakeLLM:
    """A fake conforming to app.llm.Extractor's `extract` signature."""

    def __init__(self, response: ProfileExtraction):
        self.response = response
        self.calls: list[tuple[str, type]] = []

    def extract(self, prompt, schema):
        self.calls.append((prompt, schema))
        return self.response


def test_profilize_returns_the_llms_structured_extraction():
    canned = ProfileExtraction(
        characteristics=Characteristics(
            skills=["python", "fastapi"],
            years_experience=8,
            seniority="senior",
            summary="Backend engineer.",
        ),
        target_roles=["Senior Backend Engineer", "Staff Engineer"],
    )
    llm = FakeLLM(canned)

    result = profilize("Senior backend engineer, 8 years Python.", llm)

    assert result == canned


def test_profilize_sends_the_resume_text_and_the_profile_extraction_schema():
    llm = FakeLLM(
        ProfileExtraction(characteristics=Characteristics(skills=[]), target_roles=[])
    )

    profilize("Senior backend engineer, 8 years Python.", llm)

    assert len(llm.calls) == 1
    prompt, schema = llm.calls[0]
    assert "Senior backend engineer, 8 years Python." in prompt
    assert schema is ProfileExtraction
