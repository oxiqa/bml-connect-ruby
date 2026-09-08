# Specification Quality Checklist: Stored Card Tokens

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-09-07
**Feature**: [spec.md](../spec.md)

## Content Quality

- [x] No implementation details (languages, frameworks, APIs)
- [x] Focused on user value and business needs
- [x] Written for non-technical stakeholders
- [x] All mandatory sections completed

## Requirement Completeness

- [x] No [NEEDS CLARIFICATION] markers remain
- [x] Requirements are testable and unambiguous
- [x] Success criteria are measurable
- [x] Success criteria are technology-agnostic (no implementation details)
- [x] All acceptance scenarios are defined
- [x] Edge cases are identified
- [x] Scope is clearly bounded
- [x] Dependencies and assumptions identified

## Feature Readiness

- [x] All functional requirements have clear acceptance criteria
- [x] User scenarios cover primary flows
- [x] Feature meets measurable outcomes defined in Success Criteria
- [x] No implementation details leak into specification

## Contract Fidelity *(added at constitution v2.0.0)*

- [x] Every path in `contracts/bml-remote.md` is quoted from `reference/Connect-API.json`
- [x] Every field name matches the published schema exactly
- [x] The authentication scheme matches `components.securitySchemes`
- [x] Anything not in the published document is marked `[UNVERIFIED]`
- [x] A verification table exists and is honest about what has *not* been observed live
- [x] **Absent capabilities are documented as absent**, not silently omitted
- [ ] **Every operation observed against UAT** — BLOCKED, see Notes

## Notes

- Seven `[UNVERIFIED]` items remain, all listed at the foot of `contracts/bml-remote.md`. Two are
  load-bearing:
  - **Which identifier `tokenId` refers to** (`Token#id` vs `Token#token`). Feature `004` moves
    money using it. Flagged in research R3 and as a hard blocker in `tasks.md`.
  - **Cross-customer token access.** If BML resolves `tokenId` globally rather than within the
    customer path segment, an integrator could enumerate other customers' stored cards. Treated
    as a security test (T015), not an edge case.
- **The live-verification checkbox cannot be ticked.** No token operation has been observed
  against UAT — the available key is rejected with `PP-C-004`. Left unticked deliberately.
- This feature replaces two retired ones. The most consequential correction: the retired
  `004-tokenization-endpoints` specified `POST /tokens` accepting a single-use `card_handle`.
  Neither the endpoint nor the concept exists in BML Connect. Tokens are created only as a side
  effect of a tokenizing transaction (feature `003`), and the absence of a create path here is
  enforced by a test (T022) rather than left to reviewer memory.
