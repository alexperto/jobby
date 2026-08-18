from __future__ import annotations

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Annotated

from fastapi import Depends, FastAPI, Form, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlmodel import Session

from app.clients import get_llm_client, get_search_client
from app.config import DEFAULT_FRESHNESS_DAYS, DEFAULT_SEARCH_LIMIT, HISTORY_PAGE_SIZE
from app.db import create_db_and_tables, get_session
from app.llm import Extractor
from app.models import JobState
from app.pdf import extract_pdf_text
from app.profilize import profilize
from app.repositories import JobRepository, ProfileRepository
from app.searcher import search_jobs
from app.tavily_client import Searcher

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    create_db_and_tables()
    yield


app = FastAPI(title="Jobby", lifespan=lifespan)
templates = Jinja2Templates(directory="app/templates")


# Dependency indirection so tests can swap in fakes without touching real
# OpenAI/Tavily credentials.
def llm_dependency() -> Extractor:
    return get_llm_client()


def search_dependency() -> Searcher:
    return get_search_client()


SessionDep = Annotated[Session, Depends(get_session)]
LLMDep = Annotated[Extractor, Depends(llm_dependency)]
SearchDep = Annotated[Searcher, Depends(search_dependency)]


@app.get("/")
def root() -> RedirectResponse:
    return RedirectResponse("/opportunities")


@app.get("/profile", response_class=HTMLResponse)
def profile_page(request: Request, session: SessionDep) -> HTMLResponse:
    profile = ProfileRepository(session).get()
    return templates.TemplateResponse(
        request, "profile.html", {"profile": profile}
    )


@app.post("/profile/resume")
async def save_resume(
    session: SessionDep,
    llm: LLMDep,
    resume_file: UploadFile | None = None,
    resume_text: Annotated[str, Form()] = "",
) -> RedirectResponse:
    if resume_file is not None and resume_file.filename:
        text = extract_pdf_text(await resume_file.read())
    else:
        text = resume_text

    extraction = profilize(text, llm)
    ProfileRepository(session).save_resume(
        resume_text=text,
        characteristics=extraction.characteristics.model_dump(),
        target_roles=extraction.target_roles,
    )
    return RedirectResponse("/profile", status_code=303)


@app.post("/profile/target-roles")
def save_target_roles(
    session: SessionDep, target_roles: Annotated[str, Form()]
) -> RedirectResponse:
    repo = ProfileRepository(session)
    profile = repo.get()
    roles = [r.strip() for r in target_roles.split(",") if r.strip()]
    repo.save_resume(
        resume_text=profile.resume_text if profile else "",
        characteristics=profile.characteristics if profile else {},
        target_roles=roles,
    )
    return RedirectResponse("/profile", status_code=303)


@app.post("/profile/preferences")
def save_preferences(
    session: SessionDep,
    min_salary: Annotated[int | None, Form()] = None,
    preferred_cities: Annotated[str, Form()] = "",
    preferred_modes: Annotated[list[str], Form()] = [],
) -> RedirectResponse:
    cities = [c.strip() for c in preferred_cities.split(",") if c.strip()]
    ProfileRepository(session).save_preferences(
        min_salary=min_salary,
        preferred_cities=cities,
        preferred_modes=preferred_modes,
    )
    return RedirectResponse("/profile", status_code=303)


@app.get("/opportunities", response_class=HTMLResponse)
def opportunities_page(request: Request, session: SessionDep) -> HTMLResponse:
    profile = ProfileRepository(session).get()
    target_roles = profile.target_roles if profile else []
    jobs = JobRepository(session).list_backlog() if target_roles else []
    return templates.TemplateResponse(
        request,
        "opportunities.html",
        {
            "target_roles": target_roles,
            "jobs": jobs,
            "default_limit": DEFAULT_SEARCH_LIMIT,
            "default_freshness_days": DEFAULT_FRESHNESS_DAYS,
            "default_modes": profile.preferred_modes if profile else [],
        },
    )


@app.post("/opportunities/search", response_class=HTMLResponse)
def trigger_search(
    request: Request,
    session: SessionDep,
    llm: LLMDep,
    search_client: SearchDep,
    limit: Annotated[int, Form()] = DEFAULT_SEARCH_LIMIT,
    freshness_days: Annotated[int, Form()] = DEFAULT_FRESHNESS_DAYS,
    mode_filter: Annotated[list[str], Form()] = [],
) -> HTMLResponse:
    profile_repo = ProfileRepository(session)
    profile = profile_repo.get()
    job_repo = JobRepository(session)

    if profile and profile.target_roles:
        found = search_jobs(
            target_roles=profile.target_roles,
            preferred_cities=profile.preferred_cities,
            mode_filter=mode_filter,
            limit=limit,
            freshness_days=freshness_days,
            llm=llm,
            search_client=search_client,
            min_salary=profile.min_salary,
        )
        for job in found:
            job_repo.add_if_new(job)

    jobs = job_repo.list_backlog()
    return templates.TemplateResponse(
        request, "_opportunities_list.html", {"jobs": jobs}
    )


@app.post("/opportunities/{job_id}/state", response_class=HTMLResponse)
def update_job_state(
    request: Request, session: SessionDep, job_id: int, new_state: JobState
) -> HTMLResponse:
    repo = JobRepository(session)
    try:
        repo.update_state(job_id, new_state)
    except ValueError:
        raise HTTPException(status_code=404, detail="Job not found")
    jobs = repo.list_backlog(include_all_states=True)
    job = next(j for j in jobs if j.id == job_id)

    if new_state in (JobState.new, JobState.saved):
        return templates.TemplateResponse(request, "_job_card.html", {"job": job})
    return HTMLResponse("")


@app.get("/history", response_class=HTMLResponse)
def history_page(request: Request, session: SessionDep, page: int = 1) -> HTMLResponse:
    jobs, total = JobRepository(session).list_history(
        page=page, page_size=HISTORY_PAGE_SIZE
    )
    total_pages = max(1, -(-total // HISTORY_PAGE_SIZE))
    return templates.TemplateResponse(
        request,
        "history.html",
        {"jobs": jobs, "page": page, "total_pages": total_pages},
    )
