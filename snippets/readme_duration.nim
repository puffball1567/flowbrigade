import flowbrigade

let timeout = parseDuration("30s")
let interval = parseDuration("1h30m")

doAssert timeout == 30.sec
doAssert formatDuration(interval) == "1h30m"
