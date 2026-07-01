# Intellectual Property Notes

This document records engineering due-diligence notes for algorithms used by
FlowBrigade. It is not legal advice.

## Standards-Described Algorithms

FlowBrigade may implement algorithms that are publicly described in standards,
academic material, or long-standing operational literature. The implementation
must be written for FlowBrigade's own API and tests, without copying code from
other OSS projects.

## GCRA

Before adding the GCRA-style limiter, the project reviewed public descriptions
of the Generic Cell Rate Algorithm and searched Google Patents for obvious
direct matches using terms such as:

- `Generic Cell Rate Algorithm`
- `GCRA`
- `Theoretical Arrival Time`
- `ITU-T I.371`
- `ATM Forum`

The review found GCRA described as an ATM/ITU-T/ATM Forum traffic policing and
shaping algorithm based on theoretical arrival time and continuous-state leaky
bucket descriptions. No obvious direct Google Patents result blocking a
standard GCRA-style in-process limiter was found during this review.

The review also found existing OSS usage of GCRA-style rate limiting, including
Rust's `governor` crate and the `redis-cell` Redis module. These projects were
treated as evidence that GCRA is a commonly used public algorithmic approach,
not as implementation sources to copy from.

The FlowBrigade implementation is an independent GCRA-style limiter written
against the public algorithmic description and FlowBrigade's `RateLimitResult`
API. It is not copied from another OSS implementation.

## Contact and Remediation

If you believe FlowBrigade includes code or behavior that infringes your rights,
please contact the maintainer with enough detail to review the claim. The
project will respond in good faith and may modify, disable, or remove the
affected implementation while the concern is investigated.
