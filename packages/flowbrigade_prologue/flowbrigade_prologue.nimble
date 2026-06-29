version       = "0.1.0"
author        = "flowbrigade contributors"
description   = "Prologue middleware bridge for FlowBrigade."
license       = "Apache-2.0"
srcDir        = "src"
installExt    = @["nim"]
skipDirs      = @["e2e", "tests"]

requires "nim >= 2.2.0"
requires "flowbrigade >= 0.1.0"
requires "prologue >= 0.6.8"

task test, "Run the test suite":
  exec "nim r --nimcache:/tmp/flowbrigade-prologue-nimcache -p:src -p:../../src tests/test_flowbrigade_prologue.nim"

task integration, "Run Docker HTTP E2E tests":
  exec "bash e2e/run.sh"
