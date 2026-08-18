import pytest
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine

from app.db import get_session
from app.main import app, llm_dependency, search_dependency
from app.schemas import Characteristics, JobListingExtraction, ProfileExtraction
from app.tavily_client import SearchResult


class FakeLLM:
    def __init__(self, response):
        self.response = response

    def extract(self, prompt, schema):
        return self.response


class FakeSearchClient:
    def __init__(self, results, content="content"):
        self.results = results
        self.content = content
        self.queries: list[str] = []

    def search(self, query, max_results, days=None):
        self.queries.append(query)
        return self.results

    def extract(self, url):
        return self.content


@pytest.fixture()
def client():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    SQLModel.metadata.create_all(engine)

    def override_get_session():
        with Session(engine) as session:
            yield session

    app.dependency_overrides[get_session] = override_get_session
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


def test_profile_page_loads(client):
    response = client.get("/profile")
    assert response.status_code == 200
    assert "Profile" in response.text


def test_opportunities_page_prompts_to_complete_profile_when_empty(client):
    response = client.get("/opportunities")
    assert response.status_code == 200
    assert "Complete your profile first" in response.text


def test_history_page_loads_with_no_jobs(client):
    response = client.get("/history")
    assert response.status_code == 200
    assert "No job opportunities recorded yet." in response.text


def test_saving_a_resume_runs_profilize_and_redirects_to_profile(client):
    extraction = ProfileExtraction(
        characteristics=Characteristics(skills=["python"], seniority="senior"),
        target_roles=["Senior Backend Engineer"],
    )
    app.dependency_overrides[llm_dependency] = lambda: FakeLLM(extraction)

    response = client.post(
        "/profile/resume",
        data={"resume_text": "Senior backend engineer, 8 years Python."},
        follow_redirects=True,
    )

    assert response.status_code == 200
    assert "Senior Backend Engineer" in response.text


def test_searching_persists_and_renders_a_job_card(client):
    profile_extraction = ProfileExtraction(
        characteristics=Characteristics(skills=[]), target_roles=["Engineer"]
    )
    app.dependency_overrides[llm_dependency] = lambda: FakeLLM(profile_extraction)
    client.post(
        "/profile/resume",
        data={"resume_text": "Backend engineer."},
        follow_redirects=True,
    )

    listing_extraction = JobListingExtraction(
        company="Acme Corp",
        title="Senior Engineer",
        location="Remote",
        mode="remote",
        description_summary="Build things.",
    )
    app.dependency_overrides[llm_dependency] = lambda: FakeLLM(listing_extraction)
    app.dependency_overrides[search_dependency] = lambda: FakeSearchClient(
        [SearchResult(url="https://a/1", title="A")]
    )

    response = client.post("/opportunities/search", data={"limit": 10, "freshness_days": 14})

    assert response.status_code == 200
    assert "Acme Corp" in response.text

    history = client.get("/history")
    assert "Acme Corp" in history.text


def test_updating_a_jobs_state_to_applied_removes_it_from_the_backlog_response(client):
    profile_extraction = ProfileExtraction(
        characteristics=Characteristics(skills=[]), target_roles=["Engineer"]
    )
    app.dependency_overrides[llm_dependency] = lambda: FakeLLM(profile_extraction)
    client.post(
        "/profile/resume", data={"resume_text": "Backend engineer."}, follow_redirects=True
    )

    listing_extraction = JobListingExtraction(
        company="Acme Corp",
        title="Senior Engineer",
        location="Remote",
        mode="remote",
        description_summary="Build things.",
    )
    app.dependency_overrides[llm_dependency] = lambda: FakeLLM(listing_extraction)
    app.dependency_overrides[search_dependency] = lambda: FakeSearchClient(
        [SearchResult(url="https://a/1", title="A")]
    )
    client.post("/opportunities/search", data={"limit": 10, "freshness_days": 14})

    opportunities = client.get("/opportunities")
    job_id = opportunities.text.split('id="job-')[1].split('"')[0]

    response = client.post(f"/opportunities/{job_id}/state?new_state=applied")
    assert response.status_code == 200
    assert response.text.strip() == ""


def test_updating_state_of_a_nonexistent_job_returns_404(client):
    response = client.post("/opportunities/999/state?new_state=applied")
    assert response.status_code == 404


def test_search_passes_the_profiles_min_salary_through_to_the_search_query(client):
    profile_extraction = ProfileExtraction(
        characteristics=Characteristics(skills=[]), target_roles=["Engineer"]
    )
    app.dependency_overrides[llm_dependency] = lambda: FakeLLM(profile_extraction)
    client.post(
        "/profile/resume", data={"resume_text": "Backend engineer."}, follow_redirects=True
    )
    client.post("/profile/preferences", data={"min_salary": 150_000}, follow_redirects=True)

    listing_extraction = JobListingExtraction(
        company="Acme Corp",
        title="Senior Engineer",
        location="Remote",
        mode="remote",
        description_summary="Build things.",
    )
    app.dependency_overrides[llm_dependency] = lambda: FakeLLM(listing_extraction)
    search_client = FakeSearchClient([SearchResult(url="https://a/1", title="A")])
    app.dependency_overrides[search_dependency] = lambda: search_client

    client.post("/opportunities/search", data={"limit": 10, "freshness_days": 14})

    assert any("150000" in q for q in search_client.queries)
