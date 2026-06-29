import std/times

import flowbrigade

let retryDelay = parseDuration(" 250 ms ")
let requestTimeout = parseDuration("+1.5s")
let cacheTtl = 5.min

doAssert retryDelay == 250.ms
doAssert requestTimeout == initDuration(milliseconds = 1500)
doAssert formatDuration(cacheTtl) == "5m"

echo "retryDelay=", formatDuration(retryDelay)
echo "requestTimeout=", formatDuration(requestTimeout)
echo "cacheTtl=", formatDuration(cacheTtl)
