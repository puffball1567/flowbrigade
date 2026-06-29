version       = "0.1.0"
author        = "flowbrigade contributors"
description   = "ready Redis client bridge for FlowBrigade rate limiting."
license       = "Apache-2.0"
srcDir        = "src"
installExt    = @["nim"]
skipDirs      = @["tests"]

requires "nim >= 2.2.0"
requires "flowbrigade >= 0.1.0"
requires "flowbrigade_redis >= 0.1.0"
requires "ready >= 0.1.9"

task test, "Run the test suite":
  exec "nim r --nimcache:/tmp/flowbrigade-ready-nimcache -p:src -p:../flowbrigade_redis/src -p:../../src tests/test_flowbrigade_ready.nim"

task integration, "Run ready Redis integration tests when Redis is available":
  exec "nim r --nimcache:/tmp/flowbrigade-ready-nimcache -p:src -p:../flowbrigade_redis/src -p:../../src tests/test_flowbrigade_ready_integration.nim"
