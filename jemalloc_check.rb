# bench_alloc.rb
# -----------------------------------------------------------------------------
# Purpose:
#   Stress the Ruby allocator with concurrent allocation/free churn and report:
#     - wall-clock time
#     - RSS before/after (MB) and delta (MB)
#     - runtime / platform / allocator preload info
#   Designed to demonstrate jemalloc vs system allocator inside containers.
#
# How to run:
#   # Baseline (system allocator)
#   ruby bench_alloc.rb
#
#   # With jemalloc (typical tuning + allow decay to run before measuring)
#   LD_PRELOAD=/usr/lib/libjemalloc.so.2 \
#   MALLOC_CONF='background_thread:true,dirty_decay_ms:100,muzzy_decay_ms:100,retain:false,narenas:2' \
#   BENCH_SLEEP_AFTER=2 \
#   ruby bench_alloc.rb
#
# Tunables (env):
#   BENCH_THREADS       -> number of Ruby threads (default: 4)
#   BENCH_ITERS         -> allocations per thread per round (default: 200000)
#   BENCH_STR           -> bytes per string allocation (default: 1024)
#   BENCH_KEEP          -> keep every Nth allocation (default: 17)
#   BENCH_ROUNDS        -> repeat churn rounds per thread (default: 3)
#   BENCH_SLEEP_AFTER   -> seconds to sleep after final GC before measuring RSS
#                          (helps jemalloc background decay) (default: 0)
#
# Notes:
#   - This test simulates long-lived processes with bursty churn.
#   - jemalloc tends to reduce RSS_delta for such patterns given time to decay.
# -----------------------------------------------------------------------------

require "json"
require "rbconfig"

# ---------- Helpers ----------

def parse_int_env(key, default)
  raw = ENV[key]
  return default if raw.nil? || raw.empty?
  Integer(raw.gsub("_", ""))
rescue ArgumentError
  default
end

def jemalloc_mapped?
  File.read("/proc/self/maps").include?("jemalloc")
rescue
  false
end

def rss_kb
  # VmRSS from /proc/self/status (kB)
  line = File.foreach("/proc/self/status").find { |l| l.start_with?("VmRSS:") }
  return -1 unless line
  parts = line.split(/\s+/)
  parts[1].to_i # kB
rescue
  -1
end

def statm_resident_pages
  # /proc/self/statm: size resident share text lib data dt
  # second column = resident pages
  contents = File.read("/proc/self/statm")
  contents.split(/\s+/)[1].to_i
rescue
  -1
end

def system_pagesize
  out = `getconf PAGESIZE 2>/dev/null`.strip
  Integer(out)
rescue
  4096
end

def rss_bytes
  kb = rss_kb
  return kb * 1024 if kb >= 0

  pages = statm_resident_pages
  pages > 0 ? pages * system_pagesize : -1
end

def mb(bytes)
  (bytes / 1024.0 / 1024.0).round(2)
end

# ---------- Workload ----------

def alloc_churn(iterations:, str_size:, keep_ratio:)
  keep = []
  iterations.times do |i|
    s = "x" * str_size
    keep << s if keep_ratio > 0 && (i % keep_ratio).zero?
  end
  # Drop references; GC will reclaim
  keep.clear
end

def worker(iters, str_size, keep_ratio, rounds)
  rounds.times do
    alloc_churn(iterations: iters, str_size: str_size, keep_ratio: keep_ratio)
    GC.start(full_mark: true, immediate_sweep: true)
  end
end

def run_benchmark(threads:, iters:, str_size:, keep_ratio:, rounds:, sleep_after:)
  # Warmup: populate allocator/VM state a bit
  GC.start
  2.times { worker([iters / 8, 1].max, str_size, keep_ratio, 1) }

  before_rss = rss_bytes
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  ts = Array.new(threads) do
    Thread.new { worker(iters, str_size, keep_ratio, rounds) }
  end
  ts.each(&:join)

  # Force GC then optionally give allocator background thread time to purge
  GC.start(full_mark: true, immediate_sweep: true)
  sleep(sleep_after) if sleep_after.positive?

  t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  after_rss = rss_bytes

  {
    ruby_version: RUBY_VERSION,
    ruby_platform: RUBY_PLATFORM,
    threads: threads,
    iters_per_thread: iters,
    str_size: str_size,
    keep_ratio: keep_ratio,
    rounds: rounds,
    time_s: (t1 - t0).round(3),
    rss_before_mb: mb(before_rss),
    rss_after_mb: mb(after_rss),
    rss_delta_mb: mb(after_rss - before_rss),
    ld_preload: ENV["LD_PRELOAD"].to_s,
    malloc_conf: ENV["MALLOC_CONF"].to_s,
    jemalloc_mapped: jemalloc_mapped?
  }
end

# ---------- Config from env ----------

threads     = parse_int_env("BENCH_THREADS", 4)
iters       = parse_int_env("BENCH_ITERS", 200_000)
str_size    = parse_int_env("BENCH_STR", 1024)
keep_ratio  = parse_int_env("BENCH_KEEP", 17)
rounds      = parse_int_env("BENCH_ROUNDS", 3)
sleep_after = parse_int_env("BENCH_SLEEP_AFTER", 0)

# ---------- Execute ----------

result = run_benchmark(
  threads: threads,
  iters: iters,
  str_size: str_size,
  keep_ratio: keep_ratio,
  rounds: rounds,
  sleep_after: sleep_after
)

puts JSON.pretty_generate(result)

# Tip: enable jemalloc stats (stderr) by adding to MALLOC_CONF:
#   stats_print:true