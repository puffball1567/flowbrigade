import std/[httpcore, times]

import flowbrigade
import prologue

proc remainingDeadline(deadline: Deadline): Duration {.gcsafe.} =
  {.cast(gcsafe).}:
    result = deadline.remaining()

proc expiredDeadline(deadline: Deadline): bool {.gcsafe.} =
  {.cast(gcsafe).}:
    result = deadline.expired()

proc remainingMilliseconds(value: Duration): string =
  $(value.inNanoseconds div 1_000_000)

proc deadlineMiddleware*(
    deadline: Deadline;
    deniedStatusCode = 504;
    deniedBody = "Deadline expired";
    remainingHeader = "X-FlowBrigade-Deadline-Remaining-Ms"
): HandlerAsync =
  ## Stops a Prologue request when a caller-owned deadline has expired.
  ##
  ## The middleware does not create a per-request deadline by itself. Pass a
  ## deadline owned by the surrounding request pipeline or test.
  result = proc(ctx: Context) {.async, gcsafe.} =
    let remaining = deadline.remainingDeadline()
    if remainingHeader.len > 0:
      ctx.response.setHeader(remainingHeader, remaining.remainingMilliseconds())
    if deadline.expiredDeadline():
      ctx.response.code = HttpCode(deniedStatusCode)
      ctx.response.body = deniedBody
      ctx.response.setHeader("Content-Type", "text/plain; charset=UTF-8")
    else:
      await switch(ctx)
