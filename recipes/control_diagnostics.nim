import std/sequtils

import flowbrigade

let signals = @[
  failureSignal(),
  timeoutSignal(),
  failureSignal(),
  successSignal(30.ms),
  successSignal(25.ms),
  successSignal(20.ms),
  successSignal(22.ms),
  successSignal(24.ms),
  successSignal(26.ms),
  successSignal(28.ms)
]

let report = analyzeControlSignals(signals)

doAssert report.mode == "advice-only"
doAssert report.hints.anyIt(it.kind == chkInspectDownstream)
doAssert report.hints.anyIt(it.kind == chkReduceRetryAttempts)

# FlowBrigade does not apply these hints automatically. Applications may show
# them to operators, log them, or explicitly map them to their own control
# changes.
