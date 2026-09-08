---
description: "Task list for Stored Card Tokens implementation"
---

# Tasks: Stored Card Tokens

**Input**: Design documents from `/specs/002-stored-card-tokens/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, **and feature
`001-customers-endpoints` Foundational phase (T004–T012) complete** — this feature depends on the
shared `Resource`, errors, masking, and audit infrastructure introduced there.

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

- [ ] T001 Create the `lib/bml_connect/tokens.rb` skeleton: `PATH = "/public-customers/%<customer_id>s/tokens"`, `initialize(client)`, private validation helpers. No operations yet
- [ ] T002 [P] Create `lib/bml_connect/models/token.rb` — whitelisted value object per data-model.md, with `#deleted?` and `#recurring?`
- [ ] T003 [P] Create `lib/bml_connect/models/token_list.rb` — `Enumerable`, `#active`, and a **defensive parser accepting either a bare array or a `{count, items}` envelope** (research R4)
- [ ] T004 Extend `lib/bml_connect/client.rb` with a memoized `#tokens`
- [ ] T005 Require the new files from `lib/bml_connect.rb`
- [ ] T006 Extend `spec/contract/openapi_conformance_spec.rb` to cover this feature's three path templates against `reference/Connect-API.json`

**Checkpoint**: conformance test green; foundation ready.

---

## Phase 2: User Story 1 — List a customer's stored cards (P1) 🎯 MVP

**Goal**: Turn a `customerId` into usable `tokenId`s.

**Independent Test**: List a customer with a stored card; confirm the token appears masked.

- [ ] T007 [P] [US1] Write `spec/unit/tokens_list_spec.rb` (failing): blank `customer_id` rejected with no remote call; whitelisting drops unknown keys; **an empty array yields an empty list, while a 401 raises `AuthenticationError` and is never converted to an empty list** (research R6); both envelope shapes parse
- [ ] T008 [P] [US1] Write `spec/contract/tokens_remote_spec.rb` (failing): `GET #{client.base_url}public-customers/{customerId}/tokens`, raw `Authorization` header, **no `Bearer`, no `X-App-Id`, no request body, no query parameters**; error mapping
- [ ] T009 [US1] Implement `Tokens#list(customer_id)` in `lib/bml_connect/tokens.rb` — not audited (read)
- [ ] T010 [P] [US1] Write `spec/integration/tokens_uat_spec.rb` (opt-in, gated on `BML_API_KEY` + `BML_CUSTOMER_ID`): list end-to-end, assert no full PAN in the serialized response, assert `base_url` contains `uat`
- [ ] T011 [US1] **Resolve `[UNVERIFIED]` #1 and #2**: record the observed list envelope shape and settle the `requestBody`-vs-response anomaly in `contracts/bml-remote.md`

**Checkpoint**: US1 independently shippable — feature `004` is unblocked for design.

---

## Phase 3: User Story 2 — Retrieve one stored card (P2)

- [ ] T012 [P] [US2] Write retrieve unit specs (failing): blank `token_id` rejected; whitelisting; `#deleted?`
- [ ] T013 [P] [US2] Write retrieve contract specs (failing): `GET …/tokens/{tokenId}`; 404 → `NotFoundError`
- [ ] T014 [US2] Implement `Tokens#retrieve(customer_id, token_id)` — not audited (read)
- [ ] T015 [P] [US2] **SECURITY — mandatory**: add a UAT test retrieving a valid `tokenId` under a *different* `customerId` and asserting it is NOT returned (research R5). If it IS returned, stop, do not ship, and report to BML
- [ ] T016 [US2] **Resolve `[UNVERIFIED]` #3 and #4**: not-found status/body, and the cross-customer result

---

## Phase 4: User Story 3 — Delete a stored card (P2)

- [ ] T017 [P] [US3] Write delete unit specs (failing): `204` → `true`; audit record emitted; blank-id validation; actor PAN screening
- [ ] T018 [P] [US3] Write delete contract specs (failing): `DELETE …/tokens/{tokenId}`; `400` → `ValidationError`
- [ ] T019 [US3] Implement `Tokens#delete(customer_id, token_id, actor: nil)`
- [ ] T020 [P] [US3] Add delete to the UAT suite; afterwards list again and record whether the token still appears with `deleted: true` or disappears
- [ ] T021 [US3] **Resolve `[UNVERIFIED]` #5 and #6**: deleted-token visibility in list, and the effect on an outstanding `tokenAgreementId`

---

## Phase 5: Polish & Verification

- [ ] T022 **Enforce the absence of a create path** (SC-006): a unit test asserting `BMLConnect::Tokens.public_instance_methods(false).sort == %i[delete list retrieve]`, so no future contributor can reintroduce a fictional `tokenize`
- [ ] T023 **Resolve `[UNVERIFIED]` #7** (pagination) and **close the verification table** in `contracts/bml-remote.md`
- [ ] T024 [P] Update the gem `README.md` with a Stored Cards section, stating plainly that tokens are created via feature `003`, not here
- [ ] T025 [P] Add a `CHANGELOG.md` entry under `[Unreleased]`
- [ ] T026 [P] Run `bundle exec rubocop` and resolve offenses in new files
- [ ] T027 Verify no file references `card_handle`, `cards-on-file`, `CardOnFile`, `detokenize`, `last_four`, or a top-level `/tokens` path (`grep -rn` over `lib/` and `spec/`)

---

## Dependencies

```
feature 001 Foundational (T004-T012)   ← HARD PREREQUISITE
   └─> Foundational (T001-T006)
         ├─> US1 (T007-T011)  P1  MVP
         ├─> US2 (T012-T016)  P2   includes the mandatory security test
         └─> US3 (T017-T021)  P2
               └─> Polish (T022-T027)
```

## Blocking note for feature 004

`004-token-charge` MUST NOT ship until T011 and T016 confirm **which identifier `tokenId`
refers to** (`Token#id` vs `Token#token` — research R3). Charging the wrong one is a
money-movement bug.
