---
description: "Task list for Token Charge implementation"
---

# Tasks: Token Charge

**Input**: Design documents from `/specs/004-token-charge/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, **and features
`001` (Foundational), `002` (US1) and `003` (US1) complete** — a charge needs a customer id, a
token id and a transaction id.

**Tests**: INCLUDED — Constitution Principle II is NON-NEGOTIABLE.

**Organization**: Grouped by user story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel · **[Story]**: US1–US2

## Path Conventions

One method added to the existing `lib/bml_connect/tokens.rb`; specs in `spec/`.

> 💰 **This feature moves money.** Every design refusal in it — no retry, no combined call, no
> `amount` — is load-bearing. If a task seems to be making the API less convenient, that is the
> intent.

---

## Phase 1: Release Gate (Blocking)

- [ ] T001 ⛔ **Resolve which identifier `tokenId` expects** (`Token#id` vs `Token#token`) against UAT, following the procedure in `data-model.md`. Record the answer in `contracts/bml-remote.md`, `data-model.md`, and the method RDoc. **Nothing in this feature may be released until this is done.** Implementation below may proceed in parallel

---

## Phase 2: Foundational

- [ ] T002 Extend `spec/contract/openapi_conformance_spec.rb` to cover `POST /public-customers/charge`
- [ ] T003 Add the charge request builder to `lib/bml_connect/tokens.rb` (private): exactly three keys, no `amount`, no extras

---

## Phase 3: User Story 1 — Charge a stored card (P1) 🎯 MVP

- [ ] T004 [P] [US1] Write `spec/unit/tokens_charge_spec.rb` (failing): each of `customer_id`, `transaction_id`, `token_id` missing or blank is rejected locally **with no remote call**; actor PAN screening; the request body has exactly three keys; the response maps to `TransactionRecord`; `state` passed through verbatim
- [ ] T005 [P] [US1] Write `spec/contract/tokens_charge_remote_spec.rb` (failing): `POST #{client.base_url}public-customers/charge`, raw `Authorization`, **no `Bearer`, no `X-App-Id`**; body is exactly `{customerId, transactionId, tokenId}`; error mapping per the shared table
- [ ] T006 [P] [US1] Write a failing spec asserting **the charge is never retried** (SC-004): simulate a timeout and assert **exactly one** HTTP attempt; repeat for a 500 and a connection reset
- [ ] T007 [US1] Implement `Tokens#charge(customer_id:, transaction_id:, token_id:, actor: nil)`, wired to bypass the shared retry policy
- [ ] T008 [P] [US1] Write `spec/integration/tokens_charge_uat_spec.rb` (opt-in, gated on `BML_CUSTOMER_ID` + `BML_TOKEN_ID`)

**Checkpoint**: a stored card can be charged.

---

## Phase 4: User Story 2 — Understand a failed charge (P1)

- [ ] T009 [P] [US2] Write failing specs for the outcome taxonomy: a `200` with a failed state **returns** a record; a 4xx/5xx **raises**; the library never converts one into the other (SC-005)
- [ ] T010 [P] [US2] Write a failing spec asserting `AvailabilityError` from `charge` **names the `transaction_id`** in its message (FR-005)
- [ ] T011 [P] [US2] Write failing specs asserting an audit record is emitted for **every** outcome — success, decline, validation failure, availability failure — and that the record is emitted **before** the error is re-raised (FR-011, SC-006)
- [ ] T012 [US2] Implement the outcome taxonomy and failure auditing in `#charge`
- [ ] T013 [US2] **Resolve `[UNVERIFIED]` #2**: whether a decline arrives as `200`-with-failed-state or as a non-2xx status. Update the contract table

---

## Phase 5: Safety Verification

Each of these is a case where an unexpected **success** is the dangerous outcome. Record loudly.

- [ ] T014 **Resolve `[UNVERIFIED]` #3**: charge the same transaction twice on UAT. Does BML reject it, or double-charge? If it double-charges, add a prominent warning to `contracts/library-api.md` and the README
- [ ] T015 **Resolve `[UNVERIFIED]` #4**: charge a **deleted** token. It must be rejected with a distinguishable error
- [ ] T016 **Resolve `[UNVERIFIED]` #5**: charge a token with a **mismatched** `customerId`. It must be rejected — if it succeeds, stop and report to BML, as it would mean tokens are chargeable across customers
- [ ] T017 Assert no charge method accepts an `amount` keyword (SC-007), and that `Tokens.public_instance_methods(false)` is exactly `%i[charge delete list retrieve]`

---

## Phase 6: Polish

- [ ] T018 Close the verification table in `contracts/bml-remote.md`; all five `[UNVERIFIED]` items resolved or explicitly re-scoped
- [ ] T019 [P] Update the gem `README.md` with the full four-step flow, stating plainly that charging is two calls and that the amount lives on the transaction
- [ ] T020 [P] Add a `CHANGELOG.md` entry under `[Unreleased]`
- [ ] T021 [P] Run `bundle exec rubocop`
- [ ] T022 Verify no code path can retry a charge (`grep` for the retry helper in `tokens.rb`, plus the T006 assertions)

---

## Dependencies

```
001 Foundational + 002 US1 + 003 US1   ← hard prerequisites
   │
   ├─> T001 RELEASE GATE (parallel with build, blocks release)
   │
   └─> Foundational (T002-T003)
         ├─> US1 (T004-T008)  P1  MVP
         └─> US2 (T009-T013)  P1
               └─> Safety Verification (T014-T017)
                     └─> Polish (T018-T022)
```

## Release gates

Both mandatory:

1. **T001** — the `tokenId` identifier is confirmed.
2. **T014–T016** — double-charge, deleted-token and customer-mismatch behavior are observed, not
   assumed.
