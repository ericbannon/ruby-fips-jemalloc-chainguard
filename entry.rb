#!/usr/bin/env ruby
# Robust Puma launcher that DOES NOT require bundler at runtime.
# - Scans /app/vendor/bundle/ruby/* and picks a real dir (prefers current ABI).
# - Sets GEM_HOME/GEM_PATH and execs Puma via RubyGems.
# - Prints one JSON line to stderr with what it chose.

require "rbconfig"
require "rubygems"
require "json"

APP_DIR      = File.expand_path(__dir__)
VENDOR_ROOT  = File.join(APP_DIR, "vendor", "bundle", "ruby")
RUNTIME_ABI  = RbConfig::CONFIG["ruby_version"] # e.g., "3.4.7"
PORT         = ENV["PORT"] || "8080"

dirs = Dir[File.join(VENDOR_ROOT, "*")].sort
if dirs.empty?
  $stderr.puts({ error: "no_vendor_dirs", vendor_root: VENDOR_ROOT }.to_json)
  exit 111
end

chosen = dirs.find { |d| File.basename(d) == RUNTIME_ABI } || dirs.last

ENV["GEM_HOME"] = chosen
ENV["GEM_PATH"] = dirs.join(File::PATH_SEPARATOR)

# We’re not using Bundler, but keep this set for parity.
ENV["BUNDLE_GEMFILE"] ||= File.join(APP_DIR, "Gemfile")

# Activate RubyGems with our vendored paths
Gem.use_paths(ENV["GEM_HOME"], dirs)

# Resolve Puma’s bin path from the vendored gems
specs = Gem::Specification.find_all_by_name("puma")
if specs.empty?
  $stderr.puts({ error: "puma_not_found", ruby: RUBY_VERSION, abi: RUNTIME_ABI, chosen: chosen, dirs: dirs }.to_json)
  exit 112
end

bin = Gem.bin_path("puma", "puma")

# Emit a single debug line so you can see what was picked
$stderr.puts({ ruby: RUBY_VERSION, abi: RUNTIME_ABI, chosen: chosen, bin: bin, port: PORT }.to_json)

# Exec Puma with your config (binds 0.0.0.0 by default when port set)
exec RbConfig.ruby, bin, "-C", File.join(APP_DIR, "puma.rb"), "-p", PORT