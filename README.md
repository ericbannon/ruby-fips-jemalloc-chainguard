# ruby-fips-jemalloc-chainguard

This repository demonstrates how to build and run a **Ruby (FIPS-enabled)** application on **Chainguard’s minimal container images** using **jemalloc** as the allocator.

It includes:
- A multi-stage Docker build (builder → FIPS runtime)
- Vendored gems (`bundle install --deployment`)
- jemalloc preloaded for memory optimization
- A minimal Rack/Puma service exposing allocator information
- No Bundler dependency in runtime (uses RubyGems only)

```bash
docker build -t jemalloc-ruby-ex .
```

## Run the workload

```
docker run --rm -p 8080:8080 jemalloc-ruby-ex
{"ruby":"3.4.7","abi":"3.4.0","chosen":"/app/vendor/bundle/ruby/3.4.0","bin":"/app/vendor/bundle/ruby/3.4.0/gems/puma-6.4.2/bin/puma","port":"8080"}
Puma starting in single mode...
* Puma version: 6.4.2 (ruby 3.4.7-p58) ("The Eagle of Durango")
*  Min threads: 5
*  Max threads: 5
*  Environment: production
*          PID: 1
* Listening on http://0.0.0.0:8080
Use Ctrl-C to stop
```

## jemalloc test

```
curl -v http://localhost:8080
* Host localhost:8080 was resolved.
* IPv6: ::1
* IPv4: 127.0.0.1
*   Trying [::1]:8080...
* Connected to localhost (::1) port 8080
> GET / HTTP/1.1
> Host: localhost:8080
> User-Agent: curl/8.7.1
> Accept: */*
>
* Request completely sent off
< HTTP/1.1 200 OK
< Content-Type: application/json
< Content-Length: 304
<
* Connection #0 to host localhost left intact
{"pid":1,"ruby_version":"3.4.7","ruby_platform":"aarch64-linux-gnu","puma":"6.4.2","rack":"3.0.8","allocator":"jemalloc (via LD_PRELOAD)","ld_preload":"/usr/lib/libjemalloc.so.2","malloc_conf":"background_thread:true,metadata_thp:auto,dirty_decay_ms:500,muzzy_decay_ms:500","time":"2025-10-28T16:05:49Z"}%
```

## RSS Growth & Retained Memory Comparison Test

**60 second glibc baseline**
```
# Baseline – glibc allocator
docker run --rm --entrypoint ruby \
  -e LD_PRELOAD= \
  -e BENCH_THREADS=4 \
  -e BENCH_ITERS=3000000 \
  -e BENCH_ROUNDS=20 \
  jemalloc-ruby-ex /app/bench_alloc.rb > glibc.json
```

**60 second jemalloc baseline**

```
# jemalloc allocator
docker run --rm --entrypoint ruby \
  -e LD_PRELOAD=/usr/lib/libjemalloc.so.2 \
  -e MALLOC_CONF='background_thread:true,dirty_decay_ms:100,muzzy_decay_ms:100,retain:false,narenas:2' \
  -e BENCH_THREADS=4 \
  -e BENCH_ITERS=3000000 \
  -e BENCH_ROUNDS=20 \
  -e BENCH_SLEEP_AFTER=2 \
  jemalloc-ruby-ex /app/bench_alloc.rb > jema.json
```

**compare results**

```
jq -s '[{alloc:"glibc",rss:.[0].rss_delta_mb,time:.[0].time_s},
        {alloc:"jemalloc",rss:.[1].rss_delta_mb,time:.[1].time_s}]' glibc.json jema.json
```

**Sample output**

```
[
  {
    "alloc": "glibc",
    "rss": 710.27,
    "time": 70.922
  },
  {
    "alloc": "jemalloc",
    "rss": 134.5,
    "time": 76.258
  }
]
```
