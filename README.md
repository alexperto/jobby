# Jobby

An agentic job-search tool: upload your resume, it suggests target roles,
then searches the web for matching openings.

Single-user, no login, local-first. See `plan.md` for the original brief
and the conversation that grilled it into the design below. (An earlier
Python/FastAPI implementation of this same design lives earlier in this
branch's git history — this is a from-scratch Ruby on Rails port.)

## Stack

- **Rails 8** + ERB/Hotwire (Turbo Frames/Streams) for the web app,
  **Pico.css** for styling
- **SQLite** via **ActiveRecord**
- **OpenAI** (`gpt-4o-mini`) for extraction, **Tavily** for web search —
  both called directly via **Faraday** (no SDK gems, per `plan.md`'s
  constraint)
- **Minitest** for tests

## Setup

```bash
bundle install
bin/rails db:prepare
bin/rails credentials:edit   # set openai_api_key and tavily_api_key
```

## Run

```bash
bin/dev   # or: bin/rails server
```

Then visit <http://localhost:3000/profile> to get started: save a resume,
review the generated target roles and preferences, then head to
**Job Opportunities** to trigger a search.

## Test / lint / security

```bash
bin/rails test
bin/rubocop
bin/brakeman
bin/bundler-audit
```

## Design notes

- **Profilizer** (resume → target roles) runs automatically whenever the
  resume is saved, overwriting `target_roles` each time.
- **Searcher** runs only when you click "Search for jobs" on the Job
  Opportunities page; it never re-runs Profilizer.
- Duplicate jobs (same company + title + location, normalized) are
  skipped on insert via a DB-level unique index on `dedup_key` — an
  existing row's state/score is never overwritten by a later search.
- **Evaluator** (scoring) is intentionally unbuilt — `score` exists in the
  schema as a nullable column, shown as "not yet scored".
- Job Opportunities shows the live backlog (`new`/`saved` jobs only, via
  a Turbo Frame); History is the full paginated archive.
- Job-state changes (Applied/Save/Discard/Irrelevant) are Turbo Stream
  requests — the card is replaced in place or removed depending on
  whether the new state is still in the backlog.
- API keys live in Rails' encrypted credentials
  (`config/credentials.yml.enc`), not a `.env` file — this app is never
  deployed to a shared team, so the extra ceremony of `.env` + a gem
  wasn't worth it.
