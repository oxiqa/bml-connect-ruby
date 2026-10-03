# Specification Quality Checklist: Transaction Status Webhook Handler

**Purpose**: Validate specification completeness and quality before proceeding to planning
**Created**: 2026-09-21
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

## Notes

### Iteration 1 — 2026-09-21

Three [NEEDS CLARIFICATION] markers raised, all within the limit of 3, none defaultable:

| Marker | Requirement | Why it could not be defaulted |
|--------|-------------|-------------------------------|
| Integration surface | FR-002 (draft) | Changed the deliverable and the gem's dependency footprint |
| Trust model | FR-008 (draft) | Security-critical; no signing scheme exists in the published contract |
| Registration scope | FR-013 (draft) | Changed what gets built and whether a whole user story ships |

**Resolved during drafting (not raised as markers):**

- *Transaction state enumeration* — defaulted to verbatim pass-through (FR-005, SC-010). The
  published contract enumerates no states; an invented allow-list would violate Constitution V.
- *Replay and ordering* — defaulted to caller responsibility (FR-014). A gem owning no datastore
  cannot deduplicate; surfacing the identifier is the honest alternative.
- *Delivery semantics* — defaulted to at-least-once and possibly out of order, since the contract
  promises nothing stronger.

### Iteration 2 — 2026-09-21 (all markers resolved)

Answers: framework-agnostic surface · mandatory verify-by-fetch · handling only.

Spec revised accordingly:

- FR-001 fixed the surface as framework-agnostic with no web-framework dependency; SC-012 makes
  that testable.
- FR-006 through FR-010 replaced the open trust question with verify-by-fetch. FR-007 forbids any
  opt-out and SC-004 tests for its absence — without that, the control is a default rather than a
  guarantee.
- FR-009 was **added**, not carried over from the draft: verify-by-fetch turns a public endpoint
  into an outbound-call trigger, so amplification had to be bounded. The same follow-through added
  the retrieve-amplification edge case and FR-010/US3-3 on payload-vs-authoritative disagreement,
  which is the observable signature of a forgery attempt.
- Registration removed from requirements, user stories, edge cases, and success criteria; recorded
  under Out of Scope with the deferral reason, and added as an explicit assumption (the merchant
  has registered a URL by other means) so the gap is visible rather than silent.
- User stories renumbered 1–3; FRs renumbered 001–019; SCs renumbered 001–012. No orphaned
  cross-references remain.

**Status check re-run**: the draft's ⛔ blocking dependency was **downgraded to ⚠️ outstanding
observation**, and this is a real change in readiness, not a softening of language. Under
verify-by-fetch the library reads exactly one field from the untrusted payload — the transaction
identifier — and a wrong guess there fails loudly at the retrieve instead of silently reporting a
false status. The unknown therefore no longer blocks planning, only release.

**Named-resource references (FR-017, FR-018, Context table) reviewed against "no implementation
details":** these name BML API paths, headers, and the vendored contract document, which this
repository treats as contract facts under Constitution III, consistent with the spec for feature
`004`. They are not leaked implementation choices.

### Iteration 3 — 2026-09-21 (`/speckit-clarify`)

Five questions asked and integrated; no [NEEDS CLARIFICATION] markers were introduced or remain.
Checklist state unchanged at **16/16**, but the spec behind it grew materially: 19 → 36 functional
requirements and 12 → 22 success criteria, all of it consequences of decisions the original draft
had left implicit.

| # | Question | Answer | Spec impact |
|---|----------|--------|-------------|
| 1 | Transaction-id extraction | Built-in candidates + caller override | FR-002/002a/002b, SC-011a; ⛔ downgraded to ⚠️ |
| 2 | Stale authoritative read | One delayed re-check | FR-010/010a–d, SC-008a–c, 2 edge cases |
| 3 | Amplification bound | Two-retrieve cap + optional shared secret | FR-009/009a–d, SC-008d–f, 2 edge cases |
| 4 | HTTP response to BML | Advisory status on every result | FR-016a–e, SC-008g–h |
| 5 | Raw payload exposure | Named masked diagnostics only | FR-004a/004b, SC-008i, Key Entities |

**Contradictions repaired** (the spec would otherwise have shipped internally inconsistent):

- The Context section claimed the library reads "only **one** field" from the payload. Answer 2
  added a second — a claimed status, read solely for comparison. Reworded rather than left standing.
- FR-013 enumerated the permitted side effects and did not include the re-check. Amended.
- The assumption "handling is synchronous" now states that the re-check delay is spent inside the
  caller's request, which is the part an integrator needs to see.
- Acceptance scenarios added to User Stories 1 and 2 so the re-check, the shared secret, the
  advisory status, and the no-raw-payload guarantee are covered by scenarios and not only by
  requirements.

**Judgment call, re-reviewed:** FR-016a–e and SC-008g–h name HTTP status codes. "No implementation
details" stays checked — this feature's subject *is* an HTTP callback, so response semantics are
domain facts in the same way the BML paths and the `Authorization` header are, consistent with
feature `004`. FR-016b guards the real risk by forbidding the library from writing a response or
taking a web-framework dependency.

**Worth flagging to planning:** answer 2 was chosen against the recommendation, and it is the one
decision that spends caller latency. FR-010b (delay configurable, zero disables) and SC-008b exist
so that cost is tunable and tested rather than baked in. If UAT observation shows BML's retrieve is
immediately consistent, revisit the default — the re-check would then be pure cost on every
replayed delivery.

### Iteration 4 — 2026-09-27 (`/speckit-clarify`)

Five questions asked and integrated. No [NEEDS CLARIFICATION] markers were introduced or remain.
Checklist state unchanged at **16/16**; the spec grew 36 → 41 functional requirements and 22 → 29
success criteria. Unlike iteration 3, these were not open design questions — every one was a hole in
a decision iteration 3 had already made.

| # | Question | Answer | Spec impact |
|---|----------|--------|-------------|
| 1 | How the shared secret reaches the library | Caller presents the value; library only compares | FR-001, FR-009a, FR-009e, SC-008e/008j, 1 edge case |
| 2 | Accepted inbound body formats | JSON + form-encoded by `Content-Type`, documented fallback | FR-003/003a/003b, US1-3, SC-008k/008l, 1 edge case |
| 3 | Default re-check delay | 3 seconds | FR-010b, SC-008m, 2 assumptions |
| 4 | Maximum inbound body size | None — host application's job, documented | FR-003c, SC-008n, 1 edge case, 1 assumption |
| 5 | Caller-supplied extractor contract | Parsed body + headers → identifier or nothing | FR-002c, SC-011b/011c, 1 edge case |

**The load-bearing correction (answer 1).** FR-009a previously said the library verifies the secret
"against the inbound delivery" while FR-001 hands it only a body and headers. BML chooses the
callback's headers, so a merchant cannot make it send one — the spend-gate as written was
unimplementable against real deliveries, and SC-008e could only ever have passed against a
fabricated test. FR-009e now forbids the library from inferring a location at all.

**Answer 5 for the same reason.** The caller-supplied extractor is what keeps the outstanding UAT
unknown off the release path, so it must cover the case where the identifier is not in the body.
It now receives headers too; a body-only extractor would have left exactly the blocked merchant
blocked.

**Answer 4 is an accepted risk, recorded as one.** The two-retrieve cap bounds outbound calls and
bounds nothing about parsing work, and a configured secret does not help because the body is already
in memory when the handler is called. Chosen against the recommendation: the library does not own
the socket. FR-003c and SC-008n exist so a caller reads this in the quickstart rather than
discovering it in production.

**Judgment call, re-reviewed:** FR-003a names `Content-Type`, JSON, and form-encoded. "No
implementation details" stays checked on the same grounds already accepted for the HTTP status codes
of FR-016a–e — this feature's subject *is* an HTTP callback, so its media types are domain facts,
not a chosen implementation. Both formats are marked `[UNVERIFIED]` under FR-003b.

**Worth flagging to planning:** answers 1 and 5 both widen the handling operation's signature
(presented secret in; headers through to the extractor). The 3-second default of answer 3 is a
judgment, not an observed figure — the same UAT delivery that resolves the identifier field should be
used to check whether BML's read path lags at all, since if it does not, the re-check is pure cost.

### Iteration 5 — 2026-09-27 (`/speckit-clarify`, post-`/speckit-analyze`)

Two questions asked and integrated — both were **defects the analysis pass found in artifacts already
marked complete**, not new design ground. Spec grew 41 → 43 functional requirements and 29 → 31
success criteria. No [NEEDS CLARIFICATION] markers introduced or remaining. Checklist unchanged at
**16/16**.

| # | Question | Answer | Spec impact |
|---|----------|--------|-------------|
| 1 | Card-like data in a payload: reject or scrub? | Scrub and carry on | FR-011 rewritten, FR-011a, US2-5, SC-005a, 1 edge case |
| 2 | "Equivalent results" for a repeated delivery | Equal given an unchanged record | FR-014 rewritten, FR-014a, US1-6, SC-006, SC-006a |

**Both repaired contradictions that were shipping, not gaps.**

Answer 1: FR-011 said the library "MUST NOT **accept**" a PAN arriving in a notification and must
screen it "on the same path the rest of the library already uses" — and that path raises. US2-5 asked
only that such data never reach a log, audit, or error message, which masking satisfies. One reading
rejected the delivery, the other processed it, and the outcome taxonomy had no row either way. The
resolution keeps availability: the PAN screen matches any Luhn-valid 13–19 digit run, so rejecting
would let a coincidental merchant reference permanently discard a genuine payment confirmation to
prevent a leak masking had already prevented. FR-011a records the divergence from the outbound screen
at the screening site so a later reviewer does not "correct" it.

Answer 2: FR-014's "equivalent results" was untestable as written. Taken literally the library cannot
comply — a transaction that genuinely moves from pending to paid between two deliveries *must* report
the new status on the second — and a test written to the literal reading would have forced a cache
that FR-013 and the no-datastore assumption forbid. FR-014 now says equal **given an unchanged
authoritative record**, plus no carried-over state; SC-006a asserts the changed-record case
explicitly.

**Judgment call, re-reviewed:** FR-011a describes the existing screen's behavior ("any 13–19 digit
Luhn-valid run"). "No implementation details" stays checked — it characterizes a control this
repository already ships, in the same way the spec already names BML paths and the `Authorization`
header, and the justification for the divergence is unreadable without it.

**Downstream artifacts needing alignment** (outside this command's scope — it writes only the spec and
this checklist):

- `data-model.md` §5 — add no taxonomy row for card-like data; answer 1 means it is not a distinct
  outcome. The existing rows stand unchanged.
- `tasks.md` T026 — must now assert **both** halves: the data is masked *and* the delivery is still
  handled (SC-005a). As written it only asserts the masking.
- `tasks.md` — still missing the idempotence task the analysis flagged; it should now be written to
  FR-014/SC-006/SC-006a rather than to the old ambiguous wording.

Neither answer invalidates `plan.md`: the plan and research had already assumed masking-and-continue
(research R13, T029), so answer 1 confirms the design rather than changing it.

### Gate status

- **All items pass (16/16, unchanged across three clarification rounds).** Planning complete; ready for `/speckit-implement` once the tasks.md gaps below are closed.
- One item remains outstanding for **release**, not for planning: which inbound field carries the
  transaction identifier must be observed against UAT and recorded in `contracts/bml-remote.md`
  (FR-019, SC-011).
- Planning should expect the hardest task here to be test setup, not logic: verifying a real
  delivery requires **inbound** network reachability from BML UAT, which no previous feature in
  this repository needed.
