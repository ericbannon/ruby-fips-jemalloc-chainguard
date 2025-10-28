# frozen_string_literal: true

require "json"

module JemallocCheck
  module_function

  def loaded?
    # Check mapped libraries for "jemalloc"
    maps = File.read("/proc/self/maps")
    maps.include?("jemalloc")
  rescue => e
    warn "Failed to read /proc/self/maps: #{e.class}: #{e.message}"
    false
  end

  def info
    {
      pid: Process.pid,
      ruby_version: RUBY_VERSION,
      ruby_platform: RUBY_PLATFORM,
      puma: gem_version("puma"),
      rack: gem_version("rack"),
      allocator: loaded? ? "jemalloc (via LD_PRELOAD)" : "system",
      ld_preload: ENV["LD_PRELOAD"],
      malloc_conf: ENV["MALLOC_CONF"],
      time: Time.now.utc.iso8601
    }
  end

  def info_json
    JSON.generate(info)
  end

  def gem_version(name)
    spec = Gem.loaded_specs[name]
    spec && spec.version.to_s
  end
end