# syntax=docker/dockerfile:1
# check=error=true

# Multi-stage build with two targets:
#   * development — used by docker-compose for the local stack (all gem groups,
#     code bind-mounted at runtime).
#   * production  — slim, non-root image built for deploy (Render). Selected with
#     `docker build --target production`.
#
# Make sure RUBY_VERSION matches the Ruby version in .ruby-version.
ARG RUBY_VERSION=3.3.7

###############################################################################
# Base: shared runtime layer
###############################################################################
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Packages needed at runtime by every target.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV BUNDLE_PATH="/usr/local/bundle"

###############################################################################
# Development target: full toolchain, all gem groups, code bind-mounted at runtime
###############################################################################
FROM base AS development

ENV RAILS_ENV="development"

# Packages needed to build native gems (pg, etc.).
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install gems first so the layer is cached when only app code changes.
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Bake the code in for standalone runs; docker-compose bind-mounts over it.
COPY . .

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]

###############################################################################
# Build: throw-away stage that compiles gems for the production image
###############################################################################
FROM base AS build

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_WITHOUT="development"

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/

###############################################################################
# Production target: slim, non-root runtime image
###############################################################################
FROM base AS production

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

RUN ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so

# Run and own only the runtime files as a non-root user for security.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

USER 1000:1000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server via Thruster by default; can be overridden at runtime.
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
