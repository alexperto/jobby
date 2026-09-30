# syntax=docker/dockerfile:1
# check=error=true

# Matches .ruby-version. Bump both together.
ARG RUBY_VERSION=3.4.10
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages needed both to build and to run the app
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      libsqlite3-0 \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems (sqlite3's native extension in
# particular) and precompile assets
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      libsqlite3-dev \
      pkg-config \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring a real secret key.
# There is no JS/CSS build step (importmap-rails, Pico.css via CDN link
# tag) — this just fingerprints and copies app/assets/* into public/assets.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# Local-development image: full Gemfile (rubocop/brakeman/minitest/
# web-console included), RAILS_ENV=development. Meant to be run with your
# working directory bind-mounted over /rails — see the "Docker for local
# development" section in README.md. Not used for anything pushed/deployed.
FROM build AS dev

ENV RAILS_ENV="development" \
    BUNDLE_WITHOUT="" \
    BUNDLE_DEPLOYMENT="false"

RUN bundle install

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["./bin/rails", "server", "-b", "0.0.0.0"]

# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security.
# storage/ holds the SQLite database — mount a volume there in production
# so data survives container recreation.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p db log storage tmp && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Requires RAILS_MASTER_KEY (or a config/master.key bind-mount) at runtime
# to decrypt config/credentials.yml.enc — openai_api_key and
# tavily_api_key live there, not in this image or in a .env file.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Rails' built-in health check route (config/routes.rb: get "up" => ...)
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD curl -f http://localhost:3000/up || exit 1

EXPOSE 3000
CMD ["./bin/rails", "server"]
