# syntax=docker/dockerfile:1.7

########### Stage 1 – builder (non-FIPS) ###########
FROM cgr.dev/chainguard-private/ruby:latest-dev AS builder
WORKDIR /app
USER root

RUN apk add --no-cache jemalloc build-base linux-headers git

# Standard bundler settings for vendoring
ENV BUNDLE_PATH=/app/vendor/bundle \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3

# Copy manifests first for better cache
COPY Gemfile Gemfile.lock ./

# Add platforms if needed (harmless if already present)
RUN BUNDLE_DEPLOYMENT= BUNDLE_FROZEN=false bundle lock --add-platform ruby aarch64-linux aarch64-linux-gnu || true

# Install gems to vendor dir (allow lockfile touches here only)
RUN --mount=type=cache,target=/usr/local/bundle/cache \
    BUNDLE_DEPLOYMENT= BUNDLE_FROZEN=false \
    bundle install --verbose

# Copy the rest of the app, including your pre-made entry.rb
COPY . .

# Optional: make sure entry.rb is executable (not required when invoking via ruby)
RUN chmod 0755 /app/entry.rb

########### Stage 2 – runtime (FIPS) ###########
FROM cgr.dev/chainguard-private/ruby-fips:latest
WORKDIR /app

# Copy jemalloc and app
COPY --from=builder /usr/lib/libjemalloc.so.2 /usr/lib/libjemalloc.so.2
COPY --from=builder /app /app

# jemalloc preload
ENV LD_PRELOAD=/usr/lib/libjemalloc.so.2
ENV MALLOC_CONF=background_thread:true,metadata_thp:auto,dirty_decay_ms:500,muzzy_decay_ms:500

# Freeze bundler behavior (even though we don't use bundler at runtime)
ENV BUNDLE_DEPLOYMENT=1 \
    BUNDLE_FROZEN=true \
    BUNDLE_GEMFILE=/app/Gemfile \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_PATH=/app/vendor/bundle

# Non-root
USER nonroot
EXPOSE 8080

# Run the robust launcher (Bundler-free)
ENTRYPOINT ["ruby", "/app/entry.rb"]