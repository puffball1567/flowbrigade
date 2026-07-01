import std/[times, unittest]

import flowbrigade
import flowbrigade/internal/time_source

suite "retry allowance":
  test "allows retries according to original work ratio":
    let time = initManualTimeSource()
    var allowance = initRetryAllowance(
      retryRatio = 0.5,
      per = initDuration(minutes = 1),
      timeSource = time
    )

    let original = allowance.recordOriginal("s3", amount = 4)
    check original.allowed
    check original.limit == 2
    check original.originals == 4
    check original.retries == 0
    check original.remaining == 2

    check allowance.allowRetry("s3")
    check allowance.allowRetry("s3")
    let denied = allowance.recordRetry("s3")
    check not denied.allowed
    check denied.limit == 2
    check denied.retries == 2
    check denied.remaining == 0
    check denied.retryAfter == initDuration(minutes = 1)

  test "minimum retries allow low traffic clients to retry":
    let time = initManualTimeSource()
    var allowance = initRetryAllowance(
      retryRatio = 0.0,
      per = initDuration(minutes = 1),
      minimumRetries = 2,
      timeSource = time
    )

    check allowance.allowRetry("registry")
    check allowance.allowRetry("registry")
    check not allowance.allowRetry("registry")

  test "inspectRetry does not consume or retain new keys":
    let time = initManualTimeSource()
    var allowance = initRetryAllowance(
      retryRatio = 0.5,
      per = initDuration(minutes = 1),
      minimumRetries = 1,
      timeSource = time
    )

    let inspected = allowance.inspectRetry("api")
    check inspected.allowed
    check inspected.remaining == 0
    check allowance.activeKeys() == 0

    check allowance.allowRetry("api")
    check not allowance.allowRetry("api")

  test "recordRetry supports custom retry cost":
    let time = initManualTimeSource()
    var allowance = initRetryAllowance(
      retryRatio = 0.5,
      per = initDuration(minutes = 1),
      timeSource = time
    )

    discard allowance.recordOriginal("api", amount = 10)
    let used = allowance.recordRetry("api", cost = 3)
    check used.allowed
    check used.retries == 3
    check used.remaining == 2

    let denied = allowance.recordRetry("api", cost = 3)
    check not denied.allowed
    check denied.retries == 3
    check denied.remaining == 2

  test "resets retry allowance after the configured period":
    let time = initManualTimeSource()
    var allowance = initRetryAllowance(
      retryRatio = 1.0,
      per = initDuration(seconds = 10),
      timeSource = time
    )

    discard allowance.recordOriginal("api")
    check allowance.allowRetry("api")
    check not allowance.allowRetry("api")

    time.advance(initDuration(seconds = 9))
    check not allowance.allowRetry("api")

    time.advance(initDuration(seconds = 1))
    check not allowance.allowRetry("api")
    discard allowance.recordOriginal("api")
    check allowance.allowRetry("api")

  test "keeps retry allowance isolated per key":
    let time = initManualTimeSource()
    var allowance = initRetryAllowance(
      retryRatio = 1.0,
      per = initDuration(minutes = 1),
      timeSource = time
    )

    discard allowance.recordOriginal("s3")
    discard allowance.recordOriginal("gcs")
    check allowance.allowRetry("s3")
    check not allowance.allowRetry("s3")
    check allowance.allowRetry("gcs")

  test "trims keys and rejects unsafe keys":
    let time = initManualTimeSource()
    var allowance = initRetryAllowance(
      retryRatio = 1.0,
      per = initDuration(minutes = 1),
      timeSource = time
    )

    discard allowance.recordOriginal(" api ")
    check allowance.allowRetry("api")

    expect RetryAllowanceError:
      discard allowance.recordOriginal(" ")
    expect RetryAllowanceError:
      discard allowance.inspectRetry("")
    expect RetryAllowanceError:
      discard allowance.recordRetry("api" & chr(10))

  test "rejects invalid amounts":
    let time = initManualTimeSource()
    var allowance = initRetryAllowance(
      retryRatio = 1.0,
      per = initDuration(minutes = 1),
      timeSource = time
    )

    expect RetryAllowanceError:
      discard allowance.recordOriginal("api", amount = 0)
    expect RetryAllowanceError:
      discard allowance.recordOriginal("api", amount = -1)
    expect RetryAllowanceError:
      discard allowance.recordRetry("api", cost = 0)
    expect RetryAllowanceError:
      discard allowance.recordRetry("api", cost = -1)

  test "rejects invalid retry allowance configuration":
    let time = initManualTimeSource()

    expect RetryAllowanceConfigError:
      discard initRetryAllowance(-0.1, initDuration(minutes = 1), timeSource = time)
    expect RetryAllowanceConfigError:
      discard initRetryAllowance(1.1, initDuration(minutes = 1), timeSource = time)
    expect RetryAllowanceConfigError:
      discard initRetryAllowance(0.2, initDuration(), timeSource = time)
    expect RetryAllowanceConfigError:
      discard initRetryAllowance(0.2, initDuration(minutes = 1), minimumRetries = -1, timeSource = time)
    expect RetryAllowanceConfigError:
      discard initRetryAllowance(0.2, initDuration(minutes = 1), timeSource = time, maxKeys = 0)
    expect RetryAllowanceConfigError:
      discard initRetryAllowance(0.2, initDuration(minutes = 1), timeSource = nil)

  test "enforces key capacity and prunes expired keys":
    let time = initManualTimeSource()
    var allowance = initRetryAllowance(
      retryRatio = 1.0,
      per = initDuration(seconds = 5),
      timeSource = time,
      maxKeys = 1
    )

    discard allowance.recordOriginal("api-a")
    expect RetryAllowanceError:
      discard allowance.recordOriginal("api-b")

    time.advance(initDuration(seconds = 5))
    discard allowance.recordOriginal("api-b")
    check allowance.activeKeys() == 1

  test "clear reset and resetAll remove retained state":
    let time = initManualTimeSource()
    var allowance = initRetryAllowance(
      retryRatio = 1.0,
      per = initDuration(minutes = 1),
      timeSource = time
    )

    discard allowance.recordOriginal("api-a")
    discard allowance.recordOriginal("api-b")
    check allowance.activeKeys() == 2
    check allowance.clear("api-a")
    check not allowance.clear("api-a")
    check allowance.reset("api-b")
    check allowance.activeKeys() == 0

    discard allowance.recordOriginal("api-c")
    discard allowance.recordOriginal("api-d")
    check allowance.resetAll() == 2
    check allowance.activeKeys() == 0

  test "exposes retry allowance configuration":
    let time = initManualTimeSource()
    let allowance = initRetryAllowance(
      retryRatio = 0.25,
      per = initDuration(minutes = 1),
      minimumRetries = 3,
      timeSource = time,
      maxKeys = 7
    )

    check allowance.configuredRetryRatio() == 0.25
    check allowance.configuredMinimumRetries() == 3
    check allowance.configuredPeriod() == initDuration(minutes = 1)
    check allowance.keyCapacity() == 7

  test "default constructor uses a real time source":
    var allowance = initRetryAllowance(
      retryRatio = 1.0,
      per = initDuration(seconds = 1)
    )

    discard allowance.recordOriginal("api")
    check allowance.allowRetry("api")
    check not allowance.allowRetry("api")
