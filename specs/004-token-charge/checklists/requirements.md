# Specification Quality Checklist: Token Charge

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
- [ ] **Every operation observed against UAT** — BLOCKED, see Notes

## Money-Movement Safety *(specific to this feature)*

- [x] No automatic retry on any charging call
- [x] Timeout recovery is documented as reconciliation, not retry
- [x] The error raised on an unknown outcome names the id needed to reconcile
- [x] Decline and transport failure are distinguishable outcomes
- [x] Failed charges are audited, not only successful ones
- [x] No convenience method collapses the platform's two-step flow into one
- [ ] **Double-charge behavior observed** — scheduled T014
- [ ] **Identifier semantics confirmed** — ⛔ release blocker, scheduled T001

## Notes

- ⛔ **This feature is specified but not releasable.** It is unconfirmed whether the `tokenId`
  field expects `Token#id` or `Token#token`. Both exist on every token; the document does not
  say. The inference from path-parameter naming is strong but unverified, and charging the wrong
  identifier is a money-movement defect. Implementation may be built and merged; adoption waits
  on T001.
- Five `[UNVERIFIED]` items are open. Three of them (T014–T016 — double charge, deleted token,
  customer mismatch) share a property worth stating: an unexpected **success** is the dangerous
  outcome, not a failure. They are written as safety verifications rather than edge-case tests.
- **This feature had no equivalent in the retired `bml_tokenization` specs.** Those modelled a
  stored-card charge as a `card_reference` parameter on transaction create, which would perform a
  server-side charge in one call. That endpoint and that flow do not exist. The real flow is two
  calls, and the library deliberately keeps it that way (FR-003).
- The retired specs also applied automatic retry to their charging path, justified by an
  idempotency guarantee they had invented. Dropped entirely: the charge schema has three fields,
  none an idempotency key (FR-004, SC-004).
- **The live-verification checkbox cannot be ticked.** Beyond the `PP-C-004` credential blocker
  affecting every feature, verifying a charge requires a genuinely stored card, which requires a
  human to complete a hosted payment in a browser. No unattended suite can close this.
