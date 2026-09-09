---
description: "Task list for Token Charge implementation"
---

# Tasks: Token Charge

**Input**: Design documents from `/specs/004-token-charge/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, **and features
`001` (Foundational), `002` (US1) and `003` (US1) complete** — a charge needs a customer id, a
token id and a transaction id.

**Tests**: INCLUDED — Constitution Principle II (Test-First) is NON-NEGOTIABLE.

**Organization**: Grouped by user story so each is independently implementable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1–US2 (maps to the user stories in spec.md)
- Every task names an exact file path.

## Path Conventions

The charge is **one method on the existing `Customers` resource** — `client.customers.charge`,
posting to `"#{PATH}/charge"` where `Customers::PATH == "/public-customers"` (FR-001, research R8).
Production code lives in `lib/bml_connect/customers.rb`; specs live under `spec/`.

> 💰 **This feature moves money.** Every design refusal in it — no retry, no combined call, no
> `amount` — is load-bearing. If a task seems to make the API less convenient, that is the intent.

---

## Phase 1: Release Gate (Blocks release, NOT build)

**Purpose**: Resolve the one unknown that makes charging the wrong thing possible. Implementation
below may proceed in parallel with this; **nothing in this feature may be released until it is done.**

- [ ] T001 ⛔ [US1] Resolve which identifier `tokenId` expects (`Token#id` vs `Token#token`) against UAT following the procedure in `specs/004-token-charge/data-model.md`, and record the confirmed answer in `specs/004-token-charge/contracts/bml-remote.md`, `specs/004-token-charge/data-model.md`, and the `Customers#charge` RDoc in `lib/bml_connect/customers.rb` (FR-013, SC-008)

**Checkpoint**: identifier confirmed → the release gate for adoption is cleared.

---

## Phase 2: Foundational (Blocking prerequisites for all stories)

**Purpose**: The request path and body shape both user stories build on.

**⚠️ CRITICAL**: No user-story work can begin until this phase is complete.

- [ ] T002 Extend `spec/contract/openapi_conformance_spec.rb` to cover `POST /public-customers/charge`, asserting the path/method exist in `reference/Connect-API.json` and the stub URL derives from `client.base_url` (Constitution II/III)
- [ ] T003 Add a private charge request-body builder to `lib/bml_connect/customers.rb`: it emits exactly `{customerId, transactionId, tokenId}` — no `amount`, no `currency`, no extra keys (FR-002, data-model "What is deliberately absent")

**Checkpoint**: the endpoint is conformance-covered and the body builder exists.

---

## Phase 3: User Story 1 — Charge a stored card (Priority: P1) 🎯 MVP

**Goal**: A merchant can take payment from a previously stored card, against an already-created
transaction, with no cardholder present, and get back a transaction whose `state` is resolved
synchronously.

**Independent Test**: With a customer holding a stored token and a created transaction, call
`client.customers.charge(customer_id:, transaction_id:, token_id:)`; confirm a `TransactionRecord`
is returned with a resolved `state` and no payment URL is needed.

### Tests for User Story 1 (write FIRST; ensure they FAIL before implementing) ⚠️

- [ ] T004 [P] [US1] Write `spec/unit/customers_charge_spec.rb` (failing): each of `customer_id`, `transaction_id`, `token_id` missing or blank is rejected locally **with no remote call** naming the field; `actor` PAN screening; the request body has exactly three keys; the `200` response maps to `BMLConnect::Models::TransactionRecord`; `state` is passed through verbatim (FR-002, FR-006, FR-008, SC-001)
- [ ] T005 [P] [US1] Write `spec/contract/customers_charge_remote_spec.rb` (failing): `POST #{client.base_url}public-customers/charge`, raw `Authorization` header — **no `Bearer`, no `X-App-Id`**; body is exactly `{customerId, transactionId, tokenId}`; error mapping per the shared `001` table (FR-001, FR-009)
- [ ] T006 [P] [US1] Write `spec/unit/customers_charge_no_retry_spec.rb` (failing): simulate a timeout and assert **exactly one** HTTP attempt; repeat for a `500` and a connection reset (FR-004, SC-004)

### Implementation for User Story 1

- [ ] T007 [US1] Implement `Customers#charge(customer_id:, transaction_id:, token_id:, actor: nil)` in `lib/bml_connect/customers.rb`, posting the T003 body to `"#{PATH}/charge"` with `retries: false` so the shared retry policy is bypassed, and returning a `TransactionRecord` (FR-001–FR-006)
- [ ] T008 [P] [US1] Write `spec/integration/customers_charge_uat_spec.rb` (opt-in, gated on `BML_CUSTOMER_ID` + `BML_TOKEN_ID`): charge a genuinely stored card against a freshly created transaction and assert a resolved `state` (SC-003)

**Checkpoint**: a stored card can be charged end-to-end (MVP).

---

## Phase 4: User Story 2 — Understand a failed charge (Priority: P1)

**Goal**: A merchant can tell a declined card (a returned transaction in a failed state) from a
transport failure (a raised availability error), and always has the id needed to reconcile.

**Independent Test**: Force a `200`-with-failed-state and a transport failure; confirm the first
**returns** a record and the second **raises** `AvailabilityError` whose message names the
`transaction_id`, and that neither is converted into the other.

### Tests for User Story 2 (write FIRST; ensure they FAIL before implementing) ⚠️

- [ ] T009 [P] [US2] Write `spec/unit/customers_charge_outcomes_spec.rb` (failing): a `200` with a failed `state` **returns** a `TransactionRecord`; a 4xx/5xx **raises**; the library never converts one into the other (FR-007, SC-005)
- [ ] T010 [P] [US2] Add a failing example asserting `AvailabilityError` raised by `charge` **names the `transaction_id`** in its message (FR-005)
- [ ] T011 [P] [US2] Write `spec/unit/customers_charge_audit_spec.rb` (failing): an audit record is emitted for **every** outcome — success, decline, validation failure, availability failure — carries `transaction_id` + `token_id`, contains no card data, and is emitted **before** any error is re-raised (FR-010, FR-011, SC-002, SC-006)

### Implementation for User Story 2

- [ ] T012 [US2] Implement the outcome taxonomy and failure auditing in `Customers#charge` (`lib/bml_connect/customers.rb`): map returns vs raises per data-model, and add a charge-specific audit call that passes the real `outcome` — the existing `Customers#audit` helper hardcodes `outcome: :success`, so it must not be reused unchanged (FR-007, FR-010, FR-011)
- [ ] T013 [US2] Resolve `[UNVERIFIED]` #2 against UAT — whether a decline arrives as `200`-with-failed-state or a non-2xx status — and update the decline/outage table in `specs/004-token-charge/contracts/bml-remote.md`

**Checkpoint**: US1 and US2 both work independently; declines and outages are distinguishable and audited.

---

## Phase 5: Safety Verification (UAT — unexpected *success* is the danger)

**Purpose**: Each item below is a case where an unexpected **success** would be worse than a
failure. Observe on UAT and record loudly; do not assume.

- [ ] T014 [US1] Resolve `[UNVERIFIED]` #3: charge the same transaction twice on UAT — does BML reject it or double-charge? If it double-charges, add a prominent warning to `specs/004-token-charge/contracts/library-api.md` and the gem `README.md`
- [ ] T015 [US1] Resolve `[UNVERIFIED]` #4: charge a **deleted** token — it MUST be rejected with a distinguishable error; record the observed error in `specs/004-token-charge/contracts/bml-remote.md`
- [ ] T016 [US1] Resolve `[UNVERIFIED]` #5: charge a token with a **mismatched** `customerId` — it MUST be rejected; if it succeeds, stop and report to BML (tokens would be chargeable across customers)
- [ ] T017 [US1] Add `spec/unit/customers_charge_surface_spec.rb` asserting no charge-related method accepts an `amount` keyword and that `BMLConnect::Customers.public_instance_methods(false)` is exactly `%i[archive charge create list retrieve update]` — proving `charge` was added and no combined create-and-charge method exists (FR-003, SC-007)

**Checkpoint**: both release gates (T001 + T014–T016) are observed, not assumed.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T018 Close the verification table in `specs/004-token-charge/contracts/bml-remote.md`; all five `[UNVERIFIED]` items resolved or explicitly re-scoped
- [ ] T019 [P] Update the gem `README.md` with the full four-step flow, stating plainly that charging is two calls and that the amount lives on the transaction (FR-003)
- [ ] T020 [P] Add a `CHANGELOG.md` entry under `[Unreleased]` for `Customers#charge`
- [ ] T021 [P] Run `bundle exec rubocop` and clear any new offenses in `lib/bml_connect/customers.rb` and the new specs
- [ ] T022 Verify no code path can retry a charge: `grep` for the retry helper in `lib/bml_connect/customers.rb` and confirm the T006 assertions hold (FR-004, SC-004)

---

## Dependencies & Execution Order

### Phase dependencies

- **Release Gate (Phase 1)**: independent; runs in parallel with the build, blocks release only.
- **Foundational (Phase 2)**: BLOCKS all user stories.
- **User stories (Phases 3–4)**: both depend on Foundational; both are P1.
- **Safety Verification (Phase 5)**: needs `#charge` (T007/T012) and UAT access.
- **Polish (Phase 6)**: after the desired stories are complete.

```
001 Foundational + 002 US1 + 003 US1   ← hard prerequisites
   │
   ├─> T001 RELEASE GATE (parallel with build; blocks release)
   │
   └─> Foundational (T002-T003)
         ├─> US1 (T004-T008)  P1  MVP
         └─> US2 (T009-T013)  P1
               └─> Safety Verification (T014-T017)
                     └─> Polish (T018-T022)
```

### User story dependencies

- **US1 (P1)**: starts after Foundational; no dependency on US2.
- **US2 (P1)**: starts after Foundational; shares the same `#charge` method as US1, so in practice
  T012 extends the T007 implementation rather than a separate file.

### Within each story

- Tests (T004–T006, T009–T011) are written and MUST FAIL before implementation.
- Body builder (T003) before the method (T007) before the taxonomy/audit extension (T012).

### Parallel opportunities

- T004, T005, T006 (US1 tests — different files) can run in parallel.
- T009, T010, T011 (US2 tests) can run in parallel.
- T014, T015, T016 (independent UAT observations) can run in parallel once `#charge` exists.
- T019, T020, T021 (docs/lint, different files) can run in parallel.
- T001 (release gate) runs in parallel with the entire build.

---

## Parallel Example: User Story 1

```bash
# Launch the three US1 test tasks together (all different files, all failing first):
Task: "Write spec/unit/customers_charge_spec.rb"
Task: "Write spec/contract/customers_charge_remote_spec.rb"
Task: "Write spec/unit/customers_charge_no_retry_spec.rb"
```

---

## Implementation Strategy

### MVP first (User Story 1 only)

1. Foundational (T002–T003).
2. US1 (T004–T008) → **STOP and VALIDATE**: a stored card can be charged.
3. Run T001 in parallel throughout; do not release until it and T014–T016 are done.

### Incremental delivery

1. Foundational → US1 (MVP: charge works) → US2 (failures are legible and audited).
2. Safety Verification hardens the money-movement edges.
3. Polish closes the contract table and ships docs.

### Release gates (both mandatory)

1. **T001** — the `tokenId` identifier is confirmed.
2. **T014–T016** — double-charge, deleted-token and customer-mismatch behavior are observed, not assumed.

---

## Notes

- [P] = different files, no dependency on an incomplete task.
- Every user-story task carries a `[US#]` label for traceability; Foundational and Polish tasks do not.
- Verify each test fails before implementing it (Constitution II).
- `#charge` MUST pass `retries: false` — a retried charge with no idempotency key risks a double charge.
- The charge audit path is deliberately asymmetric with the rest of `Customers` (it audits failures too); that inconsistency is intended (research R6).
- Commit after each task or logical group.
