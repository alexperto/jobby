"""Step 2: turn target_roles into stored-ready JobOpportunity candidates.

One Tavily search per target_role (seeded with well-known job-board hints),
candidate URLs deduped before extraction to control cost, capped at
`limit`, then one structured-output LLM call per surviving candidate. A
candidate whose extract/LLM call fails is skipped, not fatal to the run.

Persisting + the (company, title, location) dedup-on-store check is the
caller's job — see app.repositories.JobRepository.add_if_new.
"""

from __future__ import annotations

from datetime import date
from urllib.parse import urlparse

from app.llm import Extractor
from app.models import JobOpportunity, Mode
from app.schemas import JobListingExtraction
from app.tavily_client import Searcher

JOB_BOARD_HINTS = (
    "site:linkedin.com OR site:indeed.com OR site:glassdoor.com "
    "OR site:remoteok.com OR site:weworkremotely.com"
)

EXTRACTION_PROMPT_TEMPLATE = """Extract the job listing's attributes from the \
page content below: company, title, location, mode (remote, on_site, or \
hybrid), published date (ISO format if determinable), a short description \
summary, minimum requirements, and salary if stated.

Page content:
---
{content}
---
"""

# Substrings that identify a mode from free-text LLM output. Checked in this
# order, so "hybrid" wins over an incidental "office" mention, etc.
_MODE_ALIASES: tuple[tuple[str, Mode], ...] = (
    ("hybrid", Mode.hybrid),
    ("remote", Mode.remote),
    ("wfh", Mode.remote),
    ("work from home", Mode.remote),
    ("on-site", Mode.on_site),
    ("onsite", Mode.on_site),
    ("on site", Mode.on_site),
    ("in-office", Mode.on_site),
    ("in office", Mode.on_site),
    ("in-person", Mode.on_site),
    ("in person", Mode.on_site),
    ("office", Mode.on_site),
)


def search_jobs(
    *,
    target_roles: list[str],
    preferred_cities: list[str],
    mode_filter: list[str],
    limit: int,
    freshness_days: int,
    llm: Extractor,
    search_client: Searcher,
    min_salary: int | None = None,
) -> list[JobOpportunity]:
    candidates = _collect_candidate_urls(
        target_roles=target_roles,
        preferred_cities=preferred_cities,
        mode_filter=mode_filter,
        freshness_days=freshness_days,
        limit=limit,
        search_client=search_client,
        min_salary=min_salary,
    )

    jobs = []
    for url in candidates:
        try:
            content = search_client.extract(url)
            prompt = EXTRACTION_PROMPT_TEMPLATE.format(content=content)
            listing = llm.extract(prompt, JobListingExtraction)
        except Exception:
            # One bad candidate (a timed-out extract, an unparseable
            # response) shouldn't discard every candidate already found.
            continue
        jobs.append(_to_job_opportunity(listing, url))
    return jobs


def _collect_candidate_urls(
    *,
    target_roles: list[str],
    preferred_cities: list[str],
    mode_filter: list[str],
    freshness_days: int,
    limit: int,
    search_client: Searcher,
    min_salary: int | None,
) -> list[str]:
    seen: set[str] = set()
    urls: list[str] = []
    for role in target_roles:
        if len(urls) >= limit:
            break
        query = _build_query(role, preferred_cities, mode_filter, min_salary)
        remaining = limit - len(urls)
        for result in search_client.search(query, max_results=remaining, days=freshness_days):
            if result.url in seen:
                continue
            seen.add(result.url)
            urls.append(result.url)
            if len(urls) >= limit:
                break
    return urls


def _build_query(
    role: str,
    preferred_cities: list[str],
    mode_filter: list[str],
    min_salary: int | None,
) -> str:
    parts = [role]
    modes = [*mode_filter, "remote"]
    parts.append(f"({' OR '.join(modes)})")
    if preferred_cities:
        parts.append(f"in {' OR '.join(preferred_cities)}")
    if min_salary:
        parts.append(f"salary at least ${min_salary}")
    parts.append(JOB_BOARD_HINTS)
    return " ".join(parts)


def _to_job_opportunity(listing: JobListingExtraction, url: str) -> JobOpportunity:
    return JobOpportunity(
        company=listing.company,
        title=listing.title,
        location=listing.location,
        mode=_parse_mode(listing.mode),
        website=urlparse(url).netloc,
        url=url,
        published_date=_parse_date(listing.published_date),
        description_summary=listing.description_summary,
        minimum_requirements=listing.minimum_requirements,
        salary=listing.salary,
    )


def _parse_mode(value: str) -> Mode:
    normalized = value.strip().lower()
    for alias, mode in _MODE_ALIASES:
        if alias in normalized:
            return mode
    # Genuinely unrecognized: default to the less specific claim. Falsely
    # labeling a job "remote" is worse than falsely labeling it "on_site",
    # since users may filter/trust the remote label directly.
    return Mode.on_site


def _parse_date(value: str | None) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        return None
