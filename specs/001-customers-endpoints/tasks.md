---
description: "Task list for Customers Endpoints implementation"
---

# Tasks: Customers Endpoints

**Input**: Design documents from `/specs/001-customers-endpoints/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: INCLUDED — Constitution Principle II (Test-First) is NON-NEGOTIABLE. Every story
writes tests first; they MUST fail before implementation.

**Organization**: Tasks are grouped by user story (from spec.md) for independent implementation
and testing.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: US1–US5 (user-story tasks only)
- Paths follow the gem layout in plan.md (`lib/bml_connect/`, `spec/`)

## Path Conventions

Existing single-project Ruby gem: source in `lib/bml_connect/`, specs in `spec/` at repository
root. This feature is **additive** — no existing file's behavior changes except `client.rb`,
which gains one memoized accessor.

**Shared-file note**: all five operations live in `lib/bml_connect/customers.rb`. Its skeleton is
created in Foundational (T009); each story then adds its own method, so implementation edits to
that file are sequential (not `[P]`). Spec files are per-operation and ARE parallelizable.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Prepare the existing gem's test tooling for the new resources.

- [X] T001 Add `webmock ~> 3.14` as a development dependency in `bml_connect.gemspec`; run `bundle install` and commit the updated `Gemfile.lock`
- [X] T002 Create the `spec/unit/`, `spec/contract/`, and `spec/integration/` directories, and update `spec/spec_helper.rb` to `require "webmock/rspec"` and `WebMock.disable_net_connect!(allow_localhost: false)`
- [X] T003 [P] Add a committed secret-scanning config at the repo root (Constitution: secrets scanning MUST run before merge)

**Checkpoint**: `bundle exec rspec` still passes the four existing specs; `bundle exec rubocop` is clean.

> Existing specs (`spec/client_spec.rb`, `spec/transaction_spec.rb`, `spec/transactions_spec.rb`,
> `spec/bml_connect_spec.rb`) stay where they are. Do not move them in this feature.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Shared infrastructure every later feature (002, 003, 004) also depends on. Ported
from `bml_tokenization`, whose transport/masking/audit engineering was sound even though its API
shape was not.

- [X] T004 Write `spec/contract/openapi_conformance_spec.rb` FIRST (failing): parse `reference/Connect-API.json` and assert (a) every path constant the library defines is a key in `paths`, (b) the client's auth header name matches `components.securitySchemes.Authorization.name`, and (c) the client's `mode`→base-URL mapping matches `servers[]`. **This test is the enforcement mechanism for Constitution II's anti-stub gate.**
- [X] T005 Create `lib/bml_connect/errors.rb`: `Error` (existing, keep) plus `ValidationError` (with `#field`), `AuthenticationError`, `NotFoundError`, `ConflictError` (with `#body`), `RateLimitError` (with `#retry_after`), `AvailabilityError`
- [X] T006 [P] Create `lib/bml_connect/masking.rb`: `PAN_PATTERN` and `Masking.scrub` for structured log entries (port from `bml_tokenization/lib/bml_tokenization/masking.rb`)
- [X] T007 [P] Create `lib/bml_connect/audit.rb`: `Audit.emit_event(client, action:, actor:, outcome:, subject:)` that formats the who/what/when/outcome record and emits it as a **structured, masked log line through `client.logger`** (masked via T006's `Masking.scrub`). **No `audit_sink` object** — auditing rides the existing logging path (research R12, spec clarification 2026-09-08). Port the record shape from `bml_tokenization`, but write to the logger, not a sink
- [X] T008 Create `lib/bml_connect/resource.rb`: shared base for the new value-object resources — request dispatch over the client's Faraday connection, status→error mapping per `contracts/bml-remote.md`, bounded retry with backoff, `Retry-After` on 429. **Every WebMock stub written against this MUST interpolate `client.base_url`** (research R10)
- [X] T009 Create the `lib/bml_connect/customers.rb` skeleton (`PATH = "/public-customers"`, `initialize(client)`, private helpers) with no operations yet
- [X] T010 Extend `lib/bml_connect/client.rb`: add memoized `#customers`, plus `#logger` (defaulting to a safe masked logger — this is the audit/log sink per R12), `#timeout`, `#max_retries`, `#retry_backoff` accessors with safe defaults. **No `#audit_sink` accessor** — audit records go through `#logger`. **Do not change any existing method's behavior or signature**
- [X] T011 [P] Create `lib/bml_connect/models/customer.rb` and `models/customer_list.rb` as whitelisted value objects per data-model.md
- [X] T012 Require the new files from `lib/bml_connect.rb`

**Checkpoint**: T004 passes. Foundation ready — user stories can now proceed independently.

---

## Phase 3: User Story 1 — Create a customer (P1) 🎯 MVP

**Goal**: An integrator can register a payer and receive a BML-assigned `id`.

**Independent Test**: Create against UAT with only `name` and `email`; confirm a non-empty `id`.

- [X] T013 [P] [US1] Write `spec/unit/customers_create_spec.rb` (failing): required-field validation for `name`/`email` with no remote call made; **email shape check** — a value lacking an `@` or a domain part (e.g. `"aisha"`) raises `ValidationError(field: :email)`, and `billingEmail` gets the same check when supplied, while a valid address passes and strict-RFC edge cases are NOT rejected (research R11); PAN/CVV screening rejects card-like values in **any** caller-supplied string field; actor PAN screening; audit record emitted as a **masked structured log line via `client.logger`** (assert on the logged line; there is no sink)
- [X] T014 [P] [US1] Write `spec/contract/customers_remote_spec.rb` (failing): asserts `POST` to `#{client.base_url}public-customers` with the raw `Authorization` header, **no** `Bearer` prefix and **no** `X-App-Id`; body carries exactly the supplied documented fields; maps 201 → `Customer`, and 400/401/404/409/429/5xx → the mapped errors
- [X] T015 [US1] Implement `Customers#create(details, actor: nil)` in `lib/bml_connect/customers.rb`
- [X] T016 [P] [US1] Write `spec/integration/customers_uat_spec.rb` (opt-in, credential-gated, skips without `BML_API_KEY`): create end-to-end and assert environment isolation (`base_url` contains `uat`)

**Checkpoint**: US1 is independently shippable — `client.customers.create` works end-to-end.

---

## Phase 4: User Story 2 — Retrieve a customer (P1)

**Goal**: Look up a customer by id.

- [X] T017 [P] [US2] Write retrieve unit specs (failing): blank-id validation, whitelisting drops unknown/sensitive keys, archived customer returns with `deleted?` true
- [X] T018 [P] [US2] Write retrieve contract specs (failing): `GET #{base_url}public-customers/{id}`; 404 → `NotFoundError`
- [X] T019 [US2] Implement `Customers#retrieve(customer_id, actor: nil)` — not audited (read)
- [X] T020 [P] [US2] Add the create→retrieve round-trip to the UAT suite

**Checkpoint**: US1 + US2 both work independently.

---

## Phase 5: User Story 3 — List customers (P2)

**Goal**: Enumerate customers under the company.

- [X] T021 [P] [US3] Write list unit specs (failing): `count` coerces from a string, falls back to `items.size` on a non-numeric value, empty result yields an empty list not an error, `Enumerable` behavior
- [X] T022 [P] [US3] Write list contract specs (failing): `GET #{base_url}public-customers` sends **no** query parameters (research R4); envelope maps to `CustomerList`
- [X] T023 [US3] Implement `Customers#list(actor: nil)` — not audited (read)
- [X] T024 [P] [US3] Add list + empty-result coverage to the UAT suite

**Checkpoint**: Read paths complete.

---

## Phase 6: User Story 4 — Update a customer (P2)

**Goal**: Partially update a customer without erasing unsupplied fields.

- [X] T025 [P] [US4] Write update unit specs (failing): **body contains only supplied keys and no nulls** (research R3), empty `changes` raises `ValidationError` with no remote call, **email/`billingEmail` shape check applied when either is among the supplied changes** (research R11), PAN screening across all supplied string values, audit emitted as a masked log line via `client.logger`
- [X] T026 [P] [US4] Write update contract specs (failing): asserts **`PATCH`** (not `PUT`) to `#{base_url}public-customers/{id}`; 404 → `NotFoundError`
- [X] T027 [US4] Implement `Customers#update(customer_id, changes, actor: nil)`
- [X] T028 [P] [US4] Add a UAT test asserting a single-field update leaves every other field unchanged (retrieve before and after)

**Checkpoint**: Mutation path complete.

---

## Phase 7: User Story 5 — Archive a customer (P3)

**Goal**: Retire a customer record.

- [X] T029 [P] [US5] Write archive unit specs (failing): `204` → `true`, audit emitted as a masked log line via `client.logger`, blank-id validation
- [X] T030 [P] [US5] Write archive contract specs (failing): `DELETE #{base_url}public-customers/{id}`; `204` has no body; `400` → `ValidationError`
- [X] T031 [US5] Implement `Customers#archive(customer_id, actor: nil)`
- [X] T032 [P] [US5] Add archive to the UAT suite and record what happens to the customer's tokens — this resolves an `[UNVERIFIED]` marker in `contracts/bml-remote.md`

**Checkpoint**: All five operations complete.

---

## Phase 8: Polish & Verification

- [X] T033 Run the UAT suite with a working key and **close the verification table** in `contracts/bml-remote.md`: replace every `☐ pending credentials` with an observed status, and resolve or re-scope each `[UNVERIFIED]` marker
- [X] T034 [P] Update the gem `README.md` with a Customers section
- [X] T035 [P] Add a `CHANGELOG.md` entry under `[Unreleased]`
- [X] T036 [P] Run `bundle exec rubocop` and resolve offenses in new files
- [X] T037 Verify no new file references `first_name`, `last_name`, `card_handle`, `cards-on-file`, `Bearer`, `X-App-Id`, or `audit_sink` — the retired gem's vocabulary and the superseded audit-sink design must not leak in (`grep -rn` over `lib/` and `spec/`)

---

## Dependencies

```
Setup (T001-T003)
   └─> Foundational (T004-T012)   ← BLOCKS everything below
         ├─> US1 (T013-T016)  P1  MVP
         ├─> US2 (T017-T020)  P1
         ├─> US3 (T021-T024)  P2
         ├─> US4 (T025-T028)  P2
         └─> US5 (T029-T032)  P3
               └─> Polish (T033-T037)
```

User stories are independent of each other once Foundational is done. Implementation tasks
(T015, T019, T023, T027, T031) all edit `customers.rb` and are therefore sequential; every test
task is `[P]`.

## Parallel Execution Example

After Foundational completes, all five stories' **test** tasks can be written concurrently:

```
T013, T014, T016   (US1)
T017, T018, T020   (US2)
T021, T022, T024   (US3)
T025, T026, T028   (US4)
T029, T030, T032   (US5)
```

Then implement T015 → T019 → T023 → T027 → T031 in sequence.

## Implementation Strategy

**MVP scope**: Setup + Foundational + US1. That alone unblocks feature `002`, which needs only a
customer id. Ship it before starting US2–US5 if you want the tokens work to begin in parallel.
