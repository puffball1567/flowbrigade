version       = "0.1.0"
author        = "flowbrigade contributors"
description   = "Memcached storage adapter for FlowBrigade rate limiting."
license       = "Apache-2.0"
srcDir        = "src"
installExt    = @["nim"]
skipDirs      = @["tests"]

requires "nim >= 2.2.0"
requires "flowbrigade >= 0.1.0"

task test, "Run the test suite":
  exec "nim r --nimcache:/tmp/flowbrigade-memcached-nimcache -p:src -p:../../src tests/test_flowbrigade_memcached.nim"

task integration, "Run Memcached integration tests when Memcached is available":
  exec "nim r --nimcache:/tmp/flowbrigade-memcached-nimcache -p:src -p:../../src tests/test_flowbrigade_memcached_integration.nim"
