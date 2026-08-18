"""Persistence models.

Profile is a singleton: exactly one row is expected to exist at a time.
JobOpportunity rows are deduplicated on (company, title, location) — see
`app.dedup.dedup_key`.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from enum import Enum

from sqlalchemy import JSON, Column
from sqlmodel import Field, SQLModel


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class Mode(str, Enum):
    remote = "remote"
    on_site = "on_site"
    hybrid = "hybrid"


class JobState(str, Enum):
    new = "new"
    applied = "applied"
    saved = "saved"
    discarded = "discarded"
    irrelevant = "irrelevant"


class Profile(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    resume_text: str = ""
    characteristics: dict = Field(default_factory=dict, sa_column=Column(JSON))
    target_roles: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    min_salary: int | None = None
    preferred_cities: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    # Values from Mode, stored as plain strings (JSON columns don't round-trip
    # Enum members cleanly). "remote" is never stored here — it's implicit.
    preferred_modes: list[str] = Field(default_factory=list, sa_column=Column(JSON))
    updated_at: datetime = Field(default_factory=_utcnow)


class JobOpportunity(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    company: str
    title: str
    location: str
    mode: Mode
    website: str
    url: str
    published_date: date | None = None
    created_at: datetime = Field(default_factory=_utcnow)
    description_summary: str = ""
    minimum_requirements: str | None = None
    salary: str | None = None
    state: JobState = Field(default=JobState.new)
    score: float | None = None
    # `dedup.dedup_key(company, title, location)` joined into one string.
    # A DB-level unique index (not just an app-level check-then-insert) is
    # what makes JobRepository.add_if_new race-safe under concurrent
    # requests. Set by the repository right before insert.
    dedup_key: str = Field(default="", index=True, unique=True)
