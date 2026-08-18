"""Step 1: turn a resume into characteristics + target_roles.

`llm` only needs to satisfy app.llm.Extractor — tests pass a fake.
"""

from __future__ import annotations

from app.llm import Extractor
from app.schemas import ProfileExtraction

PROMPT_TEMPLATE = """You are helping a job seeker figure out what roles to \
search for. Given their resume below, extract their key characteristics \
(skills, years of experience, seniority level, a one-line summary) and \
suggest a list of specific job titles ("target roles") that fit their \
background — including titles they may not have held yet but are \
realistically qualified for (e.g. a Software Engineer's resume might \
suggest "Senior Software Engineer", "Staff Engineer", "Backend Developer").

Resume:
---
{resume}
---
"""


def profilize(resume_text: str, llm: Extractor) -> ProfileExtraction:
    prompt = PROMPT_TEMPLATE.format(resume=resume_text)
    return llm.extract(prompt, ProfileExtraction)
