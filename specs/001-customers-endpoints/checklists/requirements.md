# Specification Quality Checklist: Customers Endpoints

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
- [x] Every field name matches the published schema exactly (no renaming, splitting, or joining)
- [x] The authentication scheme matches `components.securitySchemes`
- [x] Anything not in the published document is marked `[UNVERIFIED]`
- [x] A verification table exists and is honest about what has *not* been observed live
- [ ] **Every operation observed against UAT** — BLOCKED, see Notes

## Notes

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`.
- Four `[UNVERIFIED]` markers remain, all recorded in `contracts/bml-remote.md`: list pagination
  parameters, the 404 body on an unknown customer id, the effect of archiving on a customer's
  stored tokens, and whether `count` arrives as a string or an integer. None blocks planning;
  all are scheduled for resolution in T033.
- **The live-verification checkbox cannot be ticked yet.** The only BML key currently available
  (from `msgowl/website`'s development credentials) is rejected by UAT with `PP-C-004` even on
  the known-working `/public/transactions` path, so no customer operation has been observed
  end-to-end. A newly issued UAT key from the merchant dashboard is a hard prerequisite for
  closing the verification table. This checklist is deliberately left unticked rather than
  marked complete — the retired `bml_tokenization` shipped four features with all boxes ticked
  and zero live verification, which is the exact failure this section exists to prevent.
- The retired spec's `first_name`/`last_name` model was corrected to BML's single `name` field,
  and its full-replace `PUT` update was corrected to a partial-merge `PATCH`. Both changes are
  recorded in Clarifications with the schema evidence.
