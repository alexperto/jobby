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

## Docker

```bash
docker build -t jobby .

docker run -d \
  -p 3000:3000 \
  -e RAILS_MASTER_KEY=$(cat config/master.key) \
  -v jobby_storage:/rails/storage \
  --name jobby \
  jobby
```

- `RAILS_MASTER_KEY` decrypts `config/credentials.yml.enc` (which holds
  `openai_api_key`/`tavily_api_key`) — the key itself is never baked into
  the image. Set it from your local `config/master.key`, or however your
  deployment target injects secrets.
- The `-v jobby_storage:/rails/storage` volume is where the SQLite
  database lives — without it, data is lost when the container is
  recreated.
- The entrypoint runs `db:prepare` on every boot (creates the DB from
  `db/schema.rb` on first run, applies any new migrations after).
- `/up` is Rails' built-in health check route, wired into the image's
  `HEALTHCHECK`.

### Docker for local development

The image above is production-only (`RAILS_ENV=production` disables code
reloading, dev/test gems aren't installed, and assets are precompiled) —
bind-mounting your working directory over it won't give you a live-edit
loop. Use the `dev` build target instead, which has the full Gemfile and
runs in development mode:

```bash
docker build --target dev -t jobby-dev .

docker run -it --rm \
  -p 3000:3000 \
  -v "$(pwd)":/rails \
  jobby-dev
```

- `-v "$(pwd)":/rails` bind-mounts the whole project in — Ruby file/view
  changes are picked up on the next request, no rebuild or restart needed.
- No `RAILS_MASTER_KEY` needed here: since the mount includes
  `config/master.key` (gitignored, but present on your local disk), Rails
  reads it straight off disk like it does outside Docker.
- Rebuild (`docker build --target dev ...`) only when the Gemfile changes
  — everything else is picked up live through the mount.

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
