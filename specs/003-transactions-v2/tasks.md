---
description: "Task list for Transactions V2 implementation"
---

# Tasks: Transactions V2

**Input**: Design documents from `/specs/003-transactions-v2/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, **and feature `001`
Foundational (T004–T012)** for the shared `Resource`, errors, masking and audit infrastructure.

**Tests**: INCLUDED — Constitution Principle II is NON-NEGOTIABLE.

**Organization**: Grouped by user story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel · **[Story]**: US1–US5

## Path Conventions

Source in `lib/bml_connect/`, specs in `spec/`. New operations are added to the **existing**
`lib/bml_connect/transactions.rb`, so implementation tasks on it are sequential.

> ⚠️ **This feature modifies released, in-production code.** Every change is additive. If a task
> would alter the behavior, signature, or return type of `create`, `get`, or `list`, stop — that
> is out of scope and breaks `msgowl/website`.

---

## Phase 1: Backward-Compatibility Pin (Blocking — do this FIRST)

**Purpose**: Freeze current behavior before touching anything, so a regression is impossible to
miss.

- [ ] T001 Write `spec/contract/transactions_v1_compat_spec.rb` (must pass **immediately**, against unmodified code): asserts `create` posts to `#{client.base_url}transactions` with `signature`, `apiVersion`, `appVersion`, `signMethod`; that `create`, `get` and `list` each return a `Faraday::Response`; and that `resp.body` is symbol-keyed
- [ ] T002 Add a `msgowl/website`-shaped smoke spec asserting the six response fields the website reads (`:id`, `:url`, `:state`, `:expires`, `:merchantId`, `:paddedCardNumber`) are reachable off a stubbed v1 response

**Checkpoint**: T001 and T002 green on unmodified code. They must stay green through every later task.

---

## Phase 2: Foundational

- [ ] T003 [P] Create `lib/bml_connect/models/transaction_record.rb` — whitelisted v2 response object per data-model.md, with `#payment_url` (raises `UnverifiedFieldError` when no candidate field is present) and `#tokenized?`. **Do not touch `models/transaction.rb`**
- [ ] T004 [P] Create `lib/bml_connect/models/tokenization_details.rb` — input validation for the four fields and their conditional rules
- [ ] T005 Add `UnverifiedFieldError` to `lib/bml_connect/errors.rb`
- [ ] T006 Extend `spec/contract/openapi_conformance_spec.rb` for this feature's paths, with the legacy `POST /public/transactions` **explicitly allow-listed as a documented exception**, carrying a comment pointing at `contracts/bml-remote.md`
- [ ] T007 Require the new files from `lib/bml_connect.rb`

---

## Phase 3: User Story 1 — Create on v2 (P1) 🎯 MVP

- [ ] T008 [P] [US1] Write `spec/unit/transactions_v2_spec.rb` (failing): `amount` must be a positive Integer — **Float and String rejected, never coerced**; `currency` required; variants 1/2/5 rejected by name; `customerId` and inline `customer` mutually exclusive; PAN screening; audit emitted; **payment URL absent from `#to_h`, `#inspect`, the log line, and the audit record**
- [ ] T009 [P] [US1] Write `spec/contract/transactions_v2_remote_spec.rb` (failing): `POST #{client.base_url}public/v2/transactions`, raw `Authorization`, no `Bearer`, no `X-App-Id`, **no `signature` field**; maps 201 → `TransactionRecord`; error mapping
- [ ] T010 [P] [US1] Write a failing spec asserting **create is never auto-retried** (SC-007): simulate a timeout, assert exactly one HTTP attempt was made
- [ ] T011 [US1] Implement `Transactions#create_v2(details, actor: nil)`
- [ ] T012 [US1] Add a one-time deprecation warning to the existing `create`, naming `create_v2`. **Behavior otherwise unchanged** — T001 must stay green
- [ ] T013 [P] [US1] Write `spec/integration/transactions_v2_uat_spec.rb` (opt-in, gated)

**Checkpoint**: v2 create works; v1 untouched.

---

## Phase 4: User Story 2 — Tokenization (P1)

- [ ] T014 [P] [US2] Write `spec/unit/tokenization_details_spec.rb` (failing), one example per rule: `tokenize` required; `paymentType` required and in `RECURRING`/`UNSCHEDULED`; `recurringFrequency` required and in the documented set when `RECURRING`; `expiryDate` required when `RECURRING`; `expiryDate` must be `yyyy-mm-dd`; `expiryDate` must be in the future. **Every one asserts no remote call was made**
- [ ] T015 [P] [US2] Write contract specs (failing): `tokenizationDetails` serialized exactly as the four documented keys, nested, with no extra fields
- [ ] T016 [US2] Wire `tokenizationDetails` into `create_v2`
- [ ] T017 [US2] **Manual UAT verification (SC-002)** — cannot be automated: create a tokenizing transaction, complete it in a browser with a UAT test card, then confirm a token appears via `client.tokens.list(customer_id)`. Record the outcome in `contracts/bml-remote.md`
- [ ] T018 [US2] **Resolve `[UNVERIFIED]` #5**: whether `tokenizationDetails` works without a `customerId`

**Checkpoint**: the migration's core capability is proven end-to-end.

---

## Phase 5: User Story 3 — Retrieve (P1)

- [ ] T019 [P] [US3] Write retrieve unit + contract specs (failing): `GET …public/transactions/{id}`; **`state` passed through verbatim, never normalized** (research R8); whitelisting; 404 → `NotFoundError`
- [ ] T020 [US3] Implement `Transactions#retrieve(id, actor: nil)` alongside the untouched `get`
- [ ] T021 [US3] **Resolve `[UNVERIFIED]` #1 — the payment-URL field.** Create one v2 transaction on UAT, dump the raw response, record which field carries the hosted URL. **BLOCKS production use of `create_v2`**
- [ ] T022 [US3] **Resolve `[UNVERIFIED]` #2, #3, #6**: whether v2 accepts a `signature`; the `state` values v2 returns; whether a v2-created transaction is retrievable at the v1 retrieve path

---

## Phase 6: User Story 4 — Update (P3)

- [ ] T023 [P] [US4] Write update unit + contract specs (failing): `PATCH …public/transactions/{id}`; only `customerReference`, `localData`, `pnr` accepted; **only supplied keys sent, no nulls**; empty changes rejected
- [ ] T024 [US4] Implement `Transactions#update(id, changes, actor: nil)`

---

## Phase 7: User Story 5 — Capture and cancel (P3)

- [ ] T025 [P] [US5] Write capture unit + contract specs (failing): `POST …/{id}/capture` with `id` and `amount`; `amount` a positive Integer; **capture is never auto-retried**; audit emitted
- [ ] T026 [P] [US5] Write cancel unit + contract specs (failing): `POST …/{id}/cancel`, no body; audit emitted
- [ ] T027 [US5] Implement `Transactions#capture(id, amount:, actor: nil)` and `#cancel(id, actor: nil)`
- [ ] T028 [US5] **Resolve `[UNVERIFIED]` #4**: what the body `id` on capture refers to

---

## Phase 8: Polish & Verification

- [ ] T029 **Run the `msgowl/website` test suite against this gem via a local path override and confirm zero changes are needed** (SC-005). This is the release gate for the whole feature
- [ ] T030 Close the verification table in `contracts/bml-remote.md`; resolve or re-scope all six `[UNVERIFIED]` items
- [ ] T031 [P] Update the gem `README.md`: v2 create, tokenization, and a clear deprecation notice on v1 `create`
- [ ] T032 [P] Add a `CHANGELOG.md` entry under `[Unreleased]`
- [ ] T033 [P] Run `bundle exec rubocop`
- [ ] T035 **Fix a pre-existing Ruby 2.7 bug** in `lib/bml_connect/models/transaction.rb:17`: `REQUIRED_FIELDS.join(', ')` → `REQUIRED_FIELDS.to_a.join(', ')`. `Set#join` requires Ruby 3.0 while the gemspec declares `>= 2.3.0`, so a create missing `amount` or `currency` currently raises `NoMethodError` instead of `ArgumentError` on Ruby 2.7 (research R11). This makes `spec/transaction_spec.rb:4` pass — it asserts the intended behavior today and fails
- [ ] T034 Verify no new code sends `Bearer`, `X-App-Id`, or a `signature` on v2, and that no log line or audit record can contain a payment URL (`grep -rn` plus the T008 assertions)

---

## Dependencies

```
Phase 1 COMPAT PIN (T001-T002)   ← must be green before anything else
   └─> feature 001 Foundational  ← hard prerequisite
         └─> Foundational (T003-T007)
               ├─> US1 (T008-T013)  P1  MVP
               │     └─> US2 (T014-T018)  P1  ← the point of the migration
               ├─> US3 (T019-T022)  P1     ← T021 unblocks production
               ├─> US4 (T023-T024)  P3
               └─> US5 (T025-T028)  P3
                     └─> Polish (T029-T034)
```

## Release gates

Neither is optional:

1. **T029** — `msgowl/website` passes unchanged.
2. **T021** — the v2 payment-URL field is confirmed. Until then `create_v2` may be merged but
   MUST NOT be adopted in production.
