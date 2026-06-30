version       = "0.2.0"
author        = "flowbrigade contributors"
description   = "Flow control utilities for Nim."
license       = "Apache-2.0"
srcDir        = "src"
installExt    = @["nim", "h"]
skipDirs      = @[
  ".github",
  "benchmarks",
  "docs",
  "examples",
  "packages",
  "recipes",
  "snippets",
  "tests"
]

requires "nim >= 2.2.0"

task test, "Run the test suite":
  exec "nim r --nimcache:/tmp/flowbrigade-nimcache -p:src tests/all.nim"

task benchmark, "Run local benchmark smoke tests":
  exec "nim r --nimcache:/tmp/flowbrigade-nimcache -d:release -p:src benchmarks/core_bench.nim"
  exec "nim r --nimcache:/tmp/flowbrigade-nimcache -d:release -p:src -p:packages/flowbrigade_redis/src benchmarks/redis_adapter_bench.nim"

task benchmarkRedis, "Run optional Redis benchmark against a real Redis server":
  exec "nim r --nimcache:/tmp/flowbrigade-nimcache -d:release -p:src -p:packages/flowbrigade_redis/src benchmarks/redis_real_bench.nim"

task cabi, "Build the experimental C ABI shared library":
  exec "nim c --mm:arc --app:lib --nimcache:/tmp/flowbrigade-cabi-nimcache -p:src --out:/tmp/libflowbrigade.so src/flowbrigade_c.nim"

task snippets, "Check README snippets and dependency-free recipes":
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src snippets/readme_quick_start.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src snippets/readme_duration.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src snippets/readme_retry.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src snippets/readme_rate_limit.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src snippets/readme_stored_fixed_window.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/api_client_retry.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/login_rate_limit.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/worker_backpressure.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/batch_worker_runtime.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/failure_modes.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/observability_hooks.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/named_limiters.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/http_api_abuse_protection.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/password_reset_throttle.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/multi_tenant_quota.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/policy_builder.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/control_diagnostics.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/observability_export.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/fallback_api_client.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/async_fallback_api_client.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/lease_refresh.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/deadline_composition.nim"
  exec "nim check --nimcache:/tmp/flowbrigade-nimcache -p:src recipes/service_guard_pipeline.nim"
