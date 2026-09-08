# Specification Quality Checklist: Transactions V2

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
- [x] **Deviations from the published document are recorded, not hidden** — the legacy v1 create
- [ ] **Every operation observed against UAT** — BLOCKED, see Notes

## Backward Compatibility *(specific to this feature)*

- [x] Every change is additive; no released method changes signature or return type
- [x] A compatibility suite pinning current behavior is scheduled **before** any modification (T001)
- [x] The downstream consumer's expectations are enumerated (six fields, six call sites)
- [ ] **`msgowl/website` verified to pass unchanged** — scheduled as release gate T029

## Notes

- Six `[UNVERIFIED]` items remain, listed at the foot of `contracts/bml-remote.md`. One is a
  **production blocker**: which v2 response field carries the hosted payment URL. The v1 response
  uses `url`, which is absent from the v2 schema. Without it there is nowhere to send the
  cardholder, so `#payment_url` raises rather than returning nil, and `create_v2` must not be
  adopted in production until T021 settles it.
- **This feature knowingly calls one undocumented endpoint.** `POST /public/transactions` is not
  in `Connect-API.json` but is live and carries all current production traffic. Removing it to
  satisfy Constitution III would break `msgowl/website` immediately. It is retained, deprecated,
  and recorded in three places: the contract, the plan's Complexity Tracking, and an explicit
  allow-list entry in the conformance test. Visible, not hidden — which is the principle's intent.
- The retired spec normalized `state` into four canonical values via an invented 20-entry alias
  table. That is dropped: `state` is passed through verbatim, because production code already
  branches on BML's own `CONFIRMED` / `CANCELLED` / `FAILED` and remapping would break it.
- The retired spec applied automatic retry to create, justified by an idempotency guarantee it
  had invented. Dropped — no idempotency key is documented, so create and capture are never
  auto-retried (FR-016, SC-007).
- **The live-verification checkbox cannot be ticked**: the available UAT key is rejected with
  `PP-C-004`. Additionally, SC-002 (tokenization end-to-end) requires a human to complete a
  hosted payment in a browser and cannot be closed by an unattended suite.
