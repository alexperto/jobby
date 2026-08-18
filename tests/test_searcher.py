from datetime import date

from app.models import Mode
from app.schemas import JobListingExtraction
from app.searcher import _build_query, _parse_mode, search_jobs
from app.tavily_client import SearchResult


class FakeSearchClient:
    """Conforms to app.tavily_client.Searcher. Each call to `search` pops
    the next canned result list, in call order."""

    def __init__(self, results_per_call, content_by_url=None):
        self._results_per_call = list(results_per_call)
        self._content_by_url = content_by_url or {}
        self.search_calls: list[str] = []
        self.max_results_calls: list[int] = []
        self.days_calls: list[int | None] = []
        self.extract_calls: list[str] = []

    def search(self, query, max_results, days=None):
        self.search_calls.append(query)
        self.max_results_calls.append(max_results)
        self.days_calls.append(days)
        return self._results_per_call.pop(0)

    def extract(self, url):
        self.extract_calls.append(url)
        content = self._content_by_url[url]
        if isinstance(content, Exception):
            raise content
        return content


class FakeLLM:
    """Conforms to app.llm.Extractor. Matches a canned response by finding
    which URL's content is embedded in the prompt."""

    def __init__(self, response_by_url, content_by_url):
        self._response_by_url = response_by_url
        self._content_by_url = content_by_url
        self.calls = []

    def extract(self, prompt, schema):
        self.calls.append((prompt, schema))
        for url, content in self._content_by_url.items():
            if isinstance(content, str) and content in prompt:
                response = self._response_by_url[url]
                if isinstance(response, Exception):
                    raise response
                return response
        raise AssertionError(f"No canned response matches prompt: {prompt!r}")


def listing(**overrides) -> JobListingExtraction:
    defaults = dict(
        company="Acme Corp",
        title="Senior Engineer",
        location="Remote",
        mode="remote",
        published_date="2026-08-10",
        description_summary="Build things.",
        minimum_requirements="5+ years Python",
        salary="$150k-$180k",
    )
    defaults.update(overrides)
    return JobListingExtraction(**defaults)


def test_search_jobs_does_one_search_per_target_role():
    search_client = FakeSearchClient(
        results_per_call=[
            [SearchResult(url="https://a/1", title="A")],
            [SearchResult(url="https://b/1", title="B")],
        ],
        content_by_url={"https://a/1": "content-a", "https://b/1": "content-b"},
    )
    llm = FakeLLM(
        response_by_url={
            "https://a/1": listing(company="A"),
            "https://b/1": listing(company="B"),
        },
        content_by_url={"https://a/1": "content-a", "https://b/1": "content-b"},
    )

    jobs = search_jobs(
        target_roles=["Engineer", "Developer"],
        preferred_cities=["Remote"],
        mode_filter=[],
        limit=10,
        freshness_days=14,
        llm=llm,
        search_client=search_client,
    )

    assert len(search_client.search_calls) == 2
    assert {job.company for job in jobs} == {"A", "B"}


def test_search_jobs_passes_freshness_days_as_a_real_recency_filter():
    search_client = FakeSearchClient(
        results_per_call=[[SearchResult(url="https://a/1", title="A")]],
        content_by_url={"https://a/1": "content-a"},
    )
    llm = FakeLLM(
        response_by_url={"https://a/1": listing()},
        content_by_url={"https://a/1": "content-a"},
    )

    search_jobs(
        target_roles=["Engineer"],
        preferred_cities=["Remote"],
        mode_filter=[],
        limit=10,
        freshness_days=21,
        llm=llm,
        search_client=search_client,
    )

    assert search_client.days_calls == [21]


def test_search_jobs_dedupes_the_same_url_across_roles_before_extracting():
    search_client = FakeSearchClient(
        results_per_call=[
            [SearchResult(url="https://a/1", title="A")],
            [SearchResult(url="https://a/1", title="A")],  # same url, second role
        ],
        content_by_url={"https://a/1": "content-a"},
    )
    llm = FakeLLM(
        response_by_url={"https://a/1": listing()},
        content_by_url={"https://a/1": "content-a"},
    )

    jobs = search_jobs(
        target_roles=["Engineer", "Developer"],
        preferred_cities=["Remote"],
        mode_filter=[],
        limit=10,
        freshness_days=14,
        llm=llm,
        search_client=search_client,
    )

    assert search_client.extract_calls == ["https://a/1"]
    assert len(jobs) == 1


def test_search_jobs_caps_total_results_at_limit():
    urls = [f"https://a/{i}" for i in range(5)]
    search_client = FakeSearchClient(
        results_per_call=[[SearchResult(url=u, title=u) for u in urls]],
        content_by_url={u: f"content-{u}" for u in urls},
    )
    llm = FakeLLM(
        response_by_url={u: listing(title=u) for u in urls},
        content_by_url={u: f"content-{u}" for u in urls},
    )

    jobs = search_jobs(
        target_roles=["Engineer"],
        preferred_cities=["Remote"],
        mode_filter=[],
        limit=3,
        freshness_days=14,
        llm=llm,
        search_client=search_client,
    )

    assert len(jobs) == 3
    assert len(search_client.extract_calls) == 3


def test_search_jobs_requests_only_the_remaining_budget_from_each_subsequent_role():
    search_client = FakeSearchClient(
        results_per_call=[
            [SearchResult(url="https://a/1", title="A"), SearchResult(url="https://a/2", title="A2")],
            [SearchResult(url="https://b/1", title="B")],
        ],
        content_by_url={
            "https://a/1": "content-a1",
            "https://a/2": "content-a2",
            "https://b/1": "content-b1",
        },
    )
    llm = FakeLLM(
        response_by_url={
            "https://a/1": listing(),
            "https://a/2": listing(),
            "https://b/1": listing(),
        },
        content_by_url={
            "https://a/1": "content-a1",
            "https://a/2": "content-a2",
            "https://b/1": "content-b1",
        },
    )

    search_jobs(
        target_roles=["Engineer", "Developer"],
        preferred_cities=["Remote"],
        mode_filter=[],
        limit=10,
        freshness_days=14,
        llm=llm,
        search_client=search_client,
    )

    # First call requests the full limit (10); second call requests only
    # what's left after the first role's 2 results (8).
    assert search_client.max_results_calls == [10, 8]


def test_search_jobs_skips_a_candidate_whose_extraction_fails_and_keeps_the_rest():
    search_client = FakeSearchClient(
        results_per_call=[
            [
                SearchResult(url="https://a/1", title="A"),
                SearchResult(url="https://a/2", title="A2"),
            ]
        ],
        content_by_url={
            "https://a/1": RuntimeError("Tavily extract timed out"),
            "https://a/2": "content-a2",
        },
    )
    llm = FakeLLM(
        response_by_url={"https://a/2": listing(company="Survivor")},
        content_by_url={"https://a/2": "content-a2"},
    )

    jobs = search_jobs(
        target_roles=["Engineer"],
        preferred_cities=["Remote"],
        mode_filter=[],
        limit=10,
        freshness_days=14,
        llm=llm,
        search_client=search_client,
    )

    assert [job.company for job in jobs] == ["Survivor"]


def test_search_jobs_builds_job_opportunities_from_structured_output():
    url = "https://boards.acme.com/jobs/1"
    search_client = FakeSearchClient(
        results_per_call=[[SearchResult(url=url, title="A")]],
        content_by_url={url: "content-a"},
    )
    llm = FakeLLM(
        response_by_url={
            url: listing(
                company="Acme Corp",
                title="Senior Engineer",
                location="Remote",
                mode="remote",
                published_date="2026-08-10",
                salary="$150k-$180k",
            )
        },
        content_by_url={url: "content-a"},
    )

    [job] = search_jobs(
        target_roles=["Engineer"],
        preferred_cities=["Remote"],
        mode_filter=[],
        limit=10,
        freshness_days=14,
        llm=llm,
        search_client=search_client,
    )

    assert job.company == "Acme Corp"
    assert job.title == "Senior Engineer"
    assert job.mode == Mode.remote
    assert job.url == url
    assert job.website == "boards.acme.com"
    assert job.published_date == date(2026, 8, 10)
    assert job.salary == "$150k-$180k"


def test_search_jobs_falls_back_gracefully_on_an_unparseable_published_date():
    url = "https://a/1"
    search_client = FakeSearchClient(
        results_per_call=[[SearchResult(url=url, title="A")]],
        content_by_url={url: "content-a"},
    )
    llm = FakeLLM(
        response_by_url={url: listing(published_date="not a date")},
        content_by_url={url: "content-a"},
    )

    [job] = search_jobs(
        target_roles=["Engineer"],
        preferred_cities=["Remote"],
        mode_filter=[],
        limit=10,
        freshness_days=14,
        llm=llm,
        search_client=search_client,
    )

    assert job.published_date is None


class TestParseMode:
    def test_recognizes_common_on_site_phrasings(self):
        assert _parse_mode("Onsite") == Mode.on_site
        assert _parse_mode("In Office") == Mode.on_site
        assert _parse_mode("on-site") == Mode.on_site

    def test_recognizes_common_remote_phrasings(self):
        assert _parse_mode("Remote") == Mode.remote
        assert _parse_mode("Work From Home") == Mode.remote

    def test_recognizes_hybrid(self):
        assert _parse_mode("Hybrid (2 days/week in office)") == Mode.hybrid

    def test_unrecognized_text_defaults_to_on_site_not_remote(self):
        # Defaulting to remote would put a possibly-onsite job in front of
        # a user who filtered specifically for remote listings.
        assert _parse_mode("flexible") == Mode.on_site


class TestBuildQuery:
    def test_includes_a_minimum_salary_hint_when_given(self):
        query = _build_query("Engineer", [], [], min_salary=150_000)
        assert "150000" in query

    def test_omits_the_salary_hint_when_not_given(self):
        query = _build_query("Engineer", [], [], min_salary=None)
        assert "salary" not in query.lower()
