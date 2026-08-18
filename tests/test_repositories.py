from datetime import date

from app.models import JobOpportunity, JobState, Mode
from app.repositories import JobRepository, ProfileRepository


class TestProfileRepository:
    def test_get_returns_none_when_no_profile_exists_yet(self, session):
        repo = ProfileRepository(session)
        assert repo.get() is None

    def test_save_resume_creates_the_singleton_profile(self, session):
        repo = ProfileRepository(session)
        repo.save_resume(
            resume_text="Senior backend engineer, 8 years Python.",
            characteristics={"skills": ["python"], "seniority": "senior"},
            target_roles=["Senior Backend Engineer", "Staff Engineer"],
        )
        profile = repo.get()
        assert profile is not None
        assert profile.resume_text == "Senior backend engineer, 8 years Python."
        assert profile.target_roles == ["Senior Backend Engineer", "Staff Engineer"]
        assert profile.characteristics["seniority"] == "senior"

    def test_save_resume_again_overwrites_the_same_row_rather_than_creating_a_second_one(
        self, session
    ):
        repo = ProfileRepository(session)
        repo.save_resume(
            resume_text="v1", characteristics={}, target_roles=["Engineer"]
        )
        repo.save_resume(
            resume_text="v2", characteristics={}, target_roles=["Staff Engineer"]
        )

        profile = repo.get()
        assert profile.resume_text == "v2"
        assert profile.target_roles == ["Staff Engineer"]

    def test_save_preferences_updates_the_existing_profile(self, session):
        repo = ProfileRepository(session)
        repo.save_resume(resume_text="v1", characteristics={}, target_roles=[])
        repo.save_preferences(
            min_salary=150_000,
            preferred_cities=["Remote", "Austin"],
            preferred_modes=["hybrid"],
        )

        profile = repo.get()
        assert profile.min_salary == 150_000
        assert profile.preferred_cities == ["Remote", "Austin"]
        assert profile.preferred_modes == ["hybrid"]


def make_job(**overrides) -> JobOpportunity:
    defaults = dict(
        company="Acme Corp",
        title="Senior Engineer",
        location="Remote",
        mode=Mode.remote,
        website="linkedin.com",
        url="https://linkedin.com/jobs/1",
        published_date=date(2026, 8, 1),
        description_summary="Build things.",
    )
    defaults.update(overrides)
    return JobOpportunity(**defaults)


class TestJobRepository:
    def test_add_if_new_inserts_a_job_that_does_not_exist_yet(self, session):
        repo = JobRepository(session)
        inserted = repo.add_if_new(make_job())
        assert inserted is True
        assert len(repo.list_backlog()) == 1

    def test_add_if_new_skips_a_duplicate_on_company_title_location(self, session):
        repo = JobRepository(session)
        repo.add_if_new(make_job(state=JobState.applied, score=0.9))

        duplicate = make_job(
            company="  ACME corp ",
            title="senior engineer",
            location="REMOTE",
            url="https://linkedin.com/jobs/1-repost",
            description_summary="A different description.",
        )
        inserted = repo.add_if_new(duplicate)

        assert inserted is False
        jobs = repo.list_backlog(include_all_states=True)
        assert len(jobs) == 1
        # The original row's state/score must survive untouched (R3-Q3).
        assert jobs[0].state == JobState.applied
        assert jobs[0].score == 0.9
        assert jobs[0].description_summary == "Build things."

    def test_add_if_new_allows_the_same_title_at_a_different_location(self, session):
        repo = JobRepository(session)
        repo.add_if_new(make_job(location="Remote"))
        inserted = repo.add_if_new(make_job(location="New York", url="https://x/2"))
        assert inserted is True
        assert len(repo.list_backlog(include_all_states=True)) == 2

    def test_list_backlog_only_returns_new_and_saved_jobs(self, session):
        repo = JobRepository(session)
        repo.add_if_new(make_job(url="https://x/1", state=JobState.new))
        repo.add_if_new(make_job(url="https://x/2", state=JobState.saved, title="B"))
        repo.add_if_new(
            make_job(url="https://x/3", state=JobState.applied, title="C")
        )
        repo.add_if_new(
            make_job(url="https://x/4", state=JobState.discarded, title="D")
        )

        backlog_titles = {job.title for job in repo.list_backlog()}
        assert backlog_titles == {"Senior Engineer", "B"}

    def test_list_history_paginates_newest_published_first(self, session):
        repo = JobRepository(session)
        for i in range(3):
            repo.add_if_new(
                make_job(
                    url=f"https://x/{i}",
                    title=f"Job {i}",
                    published_date=date(2026, 8, 1 + i),
                )
            )

        page, total = repo.list_history(page=1, page_size=2)
        assert total == 3
        assert [job.title for job in page] == ["Job 2", "Job 1"]

        page2, total2 = repo.list_history(page=2, page_size=2)
        assert total2 == 3
        assert [job.title for job in page2] == ["Job 0"]

    def test_list_history_breaks_ties_on_id_for_stable_ordering(self, session):
        repo = JobRepository(session)
        same_date = date(2026, 8, 1)
        for i in range(3):
            repo.add_if_new(
                make_job(url=f"https://x/{i}", title=f"Job {i}", published_date=same_date)
            )

        page, total = repo.list_history(page=1, page_size=10)
        assert total == 3
        # Same published_date for all three: newest inserted (highest id)
        # must still sort first, deterministically, not by insertion luck.
        assert [job.title for job in page] == ["Job 2", "Job 1", "Job 0"]

    def test_add_if_new_is_race_safe_via_a_db_level_unique_constraint(self, session):
        repo = JobRepository(session)
        first = make_job()
        second = make_job(url="https://x/2")  # same company/title/location

        # Simulates two concurrent requests both passing the (removed)
        # check-then-insert race: neither has committed yet when both are
        # added to the session.
        assert repo.add_if_new(first) is True
        assert repo.add_if_new(second) is False
        assert len(repo.list_backlog(include_all_states=True)) == 1

    def test_update_state_changes_an_existing_jobs_state(self, session):
        repo = JobRepository(session)
        repo.add_if_new(make_job())
        job = repo.list_backlog()[0]

        repo.update_state(job.id, JobState.applied)

        assert repo.list_backlog(include_all_states=True)[0].state == JobState.applied
