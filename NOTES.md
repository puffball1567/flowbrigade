# project notes

## Rename decision

The package has been renamed from `timekeeper` to `flowbrigade`.

Final naming:

- Repository name: `flowbrigade`
- Nimble package name: `flowbrigade`
- Import path: `import pkg/flowbrigade`

Reasoning: the scope expanded from basic duration/retry/rate-limit helpers into
broader time-based flow control: throttling, debouncing, circuit breaking, and
timeouts. `flowbrigade` is more distinctive than `timekeeper` and better matches
the traffic-control metaphor while avoiding a date/time-library impression.

## Original timekeeper notes

## Direction

Build `timekeeper` as a small Nim OSS library focused on time-based control utilities:

- duration parsing
- retry/backoff policies
- rate limiting

This should stay separate from a Carbon-like date/time convenience library. Carbon-style helpers are related by domain, but they solve a different problem: date formatting, calendar math, relative display text, and localization. Mixing both directions would make the package purpose less clear.

## Package name

Preferred naming:

- Repository directory/name: `timekeeper` or `nim-timekeeper`
- Nimble package name: `timekeeper`
- Import path: `import pkg/timekeeper`

As of the local check against the Nimble package list downloaded during the discussion, neither `timekeeper` nor `nim-timekeeper` appeared as an exact package name. A full GitHub repository name check was started but interrupted before completion, so that still needs a final check before publishing.

## Existing Nim packages nearby

Related packages found in the Nimble package list:

- `backoff`: exponential backoff implementation with jitter variants. It appears old, with a latest GitHub release shown as `v0.1` from 2018-11-18.
- `limiter`: HTTP-oriented rate limiting library.
- `clown_limiter`: Jester-specific rate limiter plugin.
- `humanize`: formats numbers, file sizes, times, durations, and lists for display, but it is not a duration parser centered on strings like `1h30m`.

Conclusion: individual pieces exist, but a focused, unified package for duration parsing plus retry/backoff plus generic rate limiting still looks useful.

## Proposed scope

MVP:

- `parseDuration("250ms")`
- `parseDuration("1h30m")`
- `parseDuration("2d4h")`
- `formatDuration(duration)` for compact output
- fixed, linear, and exponential backoff policies
- jitter support: none, full, equal, decorrelated
- sync retry helper
- async retry helper if it can be done cleanly
- token bucket rate limiter
- fixed window rate limiter
- dependency-free implementation using `std/times`

Out of scope for the first version:

- Carbon-style date helpers
- timezone and locale handling
- HTTP-framework-specific middleware
- persistent/distributed rate limiting
- cron scheduling

## Example API sketch

```nim
import pkg/timekeeper

let timeout = parseDuration("2s")
let delay = parseDuration("250ms")

let policy = expBackoff(
  initial = parseDuration("100ms"),
  max = parseDuration("5s"),
  jitter = fullJitter
)

retry(policy, maxAttempts = 5):
  callUnreliableApi()

var limiter = tokenBucket(rate = 10.perSecond, burst = 20)

if limiter.allow():
  handleRequest()
```

## Positioning

Suggested README tagline:

> Duration parsing, retry policies, and rate limiting for Nim.

Avoid positioning it as a Carbon clone. If a Carbon-inspired library is created later, it should be a separate package, for example `datekeeper`, `chronokit`, or another clearly date-focused name.
