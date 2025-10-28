# frozen_string_literal: true

port ENV.fetch("PORT", "8080")
environment ENV.fetch("RACK_ENV", "production")

# Keep it single-process by default; set WEB_CONCURRENCY for workers.
workers Integer(ENV.fetch("WEB_CONCURRENCY", "0"))
threads_count = Integer(ENV.fetch("RACK_MAX_THREADS", "5"))
threads threads_count, threads_count

preload_app!

# Minimal logging
stdout_redirect nil, nil, true

# Health endpoint (handled by Rack app)