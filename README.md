# Jobby

An agentic job-search tool: upload your resume, it suggests target roles,
then searches the web for matching openings.

Single-user, no login, local-first. See `plan.md` for the original brief
and the conversation that grilled it into the design below.

## Stack

- **FastAPI** + Jinja2/HTMX for the web app, **Pico.css** for styling
- **SQLite** via **SQLModel**
- **OpenAI** (`gpt-4o-mini`) for extraction, **Tavily** for web search

## Setup

Dependencies are managed with [uv](https://docs.astral.sh/uv/).

```bash
uv sync   # creates .venv and installs everything from uv.lock
cp .env.example .env   # then fill in OPENAI_API_KEY and TAVILY_API_KEY
```

## Run

```bash
uv run uvicorn app.main:app --reload
```

Then visit <http://localhost:8000/profile> to get started: save a resume,
review the generated target roles and preferences, then head to
**Job Opportunities** to trigger a search.

## Test / typecheck

```bash
uv run pytest
uv run mypy app --ignore-missing-imports
```

## Design notes

- **Profilize** (resume → target roles) runs automatically whenever the
  resume is saved, overwriting `target_roles` each time.
- **Searcher** runs only when you click "Search for jobs" on the Job
  Opportunities page; it never re-runs Profilize.
- Duplicate jobs (same company + title + location) are skipped on insert —
  an existing row's state/score is never overwritten by a later search.
- **Evaluator** (scoring) is intentionally unbuilt — `score` exists in the
  schema as a nullable field, shown as "not yet scored".
- Job Opportunities shows the live backlog (`new`/`saved` jobs only);
  History is the full paginated archive.
