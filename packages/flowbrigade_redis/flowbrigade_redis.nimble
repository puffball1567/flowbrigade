version       = "0.1.0"
author        = "flowbrigade contributors"
description   = "Redis storage adapter for FlowBrigade rate limiting."
license       = "Apache-2.0"
srcDir        = "src"
installExt    = @["nim"]
skipDirs      = @["tests"]

requires "nim >= 2.2.0"
requires "flowbrigade >= 0.1.0"

task test, "Run the test suite":
  exec "nim r --nimcache:/tmp/flowbrigade-redis-nimcache -p:src -p:../../src tests/test_flowbrigade_redis.nim"

task integration, "Run Redis integration tests when redis-cli and Redis are available":
  exec "nim r --nimcache:/tmp/flowbrigade-redis-nimcache -p:src -p:../../src tests/test_flowbrigade_redis_integration.nim"
