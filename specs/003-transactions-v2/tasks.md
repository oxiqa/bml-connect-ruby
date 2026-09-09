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

- [X] T001 Write `spec/contract/transactions_v1_compat_spec.rb` (must pass **immediately**, against unmodified code): asserts `create` posts to `#{client.base_url}transactions` with `signature`, `apiVersion`, `appVersion`, `signMethod`; that `create`, `get` and `list` each return a `Faraday::Response`; and that `resp.body` is symbol-keyed
- [X] T002 Add a `msgowl/website`-shaped smoke spec asserting the six response fields the website reads (`:id`, `:url`, `:state`, `:expires`, `:merchantId`, `:paddedCardNumber`) are reachable off a stubbed v1 response

**Checkpoint**: T001 and T002 green on unmodified code. They must stay green through every later task.

---

## Phase 2: Foundational

- [X] T003 [P] Create `lib/bml_connect/models/transaction_record.rb` — whitelisted v2 response object per data-model.md, with `#payment_url` (raises `UnverifiedFieldError` when no candidate field is present) and `#tokenized?`. **Do not touch `models/transaction.rb`**
- [X] T004 [P] Create `lib/bml_connect/models/tokenization_details.rb` — input validation for the four fields and their conditional rules
- [X] T005 Add `UnverifiedFieldError` to `lib/bml_connect/errors.rb`
- [X] T006 Extend `spec/contract/openapi_conformance_spec.rb` for this feature's paths, with the legacy `POST /public/transactions` **explicitly allow-listed as a documented exception**, carrying a comment pointing at `contracts/bml-remote.md`
- [X] T007 Require the new files from `lib/bml_connect.rb`

---

## Phase 3: User Story 1 — Create on v2 (P1) 🎯 MVP

- [X] T008 [P] [US1] Write `spec/unit/transactions_v2_spec.rb` (failing): `amount` must be a positive Integer — **Float and String rejected, never coerced**; `currency` required; variants 1/2/5 rejected by name; `customerId` and inline `customer` mutually exclusive; PAN screening; audit emitted; **payment URL absent from `#to_h`, `#inspect`, the log line, and the audit record**
- [X] T009 [P] [US1] Write `spec/contract/transactions_v2_remote_spec.rb` (failing): `POST #{client.base_url}public/v2/transactions`, raw `Authorization`, no `Bearer`, no `X-App-Id`, **no `signature` field**; maps 201 → `TransactionRecord`; error mapping
- [X] T010 [P] [US1] Write a failing spec asserting **create is never auto-retried** (SC-007): simulate a timeout, assert exactly one HTTP attempt was made
- [X] T011 [US1] Implement `Transactions#create_v2(details, actor: nil)`
- [X] T012 [US1] Add a **single structured deprecation warning, deduplicated to at most once per process** (FR-011), to the existing `create`, naming `create_v2`. **Behavior, return value, and request otherwise unchanged** — T001 and the `msgowl/website` gate (T029) must stay green. Include a spec asserting the warning fires once and does not fire on a second call
- [X] T013 [P] [US1] Write `spec/integration/transactions_v2_uat_spec.rb` (opt-in, gated)

**Checkpoint**: v2 create works; v1 untouched.

---

## Phase 4: User Story 2 — Tokenization (P1)

- [X] T014 [P] [US2] Write `spec/unit/tokenization_details_spec.rb` (failing), one example per rule: `tokenize` required; `paymentType` required and in `RECURRING`/`UNSCHEDULED`; `recurringFrequency` required and in the documented set when `RECURRING`; `expiryDate` required when `RECURRING`; `expiryDate` must be `yyyy-mm-dd`; `expiryDate` must be in the future. **Every one asserts no remote call was made**
- [X] T015 [P] [US2] Write contract specs (failing): `tokenizationDetails` serialized exactly as the four documented keys, nested, with no extra fields
- [X] T016 [US2] Wire `tokenizationDetails` into `create_v2`
- [ ] T017 [US2] **Manual UAT verification (SC-002)** — cannot be automated: create a tokenizing transaction, complete it in a browser with a UAT test card, then confirm a token appears via `client.tokens.list(customer_id)`. Record the outcome in `contracts/bml-remote.md`
- [ ] T018 [US2] **Resolve `[UNVERIFIED]` #5**: whether `tokenizationDetails` works without a `customerId`

**Checkpoint**: the migration's core capability is proven end-to-end.

---

## Phase 5: User Story 3 — Retrieve (P1)

- [X] T019 [P] [US3] Write retrieve unit + contract specs (failing): `GET …public/transactions/{id}`; **`state` passed through verbatim, never normalized** (research R8); whitelisting; 404 → `NotFoundError`
- [X] T020 [US3] Implement `Transactions#retrieve(id, actor: nil)` alongside the untouched `get`
- [ ] T021 [US3] **Resolve `[UNVERIFIED]` #1 — the payment-URL field.** Create one v2 transaction on UAT, dump the raw response, record which field carries the hosted URL. **BLOCKS production use of `create_v2`**
- [ ] T022 [US3] **Resolve `[UNVERIFIED]` #2, #3, #6**: whether v2 accepts a `signature`; the `state` values v2 returns; whether a v2-created transaction is retrievable at the v1 retrieve path

---

## Phase 6: User Story 4 — Update (P3)

- [X] T023 [P] [US4] Write update unit + contract specs (failing): `PATCH …public/transactions/{id}`; only `customerReference`, `localData`, `pnr` accepted; **only supplied keys sent, no nulls**; empty changes rejected; **audit record emitted** (FR-017)
- [X] T024 [US4] Implement `Transactions#update(id, changes, actor: nil)`, returning a `TransactionRecord` value object (FR-019) and emitting an audit record (FR-017)

---

## Phase 7: User Story 5 — Capture and cancel (P3)

- [X] T025 [P] [US5] Write capture unit + contract specs (failing): `POST …/{id}/capture` with `id` and `amount`; `amount` validated under the **same rule as `create_v2` (FR-008/FR-005)** — positive Integer in minor units, **Float, String, zero, and negative each rejected by name with no remote call**; **capture is never auto-retried**; audit emitted
- [X] T026 [P] [US5] Write cancel unit + contract specs (failing): `POST …/{id}/cancel`, no body; audit emitted
- [X] T027 [US5] Implement `Transactions#capture(id, amount:, actor: nil)` and `#cancel(id, actor: nil)`, both returning a `TransactionRecord` value object (FR-019). Reuse the `create_v2` amount validator for capture (FR-008)
- [ ] T028 [US5] **Resolve `[UNVERIFIED]` #4**: what the body `id` on capture refers to

---

## Phase 8: Polish & Verification

- [ ] T029 **Run the `msgowl/website` test suite against this gem via a local path override and confirm zero changes are needed** (SC-005). This is the release gate for the whole feature
- [ ] T030 Close the verification table in `contracts/bml-remote.md`: (a) demonstrate **every operation** — create_v2, retrieve, update, capture, cancel — against UAT and record the observed response, satisfying FR-018 and SC-004 (not only the create/tokenization paths of T013/T017); (b) resolve or re-scope all six `[UNVERIFIED]` items
- [X] T031 [P] Update the gem `README.md`: v2 create, tokenization, and a clear deprecation notice on v1 `create`
- [X] T032 [P] Add a `CHANGELOG.md` entry under `[Unreleased]`
- [X] T033 [P] Run `bundle exec rubocop`
- [X] T035 **Fix a pre-existing Ruby 2.7 bug** in `lib/bml_connect/models/transaction.rb:17`: `REQUIRED_FIELDS.join(', ')` → `REQUIRED_FIELDS.to_a.join(', ')`. `Set#join` requires Ruby 3.0 while the gemspec declares `>= 2.3.0`, so a create missing `amount` or `currency` currently raises `NoMethodError` instead of `ArgumentError` on Ruby 2.7 (research R11). This makes `spec/transaction_spec.rb:4` pass — it asserts the intended behavior today and fails
- [X] T034 Verify no new code sends `Bearer`, `X-App-Id`, or a `signature` on v2, and that no log line or audit record can contain a payment URL (`grep -rn` plus the T008 assertions)

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

## Implementation status (2026-09-09)

All code, unit, contract and conformance work is **complete** (T001–T016, T019–T020, T023–T027,
T031–T035) — full suite green (208 examples, 0 failures, 12 pending). The 7 unchecked tasks are the
ones that cannot be closed without a working UAT credential or the downstream repo:

- **T017, T018, T021, T022, T028, T030** — require live UAT observation. The available UAT key is
  rejected with `PP-C-004`, and SC-002 (tokenization end-to-end) needs a human to complete a hosted
  payment in a browser. The v2 integration spec (`spec/integration/transactions_v2_uat_spec.rb`) is
  written and skips cleanly until `BML_RUN_UAT=1` with a valid key; running it resolves T021/T030.
- **T029** — `msgowl/website` compatibility gate; needs the website repo checked out against this
  gem via a local path override. The compat pin (T001/T002) stands in as the automated proxy and is
  green.

`create_v2` is therefore **merge-ready but not production-ready**: `payment_url` raises
`UnverifiedFieldError` until T021 confirms the field.
