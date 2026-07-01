# Intellectual Property Notes

This document records engineering due-diligence notes for algorithms and
operational patterns used by FlowBrigade. It is not legal advice.

## Standards and Common Operational Patterns

FlowBrigade may implement algorithms or control patterns that are publicly
described in standards, books, operational guides, or long-standing OSS
practice. Implementations must be written for FlowBrigade's own API and tests,
without copying code from other OSS projects.

## Retry Allowance

Before adding `RetryAllowance`, the project reviewed public usage of retry
budget style controls and searched Google Patents for obvious direct matches
using terms such as:

- `retry budget`
- `retry storm budget`
- `external service guard retry rate limit circuit breaker`
- `service guard circuit breaker rate limit`

The review found retry budget style controls in established resilience tooling,
including Finagle's `RetryBudget`, where retry budgets are documented as a way
to prevent retry storms. These projects were treated as evidence that the
pattern is commonly used, not as implementation sources to copy from.

FlowBrigade intentionally exposes this feature as `RetryAllowance` rather than
copying another library's API name or shape. The implementation records original
work and retry consumption using FlowBrigade's own keyed window state and result
types.

## Contact and Remediation

If you believe FlowBrigade includes code or behavior that infringes your rights,
please contact the maintainer with enough detail to review the claim. The
project will respond in good faith and may modify, disable, or remove the
affected implementation while the concern is investigated.
