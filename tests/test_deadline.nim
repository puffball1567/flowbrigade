import std/[times, unittest]

import flowbrigade/durations
import flowbrigade/internal/time_source
import flowbrigade/timeout

suite "deadline":
  test "tracks remaining time until the deadline":
    let time = initManualTimeSource()
    let deadline = initDeadline(after = 1.min, timeSource = time)

    check not deadline.expired()
    check deadline.remaining() == 1.min

    time.advance(25.sec)

    check not deadline.expired()
    check deadline.remaining() == 35.sec

  test "expires at the boundary and caps remaining at zero":
    let time = initManualTimeSource()
    let deadline = initDeadline(after = 1.min, timeSource = time)

    time.advance(1.min)

    check deadline.expired()
    check deadline.remaining() == initDuration()

    time.advance(1.min)

    check deadline.expired()
    check deadline.remaining() == initDuration()

  test "zero duration deadline is expired immediately":
    let time = initManualTimeSource()
    let deadline = initDeadline(after = initDuration(), timeSource = time)

    check deadline.expired()
    check deadline.remaining() == initDuration()

  test "rejects negative relative deadlines":
    let time = initManualTimeSource()

    expect TimeoutConfigError:
      discard initDeadline(after = -1.sec, timeSource = time)

  test "can be initialized at an absolute monotonic time":
    let time = initManualTimeSource()
    time.advance(10.sec)

    let future = initDeadlineAt(expiresAt = 25.sec, timeSource = time)
    let past = initDeadlineAt(expiresAt = 5.sec, timeSource = time)

    check future.expiresAt() == 25.sec
    check future.remaining() == 15.sec
    check not future.expired()

    check past.expiresAt() == 5.sec
    check past.remaining() == initDuration()
    check past.expired()

  test "absolute deadline at the current time is expired":
    let time = initManualTimeSource()
    time.advance(10.sec)

    let deadline = initDeadlineAt(expiresAt = 10.sec, timeSource = time)

    check deadline.expiresAt() == 10.sec
    check deadline.expired()
    check deadline.remaining() == initDuration()

  test "rejects negative absolute deadlines":
    let time = initManualTimeSource()

    expect TimeoutConfigError:
      discard initDeadlineAt(expiresAt = -1.sec, timeSource = time)

  test "default constructors use a real time source":
    let relative = initDeadline(after = 1.min)
    let absolute = initDeadlineAt(expiresAt = 1.min)

    check not relative.expired()
    check not absolute.expired()

  test "clamps requested durations to the remaining deadline":
    let time = initManualTimeSource()
    let deadline = initDeadline(after = 1.min, timeSource = time)

    time.advance(20.sec)

    check deadline.clamp(initDuration()) == initDuration()
    check deadline.clamp(10.sec) == 10.sec
    check deadline.clamp(45.sec) == 40.sec

    time.advance(40.sec)

    check deadline.clamp(10.sec) == initDuration()

  test "rejects negative clamp requests":
    let deadline = initDeadline(after = 1.min, timeSource = initManualTimeSource())

    expect TimeoutConfigError:
      discard deadline.clamp(-1.sec)

  test "child deadlines do not outlive their parent":
    let time = initManualTimeSource()
    let parent = initDeadline(after = 1.min, timeSource = time)

    time.advance(20.sec)
    let shortChild = parent.childDeadline(10.sec)
    let longChild = parent.childDeadline(1.min)

    check shortChild.remaining() == 10.sec
    check shortChild.expiresAt() == 30.sec
    check longChild.remaining() == 40.sec
    check longChild.expiresAt() == 1.min

    time.advance(11.sec)

    check shortChild.expired()
    check not longChild.expired()

  test "child deadline accepts zero duration":
    let time = initManualTimeSource()
    let parent = initDeadline(after = 1.min, timeSource = time)

    let child = parent.childDeadline(initDuration())

    check child.expired()
    check child.remaining() == initDuration()
    check child.expiresAt() == initDuration()

  test "child deadline from an expired parent is expired":
    let time = initManualTimeSource()
    let parent = initDeadline(after = 1.min, timeSource = time)

    time.advance(1.min)
    let child = parent.childDeadline(10.sec)

    check child.expired()
    check child.remaining() == initDuration()

  test "rejects negative child deadline duration":
    let parent = initDeadline(after = 1.min, timeSource = initManualTimeSource())

    expect TimeoutConfigError:
      discard parent.childDeadline(-1.sec)

  test "converts remaining deadline to a timeout":
    let time = initManualTimeSource()
    let deadline = initDeadline(after = 1.min, timeSource = time)

    time.advance(15.sec)
    let timeout = deadline.toTimeout()

    check timeout.remaining() == 45.sec

    time.advance(45.sec)

    check timeout.expired()

  test "timeout conversion from expired deadline is expired immediately":
    let time = initManualTimeSource()
    let deadline = initDeadline(after = 1.min, timeSource = time)

    time.advance(1.min)
    let timeout = deadline.toTimeout()

    check timeout.expired()
    check timeout.remaining() == initDuration()
