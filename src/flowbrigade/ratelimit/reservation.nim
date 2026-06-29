import std/[asyncdispatch, times]

import ./errors
import ./result
import ./wait

type
  RateLimitReservation* = object
    accepted*: bool
    readyAfter*: Duration
    decision*: RateLimitResult

proc reserve*(
    decision: RateLimitResult;
    maxWait = initDuration()
): RateLimitReservation =
  ## Converts a decision into a waitable reservation shape.
  ##
  ## This is a framework-neutral contract. For distributed or strict future
  ## capacity reservation, use an adapter that explicitly advertises
  ## `rlcReservation`.
  let delay = decision.waitDelay()
  let accepted = decision.allowed or maxWait <= initDuration() or delay <= maxWait
  RateLimitReservation(
    accepted: accepted,
    readyAfter: delay,
    decision: decision
  )

proc raiseIfRejected*(reservation: RateLimitReservation) =
  if not reservation.accepted:
    raise newException(RateLimitError, "rate-limit reservation exceeds max wait")

proc wait*(reservation: RateLimitReservation; sleep: RateLimitSleepProc) =
  reservation.raiseIfRejected()
  reservation.decision.wait(sleep)

proc waitAsync*(
    reservation: RateLimitReservation;
    sleep: AsyncRateLimitSleepProc
): Future[void] {.async.} =
  reservation.raiseIfRejected()
  await reservation.decision.waitAsync(sleep)
