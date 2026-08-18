"""Persistence-layer seams for Profile and JobOpportunity.

JobRepository.add_if_new is where the dedup decision from grilling lands:
duplicates (same company/title/location) are skipped, and the existing row
is never touched — a background search run must not clobber a user-set
state or score.
"""

from __future__ import annotations

from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, col, func, select

from app.dedup import dedup_key
from app.models import JobOpportunity, JobState, Profile

BACKLOG_STATES = (JobState.new, JobState.saved)

# Profile is a singleton; this is its one row's id.
PROFILE_ID = 1


class ProfileRepository:
    def __init__(self, session: Session):
        self.session = session

    def get(self) -> Profile | None:
        return self.session.get(Profile, PROFILE_ID)

    def _get_or_create(self) -> Profile:
        profile = self.get()
        if profile is None:
            profile = Profile(id=PROFILE_ID)
            self.session.add(profile)
        return profile

    def save_resume(
        self, *, resume_text: str, characteristics: dict, target_roles: list[str]
    ) -> Profile:
        profile = self._get_or_create()
        profile.resume_text = resume_text
        profile.characteristics = characteristics
        profile.target_roles = target_roles
        self.session.add(profile)
        self.session.commit()
        self.session.refresh(profile)
        return profile

    def save_preferences(
        self,
        *,
        min_salary: int | None,
        preferred_cities: list[str],
        preferred_modes: list[str],
    ) -> Profile:
        profile = self._get_or_create()
        profile.min_salary = min_salary
        profile.preferred_cities = preferred_cities
        profile.preferred_modes = preferred_modes
        self.session.add(profile)
        self.session.commit()
        self.session.refresh(profile)
        return profile


class JobRepository:
    def __init__(self, session: Session):
        self.session = session

    def add_if_new(self, job: JobOpportunity) -> bool:
        job.dedup_key = "|".join(dedup_key(job.company, job.title, job.location))
        self.session.add(job)
        try:
            self.session.commit()
        except IntegrityError:
            # The unique index on dedup_key is the actual dedup guarantee —
            # atomic at the DB level, so two concurrent requests inserting
            # the same job can't both slip past a check-then-insert race.
            self.session.rollback()
            return False
        return True

    def list_backlog(self, *, include_all_states: bool = False) -> list[JobOpportunity]:
        statement = select(JobOpportunity)
        if not include_all_states:
            statement = statement.where(col(JobOpportunity.state).in_(BACKLOG_STATES))
        return list(self.session.exec(statement).all())

    def list_history(
        self, *, page: int, page_size: int
    ) -> tuple[list[JobOpportunity], int]:
        total = self.session.exec(
            select(func.count()).select_from(JobOpportunity)
        ).one()
        statement = (
            select(JobOpportunity)
            # published_date is nullable and not unique — id as a secondary
            # key keeps page ordering stable even when dates tie or a new
            # row is inserted between two page requests.
            .order_by(
                col(JobOpportunity.published_date).desc(),
                col(JobOpportunity.id).desc(),
            )
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
        return list(self.session.exec(statement).all()), total

    def update_state(self, job_id: int, state: JobState) -> None:
        job = self.session.get(JobOpportunity, job_id)
        if job is None:
            raise ValueError(f"No job with id {job_id}")
        job.state = state
        self.session.add(job)
        self.session.commit()
