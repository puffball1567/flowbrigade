import std/[times, unittest]

import flowbrigade/backoff

suite "backoff policies":
  test "fixed backoff always returns the same delay":
    let policy = fixedBackoff(initDuration(milliseconds = 250))

    check policy.delayFor(attempt = 1) == initDuration(milliseconds = 250)
    check policy.delayFor(attempt = 2) == initDuration(milliseconds = 250)
    check policy.delayFor(attempt = 5) == initDuration(milliseconds = 250)

  test "linear backoff grows by a fixed increment":
    let policy = linearBackoff(
      initial = initDuration(milliseconds = 100),
      increment = initDuration(milliseconds = 50),
      maxDelay = initDuration(milliseconds = 250)
    )

    check policy.delayFor(attempt = 1) == initDuration(milliseconds = 100)
    check policy.delayFor(attempt = 2) == initDuration(milliseconds = 150)
    check policy.delayFor(attempt = 3) == initDuration(milliseconds = 200)

  test "linear backoff caps at max delay":
    let policy = linearBackoff(
      initial = initDuration(milliseconds = 100),
      increment = initDuration(milliseconds = 100),
      maxDelay = initDuration(milliseconds = 250)
    )

    check policy.delayFor(attempt = 4) == initDuration(milliseconds = 250)

  test "exponential backoff grows by factor":
    let policy = expBackoff(
      initial = initDuration(milliseconds = 100),
      factor = 2.0,
      maxDelay = initDuration(seconds = 5)
    )

    check policy.delayFor(attempt = 1) == initDuration(milliseconds = 100)
    check policy.delayFor(attempt = 2) == initDuration(milliseconds = 200)
    check policy.delayFor(attempt = 3) == initDuration(milliseconds = 400)

  test "exponential backoff caps at max delay":
    let policy = expBackoff(
      initial = initDuration(seconds = 1),
      factor = 2.0,
      maxDelay = initDuration(seconds = 5)
    )

    check policy.delayFor(attempt = 10) == initDuration(seconds = 5)

  test "rejects attempt zero":
    let policy = fixedBackoff(initDuration(milliseconds = 100))

    expect BackoffError:
      discard policy.delayFor(attempt = 0)

  test "rejects non-positive fixed delay":
    expect BackoffConfigError:
      discard fixedBackoff(initDuration())

  test "rejects negative fixed delay":
    expect BackoffConfigError:
      discard fixedBackoff(initDuration(milliseconds = -1))

  test "rejects linear max delay lower than initial":
    expect BackoffConfigError:
      discard linearBackoff(
        initial = initDuration(seconds = 2),
        increment = initDuration(seconds = 1),
        maxDelay = initDuration(seconds = 1)
      )

  test "rejects non-positive linear increment":
    expect BackoffConfigError:
      discard linearBackoff(
        initial = initDuration(seconds = 1),
        increment = initDuration(),
        maxDelay = initDuration(seconds = 2)
      )

  test "rejects non-positive exponential factor":
    expect BackoffConfigError:
      discard expBackoff(
        initial = initDuration(milliseconds = 100),
        factor = 0.0,
        maxDelay = initDuration(seconds = 1)
      )

  test "rejects exponential factor of one":
    expect BackoffConfigError:
      discard expBackoff(
        initial = initDuration(milliseconds = 100),
        factor = 1.0,
        maxDelay = initDuration(seconds = 1)
      )

  test "rejects exponential max delay lower than initial":
    expect BackoffConfigError:
      discard expBackoff(
        initial = initDuration(seconds = 2),
        factor = 2.0,
        maxDelay = initDuration(seconds = 1)
      )

  test "caps large linear attempts without overflowing":
    let policy = linearBackoff(
      initial = initDuration(milliseconds = 100),
      increment = initDuration(seconds = 1),
      maxDelay = initDuration(seconds = 5)
    )

    check policy.delayFor(attempt = high(int)) == initDuration(seconds = 5)
