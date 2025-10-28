# frozen_string_literal: true
# Simple alloc/free churn benchmark to compare jemalloc vs system allocator.
# - Measures wall time and RSS before/after heavy allocations.
# - Multithreaded to trigger fragmentation/metadata behavior.
# - When MALLOC_CONF=stats_print:true is set, jemalloc prints allocator stats on exit.

require "json"

def rss_kb
  # Read VmRSS from /proc/self/status in kB
  File.read("/proc/self/status")
      .lines
      .find { |l| l.start_with?("VmRSS:") }
      .split(/\s+/)[1].to_i
rescue
  -1
end

def statm_pages
  # /proc/self/statm: size resident share text lib data dt
  # returns resident pages
  File.read("/proc/self/statm").split(/\s+/)[1].to_i
rescue
  -1
end

def pagesize
  @pagesize ||= (`getconf PAGESIZE` rescue "4096").to_i
rescue
  4096
end

def rss_bytes
  if (kb = rss_kb) >= 0
    kb * 1024
  else
    # fallback via statm
    statm_pages * pagesize
  end
end

def alloc_churn(iterations:, str_size:, keep_ratio:)
  # churn workload: allocate many strings, keep some to simulate live set, then free
  keep = []
  iterations.times do |i|
    s = "x" * str_size
    keep << s if (i % keep_ratio).zero?
  end
  # Drop references; GC later
  keep.clear
end

def worker(iters, str_size, keep_ratio, rounds)
  rounds.times do
    alloc_churn(iterations: iters, str_size: str_size, keep_ratio: keep_ratio)
    GC.start(full_mark: true, immediate_sweep: true)
  end
end

def run_benchmark(threads:, iters:, str_size:, keep_ratio:, rounds:)
  # Warmup
  GC.start
  2.times { worker(iters / 4, str_size, keep_ratio, 1) }

  before_rss = rss_bytes
  t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  ts = []
  threads.times do
    ts << Thread.new { worker(iters, str_size, keep_ratio, rounds) }
  end
  ts.each(&:join)

  GC.start(full_mark: true, immediate_sweep: true)
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
    rss_before_mb: (before_rss / 1024.0 / 1024.0).round(2),
    rss_after_mb: (after_rss / 1024.0 / 1024.0).round(2),
    rss_delta_mb: ((after_rss - before_rss) / 1024.0 / 1024.0).round(2),
    ld_preload: ENV["LD_PRELOAD"],
    malloc_conf: ENV["MALLOC_CONF"]
  }
end

# Tunables via env
threads    = Integer(ENV.fetch("BENCH_THREADS", "4"))
iters      = Integer(ENV.fetch("BENCH_ITERS", "200_000"))
str_size   = Integer(ENV.fetch("BENCH_STR", "1024"))       # 1 KiB strings
keep_ratio = Integer(ENV.fetch("BENCH_KEEP", "17"))        # keep ~1/17 allocations
rounds     = Integer(ENV.fetch("BENCH_ROUNDS", "3"))

result = run_benchmark(
  threads: threads,
  iters: iters,
  str_size: str_size,
  keep_ratio: keep_ratio,
  rounds: rounds
)

puts JSON.pretty_generate(result)
# If jemalloc is configured with MALLOC_CONF=stats_print:true,
# allocator stats will be printed to stderr on process exit.
