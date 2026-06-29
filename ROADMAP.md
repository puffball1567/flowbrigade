# Roadmap

This roadmap is intentionally conservative. The package should stay focused on
time-based control utilities.

## v0.1

- duration parsing
- duration formatting
- duration unit helpers
- fixed backoff
- linear backoff
- exponential backoff
- jitter modes
- sync retry
- token bucket rate limiter
- fixed window rate limiter
- sliding window rate limiter
- keyed in-memory fixed window limiter
- rate limit result metadata
- non-consuming rate limit inspection
- compound limiter
- storage interface for fixed-window rate limiting
- in-memory storage adapter
- Redis fixed-window adapter package
- internal manual time source for tests
- async retry
- throttle
- debounce
- circuit breaker
- timeout helpers

## v0.2 Candidates

- richer examples
- Redis adapter CI with a real Redis service
- Redis-backed token bucket limiter
- adapter policy documentation
- performance notes
- benchmark smoke suite
- default retry sleep helpers
- retry and circuit breaker observer hooks
- middleware integration patterns
- async fixed-window storage surface
- Memcached fixed-window adapter package
- adapter provider selection model
- ready Redis client bridge package
- more deterministic jitter tests
- additional timeout integration helpers
- async convenience wrappers
- optional Memcached-backed rate limiting adapter

## Not Planned For Core

- timezone handling
- calendar math
- date formatting
- localization
- relative humanized date text
- cron scheduling
- HTTP-framework-specific middleware
- built-in Redis, Memcached, or database dependency in the core package

Some of these may make sense as separate packages or integrations later.
