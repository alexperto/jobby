"""Structured-output schemas the LLM is asked to fill in.

These are the shapes passed to `LLMClient.extract` — see app/profilize.py
and app/searcher.py.
"""

from __future__ import annotations

from pydantic import BaseModel


class Characteristics(BaseModel):
    skills: list[str]
    years_experience: float | None = None
    seniority: str | None = None
    summary: str | None = None


class ProfileExtraction(BaseModel):
    characteristics: Characteristics
    target_roles: list[str]


class JobListingExtraction(BaseModel):
    company: str
    title: str
    location: str
    mode: str  # "remote" | "on_site" | "hybrid"
    published_date: str | None = None  # best-effort ISO date string
    description_summary: str
    minimum_requirements: str | None = None
    salary: str | None = None
