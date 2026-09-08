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
- [x] **Every operation observed against UAT** — all five verified live 2026-09-08, see Notes

## Notes

- Items marked incomplete require spec updates before `/speckit-clarify` or `/speckit-plan`.
- Of the four original `[UNVERIFIED]` markers, **two are resolved** by the 2026-09-08 UAT run
  (recorded in `contracts/bml-remote.md`): the 404 body on an unknown id is
  `{"message":"Customer not found","code":"PP-CU-001"}`, and `count` arrives as an **Integer**.
  Two remain and are correctly out of scope for this feature: list pagination parameters (not
  exercised) and the archive→stored-token cascade (depends on feature `002`).
- **The live-verification checkbox is now ticked — legitimately.** A provisioned UAT key
  authenticates on `/public/me` and every customer path, and all five operations
  (`create`/`retrieve`/`list`/`update`/`archive`) were exercised end-to-end via
  `spec/integration/customers_uat_spec.rb` and passed. The live run also surfaced two document
  discrepancies the OpenAPI file hid — responses use `_id`/`id` (both present, equal) and
  `createdAt`/`updatedAt` rather than `created`/`updated` — which is exactly why this box requires
  observation, not stubs. The credentials live only in this repo's git-ignored `.env`.
- The retired spec's `first_name`/`last_name` model was corrected to BML's single `name` field,
  and its full-replace `PUT` update was corrected to a partial-merge `PATCH`. Both changes are
  recorded in Clarifications with the schema evidence.
