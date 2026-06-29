import std/times

import pkg/flowbrigade
import pkg/flowbrigade/internal/time_source

let time = initManualTimeSource()
let requestDeadline = initDeadline(after = 3.sec, timeSource = time)

let lookupDeadline = requestDeadline.childDeadline(1.sec)
doAssert lookupDeadline.remaining() == 1.sec

time.advance(800.ms)

let downstreamBudget = requestDeadline.clamp(5.sec)
doAssert downstreamBudget == 2200.ms

let timeout = requestDeadline.toTimeout()
doAssert timeout.remaining() == 2200.ms

time.advance(2200.ms)
doAssert requestDeadline.expired()
doAssert timeout.expired()
