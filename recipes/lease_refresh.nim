import std/times

import pkg/flowbrigade
import pkg/flowbrigade/internal/time_source

let time = initManualTimeSource()
let locks = initInMemoryLockStore(time).asLockStore()

let lease = locks.acquire("report:daily", 1.min)
doAssert lease.acquired

time.advance(45.sec)
let status = locks.inspect(lease)
doAssert status.held
doAssert status.remaining == 15.sec

let refreshed = locks.refresh(lease, 1.min)
doAssert refreshed.acquired
doAssert refreshed.token == lease.token

time.advance(45.sec)
doAssert locks.inspect(refreshed).held

discard locks.release(refreshed)
doAssert locks.acquire("report:daily", 1.min).acquired
