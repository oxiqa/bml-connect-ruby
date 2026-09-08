---
description: "Task list for Stored Card Tokens implementation"
---

# Tasks: Stored Card Tokens

**Input**: Design documents from `/specs/002-stored-card-tokens/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, **and feature
`001-customers-endpoints` Foundational phase (T004–T012) complete** — this feature depends on the
shared `Resource`, errors, masking, and audit infrastructure introduced there. Retry/backoff
(FR-013a) is added to that same shared transport (research R9).

**Tests**: INCLUDED — Constitution Principle II is NON-NEGOTIABLE. Tests precede implementation.

**Organization**: Grouped by user story for independent implementation and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1–US3

## Path Conventions

Source in `lib/bml_connect/`, specs in `spec/`. All three operations live in
`lib/bml_connect/tokens.rb`, so implementation tasks on it are sequential; test tasks are `[P]`.

---

## Phase 1: Foundational (Blocking Prerequisites)

- [X] T001 Create the `lib/bml_connect/tokens.rb` skeleton: `PATH = "/public-customers/%<customer_id>s/tokens"`, `initialize(client)`, private validation helpers. No operations yet
- [X] T002 [P] Create `lib/bml_connect/models/token.rb` — whitelisted value object per data-model.md, with `#deleted?` and `#recurring?`
- [X] T003 [P] Create `lib/bml_connect/models/token_list.rb` — `Enumerable`, `#active`, and a **defensive parser accepting either a bare array or a `{count, items}` envelope** (research R4)
- [X] T004 Extend `lib/bml_connect/client.rb` with a memoized `#tokens`. (Retry knobs `max_retries`/`retry_backoff` already exist on the client from feature `001` and are reused as-is — research R9; no new options added)
- [X] T005 Require the new files from `lib/bml_connect.rb` (and models from `lib/bml_connect/models.rb`)
- [X] T006 Extend `spec/contract/openapi_conformance_spec.rb` to cover this feature's two path templates against `reference/Connect-API.json`, tying `Tokens::PATH` to the documented template
- [X] T007 [P] Write `spec/unit/retry_spec.rb`: a transient failure (`429`, `408`, timeout, `5xx`) is retried with bounded backoff up to `max_retries` then raises the original distinguishable error (`RateLimitError` / `AvailabilityError`); non-transient errors (`AuthenticationError`, `NotFoundError`, `ConflictError`, local `ValidationError`) are **never** retried; `max_retries: 0` disables retry (research R9)
- [X] T008 Extend the shared transport (`lib/bml_connect/resource.rb`) to also retry `429` (it already retried `408`/timeouts/`5xx`), reusing the existing `retry_backoff` schedule; a surviving `429` is still surfaced as `RateLimitError` carrying `Retry-After`; make T007 green

**Checkpoint**: conformance test green; retry behavior green; foundation ready.

---

## Phase 2: User Story 1 — List a customer's stored cards (P1) 🎯 MVP

**Goal**: Turn a `customerId` into usable `tokenId`s.

**Independent Test**: List a customer with a stored card; confirm the token appears masked.

- [X] T009 [P] [US1] Write `spec/unit/tokens_list_spec.rb` (failing): blank `customer_id` rejected with no remote call; whitelisting drops unknown keys; **an empty array yields an empty list, while a 401 raises `AuthenticationError` and is never converted to an empty list** (research R6); both envelope shapes parse
- [X] T010 [P] [US1] Write `spec/contract/tokens_remote_spec.rb` (failing): `GET #{client.base_url}public-customers/{customerId}/tokens`, raw `Authorization` header, **no `Bearer`, no `X-App-Id`, no request body, no query parameters**; error mapping
- [X] T011 [US1] Implement `Tokens#list(customer_id)` in `lib/bml_connect/tokens.rb` — not audited (read); inherits shared-transport retry from T008
- [ ] T012 [P] [US1] Write `spec/integration/tokens_uat_spec.rb` (opt-in, gated on `BML_API_KEY` + `BML_CUSTOMER_ID`): list end-to-end, assert no full PAN in the serialized response, assert `base_url` contains `uat`
- [ ] T013 [US1] **Resolve `[UNVERIFIED]` #1 and #2**: record the observed list envelope shape and settle the `requestBody`-vs-response anomaly in `contracts/bml-remote.md`

**Checkpoint**: US1 independently shippable — feature `004` is unblocked for design.

---

## Phase 3: User Story 2 — Retrieve one stored card (P2)

- [X] T014 [P] [US2] Write retrieve unit specs (failing) in `spec/unit/tokens_retrieve_spec.rb`: blank `token_id` rejected; whitelisting; `#deleted?`
- [X] T015 [P] [US2] Write retrieve contract specs (failing) in `spec/contract/tokens_remote_spec.rb`: `GET …/tokens/{tokenId}`; 404 → `NotFoundError` (asserting it is not retried)
- [X] T016 [US2] Implement `Tokens#retrieve(customer_id, token_id)` — not audited (read)
- [ ] T017 [P] [US2] **SECURITY — mandatory**: add a UAT test in `spec/integration/tokens_uat_spec.rb` retrieving a valid `tokenId` under a *different* `customerId` and asserting it is NOT returned (research R5). If it IS returned, stop, do not ship, and report to BML
- [ ] T018 [US2] **Resolve `[UNVERIFIED]` #3 and #4**: not-found status/body, and the cross-customer result

---

## Phase 4: User Story 3 — Delete a stored card (P2)

- [X] T019 [P] [US3] Write delete unit specs (failing) in `spec/unit/tokens_delete_spec.rb`: `204` → `true`; audit record emitted; blank-id validation; actor PAN screening; **a retried delete (e.g. `429` then `204`) emits exactly ONE audit record capturing the final outcome, not one per attempt** (FR-013a × FR-014, research R9)
- [X] T020 [P] [US3] Write delete contract specs (failing) in `spec/contract/tokens_remote_spec.rb`: `DELETE …/tokens/{tokenId}`; `400` → `ValidationError` (not retried); **a transient `5xx`/timeout is retried then succeeds on `204`** (delete is idempotent, research R9)
- [X] T021 [US3] Implement `Tokens#delete(customer_id, token_id, actor: nil)` — audit written after the retry sequence settles, once
- [ ] T022 [P] [US3] Add delete to the UAT suite; afterwards list again and record whether the token still appears with `deleted: true` or disappears
- [ ] T023 [US3] **Resolve `[UNVERIFIED]` #5 and #6**: deleted-token visibility in list, and the effect on an outstanding `tokenAgreementId`

---

## Phase 5: Polish & Verification

- [X] T024 **Enforce the absence of a create path** (SC-006): a unit test in `spec/unit/tokens_spec.rb` asserting `BMLConnect::Tokens.public_instance_methods(false).sort == %i[delete list retrieve]`, so no future contributor can reintroduce a fictional `tokenize`
- [X] T025 **Environment isolation** (SC-004, FR-011): add a deterministic unit test asserting a `mode: "production"` client routes every token request to the production `base_url` and never a `uat` host, and vice versa; document that cross-environment *token visibility* itself is a UAT observation recorded in `contracts/bml-remote.md`
- [ ] T026 **Resolve `[UNVERIFIED]` #7** (pagination) and **close the verification table** in `contracts/bml-remote.md`
- [X] T027 [P] Update the gem `README.md` with a Stored Cards section, stating plainly that tokens are created via feature `003`, not here, and documenting the client retry options
- [X] T028 [P] Add a `CHANGELOG.md` entry under `[Unreleased]`
- [X] T029 [P] Run `bundle exec rubocop` and resolve offenses in new files
- [X] T030 Verify no file references `card_handle`, `cards-on-file`, `CardOnFile`, `detokenize`, `last_four`, or a top-level `/tokens` path (`grep -rn` over `lib/` and `spec/`)

---

## Dependencies

```
feature 001 Foundational (T004-T012)   ← HARD PREREQUISITE
   └─> Foundational (T001-T008)              incl. retry/backoff in shared transport
         ├─> US1 (T009-T013)  P1  MVP
         ├─> US2 (T014-T018)  P2   includes the mandatory security test
         └─> US3 (T019-T023)  P2   includes retry + single-audit-record assertions
               └─> Polish (T024-T030)
```

Within Foundational, T007 (failing retry spec) precedes T008 (retry implementation) per
Constitution II. T008 is a shared-transport change every operation inherits, so it blocks the
implementation tasks (T011, T016, T021) but not the per-story test-writing tasks.

## Parallel execution examples

- Foundational: T002, T003, and T007 are `[P]` — different files, no interdependency.
- Per story, the failing test tasks are `[P]` (e.g. T009 ∥ T010; T019 ∥ T020) but the single
  `tokens.rb` implementation task in each story is sequential.
- Polish: T027, T028, T029 are `[P]`.

## Implementation strategy

MVP is US1 (T001–T013): a caller can turn a `customerId` into usable `tokenId`s, with retry
resilience already in place from Foundational. US2 and US3 are independent P2 increments layered
on the same foundation. Ship US1 first to unblock feature `004`'s design.

## Blocking note for feature 004

`004-token-charge` MUST NOT ship until T013 and T018 confirm **which identifier `tokenId`
refers to** (`Token#id` vs `Token#token` — research R3). Charging the wrong one is a
money-movement bug.
