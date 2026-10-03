---
description: "Task list for Transaction Status Webhook Handler implementation"
---

# Tasks: Transaction Status Webhook Handler

**Input**: Design documents from `/specs/005-webhook-handler/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, **and feature `003`
(transactions v2) complete** — the verifying retrieve is this feature's load-bearing dependency.

**Tests**: INCLUDED — Constitution Principle II (Test-First) is NON-NEGOTIABLE.

**Organization**: Grouped by user story so each is independently implementable and testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1–US3 (maps to the user stories in spec.md)
- Every task names an exact file path.

## Path Conventions

One new resource, `BMLConnect::Webhooks`, reached as `client.webhooks` and memoized like
`#customers`/`#tokens`. It subclasses `Resource` for the shared validation/audit/masking helpers but
**issues no HTTP of its own** — the verifying retrieve is delegated to `client.transactions.retrieve`
(research R1). Production code in `lib/bml_connect/`; specs under `spec/`.

> 🔓 **The inbound surface is entirely `[UNVERIFIED]`.** The published contract documents the
> callback nowhere. Every task that reads a payload field reads a *guess*, and the design is built so
> a wrong guess fails loudly instead of reporting a false status. If a task seems to refuse a
> convenience — no state allow-list, no default secret location, no opt-out of verification — that
> refusal is the feature.

---

## Phase 1: Release Gate (Blocks release, NOT build)

**Purpose**: Observe one real delivery. Everything below may be built, merged and tested in parallel
with this; **nothing in this feature may be declared complete until it is done** (FR-019, SC-011).

- [ ] T001 ⛔ [US1] Observe a genuine UAT delivery following the procedure in `specs/005-webhook-handler/contracts/bml-remote.md` ("Observation procedure"), record the raw body/headers verbatim under "Observed delivery", and resolve `[UNVERIFIED]` #1 (identifier field), #2 (claimed-status field), #3 (body format), #4 (read-path lag), #5 (delivery metadata) — correcting the candidate lists in `lib/bml_connect/webhooks.rb` and leaving anything still unconfirmed marked `[UNVERIFIED]` (FR-002a, FR-003b, FR-018)

**Checkpoint**: identifier field confirmed → the release gate is cleared. Note #4's answer may also
retire the 3-second re-check default (see T038).

---

## Phase 2: Foundational (Blocking prerequisites for all stories)

**Purpose**: The retry fix, the advisory-status carrier, the configuration, and the resource
skeleton. No behavior yet.

**⚠️ CRITICAL**: No user-story work can begin until this phase is complete.

- [X] T002 [P] Write `spec/unit/transactions_retrieve_retries_spec.rb` (failing): `retrieve(id)` still retries on a timeout exactly as feature `003` released it (default preserved), while `retrieve(id, retries: false)` makes **exactly one** HTTP attempt and raises `AvailabilityError` immediately (research R3, FR-009)
- [X] T003 Add the additive `retries: true` keyword to `Transactions#retrieve` in `lib/bml_connect/transactions.rb`, forwarding it to `request`, and update its RDoc to say why the webhook path passes `false` — without it one notification during a BML wobble makes up to six HTTP calls and breaks SC-008d (research R3)
- [X] T004 [P] Write `spec/unit/webhooks_errors_spec.rb` (failing): `BMLConnect::Error#advisory_http_status` reads/writes and defaults to `nil` on every existing error class; `BMLConnect::WebhookRejectedError` exists, descends from `Error`, and is a distinct class from `ValidationError` (FR-016a, FR-016, research R11)
- [X] T005 Add `attr_accessor :advisory_http_status` to `BMLConnect::Error` and define `WebhookRejectedError < Error` in `lib/bml_connect/errors.rb`, with a comment recording why a new class was justified over a `field:` value on `ValidationError` (plan.md Constitution Check)
- [X] T006 [P] Write `spec/unit/webhooks_client_config_spec.rb` (failing): `client.webhooks` is memoized and returns the same object twice; `options: { webhook_secret:, webhook_recheck_delay: }` are accepted, readable, **and stripped from the hash before Faraday sees them** (Faraday rejects unknown keys); defaults are `nil` and `3` (FR-009a, FR-010b, SC-008m)
- [X] T007 Add `webhook_secret` and `webhook_recheck_delay` (default `DEFAULT_WEBHOOK_RECHECK_DELAY = 3`) to `BMLConnect::Client#initialize` in `lib/bml_connect/client.rb`, deleting both from `opts` alongside the existing `timeout`/`max_retries`/`retry_backoff` handling, and add the memoized `#webhooks` reader
- [X] T008 [P] Create `spec/support/webhooks_helpers.rb`: builders for a JSON delivery and an equivalent form-encoded one, a Rack-style `HTTP_*` header hash, a retrieve stub helper that counts HTTP calls off `client.base_url`, a capturing logger, and a wait spy so **no test ever sleeps for real** (research R8)
- [X] T009 Create `lib/bml_connect/webhooks.rb` (`class Webhooks` — **not** a `Resource` subclass; see research R2: there were no helpers to inherit and `Resource#handle(response)` would collide with the public `#handle(body:, ...)`) with `ID_CANDIDATES = %i[transactionId transaction_id id]`, `STATUS_CANDIDATES = %i[state status]`, both commented `[UNVERIFIED]` with their justification from research R6, and `#handle` raising `NotImplementedError`), require it from `lib/bml_connect.rb`, and create `lib/bml_connect/models/status_change_result.rb` as an empty class required from `lib/bml_connect/models.rb`

**Checkpoint**: the retrieve can be called without retry, errors can carry an advisory status, the
client is configurable, and `client.webhooks` exists.

---

## Phase 3: User Story 1 — React to a transaction reaching a final state (Priority: P1) 🎯 MVP

**Goal**: A merchant's application hands the library a delivery and gets back the authoritative
transaction record, without writing any parsing of its own.

**Independent Test**: Hand the library a representative notification body and headers and confirm it
returns an authoritative transaction record the application can act on, with no parsing code in the
caller.

### Tests for User Story 1 (write FIRST; ensure they FAIL before implementing) ⚠️

- [X] T010 [P] [US1] Write `spec/unit/webhooks_parsing_spec.rb` (failing): JSON selected by `Content-Type`, form-encoded selected by `application/x-www-form-urlencoded`, a `+json` suffix accepted; absent/unrecognized type falls back **JSON first then form** (a JSON body must NOT be mangled into one garbage form key — verified behavior, research R4); an empty, whitespace-only, invalid-UTF-8, unparseable, or non-Hash body (bare JSON array) raises `ValidationError(field: :body)` with **zero** HTTP calls; header lookup resolves `Content-Type`, `content_type`, `CONTENT_TYPE` and Rack's `HTTP_CONTENT_TYPE` (FR-003/003a, US1-2, US1-3, SC-008k/008l, research R5)
- [X] T011 [P] [US1] Write `spec/unit/webhooks_extraction_spec.rb` (failing): candidates resolve in order `transactionId`, `transaction_id`, `id`; a candidate holding a Hash/Array/number/blank is skipped as absent; none yielding a `String` raises `ValidationError(field: :transaction_id)` with **zero** HTTP calls; a supplied `extract_id:` is used and the built-in list is **not** consulted even when the payload contains `transactionId`; the extractor receives the parsed payload **and** the normalized headers; an extractor returning `nil` raises the same error with zero calls (FR-002/002b/002c, US1-4, SC-011a/011b/011c)
- [X] T012 [P] [US1] Write `spec/unit/status_change_result_spec.rb` (failing): readers `transaction_id`, `transaction`, `status`, `changed_at`, `claimed_status`, `disagreed?`, `rechecked?`, `advisory_http_status`; `status` delegates to `transaction.state` verbatim; `claimed_status` is `Masking.scrub`bed; `to_h`/`inspect` are whitelisted; value equality; **no `payload`, `body`, `headers`, or `raw` reader exists** (FR-004/004a, SC-008i)
- [X] T013 [P] [US1] Write `spec/unit/webhooks_verify_spec.rb` (failing): a handled delivery performs the retrieve and returns a `TransactionRecord`; the retrieve is issued with `retries: false` so a timeout produces **exactly one** HTTP attempt; a status appearing nowhere in this repository is returned verbatim; `NotFoundError` and `AvailabilityError` are distinguishable from each other and from a validation failure; `changed_at` comes from the record (FR-004, FR-005, FR-008, FR-009, US1-5, SC-003, SC-007, SC-008)
- [X] T014 [P] [US1] Write `spec/unit/webhooks_recheck_spec.rb` (failing): a disagreeing claimed status triggers **exactly two** retrieves and reports the second; `webhook_recheck_delay: 0` produces **exactly one** retrieve with no wait; a payload with no comparable status produces exactly one retrieve; a claim differing only in case or surrounding whitespace produces **no** re-check (research R7); a persistent disagreement returns a result with `disagreed?` true rather than raising; the two-retrieve cap holds across the malformed, forged, disagreeing and transport-failure cases; a negative or non-numeric configured delay raises `ValidationError` (FR-010–010d, US1-7, SC-008a/008b/008c/008d)
- [X] T015 [P] [US1] Write `spec/unit/webhooks_advisory_status_spec.rb` (failing): enumerate every outcome — accepted, malformed, unextractable, not-found, unreachable, rate-limited, credential-rejected — and assert each carries the advisory status from the `data-model.md` taxonomy; **`404` is never advised for any outcome**; transient (`503`) and permanent (`4xx`) are never confused; the accepted result carries `200` (FR-016a/016c/016d, US1-8, SC-008g/008h, research R10)
- [X] T016 [P] [US1] Write `spec/contract/webhooks_remote_spec.rb` (failing): the verifying retrieve hits `GET #{client.base_url}transactions/{id}` with the raw `Authorization` API key — **no `Bearer`, no `X-App-Id`** — with every stub URL interpolated from `client.base_url` and no hardcoded host, and extend `spec/contract/openapi_conformance_spec.rb` to assert `get-public-transactions-transactionId` exists in `reference/Connect-API.json` (FR-017, FR-018, Constitution II/III)

### Implementation for User Story 1

- [X] T017 [US1] Implement body parsing and header normalization in `lib/bml_connect/webhooks.rb`: normalize header keys once (`downcase`, `_`→`-`, strip leading `http-`), select the parser by media type, fall back JSON-then-form, and reject empty/invalid-UTF-8/unparseable/non-Hash bodies as `ValidationError(field: :body)` before any remote call — using stdlib `json` and `uri` only, **no new dependency** (FR-003/003a, FR-003c: no size or nesting limit, research R4/R5)
- [X] T018 [US1] Implement identifier and claimed-status extraction in `lib/bml_connect/webhooks.rb`: the ordered candidate lists (top-level keys, non-blank `String` only), the `extract_id:` override that suppresses the built-in list entirely, and the raise-rather-than-guess failure — each candidate commented with its justification from research R6, including why `localId` is excluded (FR-002/002a/002b/002c, FR-010c)
- [X] T019 [P] [US1] Implement `BMLConnect::Models::StatusChangeResult` in `lib/bml_connect/models/status_change_result.rb` following `TransactionRecord`'s conventions (whitelisted `to_h`/`inspect`, value equality), scrubbing `claimed_status` on construction and exposing **no** payload-shaped reader (FR-004/004a, data-model §2)
- [X] T020 [US1] Implement `Webhooks#handle(body:, headers: {}, presented_secret: nil, extract_id: nil, actor: nil)` in `lib/bml_connect/webhooks.rb`: parse → extract → `client.transactions.retrieve(id, retries: false)` → build the result, with RDoc stating that the reported status always comes from the retrieve and that there is no option to skip it (FR-001, FR-006, FR-009)
- [X] T021 [US1] Implement the re-check in `lib/bml_connect/webhooks.rb`: compare claimed vs authoritative with `strip.upcase` **for the comparison only**, and when they disagree and the delay is greater than zero, wait once through a single private injectable method and retrieve once more — at most one re-check, no loop, no third call, reporting whatever the second retrieve says; validate the configured delay rather than coercing it (FR-010–010d, research R7/R8)
- [X] T022 [US1] Implement the advisory-status mapping in `lib/bml_connect/webhooks.rb` per the `data-model.md` §5 taxonomy, tagging each error object's `advisory_http_status` before it propagates, and document in the method's RDoc why a not-found transaction advises `422` rather than `404` and why a rejected credential advises transient (FR-016a–016d, research R10)

- [X] T022a [P] [US1] Write `spec/unit/webhooks_idempotence_spec.rb` (failing): two handlings of the same delivery against an unchanged authoritative record produce **equal** results with one retrieve each and no carried-over state; when the record changed in between, the second handling reports the **new** status (no caching); a duplicate delivery is handled again rather than short-circuited, and no deduplication surface exists for a caller to mistake for one (FR-013, FR-014, FR-014a, SC-006, SC-006a)

**Checkpoint**: a genuine delivery is handled end-to-end and returns an authoritative record (MVP).

---

## Phase 4: User Story 2 — Refuse to act on an unauthenticated payload (Priority: P1)

**Goal**: A forged "payment confirmed" posted to a public endpoint cannot cause goods to ship, and no
configuration exists that would let it.

**Independent Test**: Hand the library a well-formed forgery claiming a transaction is paid while BML
reports it unpaid, and confirm the library reports unpaid.

### Tests for User Story 2 (write FIRST; ensure they FAIL before implementing) ⚠️

- [X] T023 [P] [US2] Write `spec/unit/webhooks_forgery_spec.rb` (failing): a payload claiming `PAID` while BML reports unpaid reports **unpaid**; no result is ever produced without a retrieve having occurred; a failed retrieve raises and the library does **not** degrade to the payload's claims; a forged id that does not exist raises `NotFoundError`, distinguishable from a transport failure (FR-006, FR-008, US2-1/2/3/4, SC-002, SC-003)
- [X] T024 [P] [US2] Write `spec/unit/webhooks_surface_spec.rb` (failing): `handle` accepts no verification-skipping keyword — `handle(body:, verify: false)` raises `ArgumentError` for an unknown keyword — and neither `Webhooks` nor `StatusChangeResult` exposes any public method returning the raw body, the parsed payload, or a payload-shaped object; assert against the actual public method list, not a hand-written allow-list (FR-004a, FR-007, SC-004, SC-008i)
- [X] T025 [P] [US2] Write `spec/unit/webhooks_secret_spec.rb` (failing): with a secret configured, an absent or wrong presented value raises `WebhookRejectedError` with **zero** HTTP calls; a matching value still performs the verifying retrieve; the same genuine notification reports an identical status with and without a secret configured; the correct secret present in the delivery's **headers** but not presented by the caller is still rejected (the library reads no location of its own); neither secret value appears in the error message; comparison is constant-time over SHA-256 digests (FR-009a/009b/009d/009e, FR-012, US2-6/7, SC-008e/008f/008j)
- [X] T026 [P] [US2] Write `spec/unit/webhooks_pan_screening_spec.rb` (failing): a payload containing a Luhn-valid card number is **still handled normally** — one retrieve, an authoritative status returned (FR-011a, SC-005a) — **and** that number appears in no log line, audit record, error message, or result, across the accepted, rejected and malformed paths. A card-like `actor` is caller-supplied and still raises (FR-011, SC-005)

### Implementation for User Story 2

- [X] T027 [US2] Implement the secret gate in `lib/bml_connect/webhooks.rb`, running **before** any retrieve: reject a blank/absent presented value immediately, otherwise compare `Digest::SHA256.digest` of both values with a fixed-length XOR-accumulate loop — `OpenSSL.fixed_length_secure_compare` is **unavailable on this toolchain** (verified on Ruby 2.7.4), so stdlib `digest` is the implementation (FR-009a/009d, research R9)
- [X] T028 [US2] Document in the `Webhooks` class RDoc that the secret gates **spend, not trust** — a match never causes the payload to be believed, never skips the retrieve, and never weakens FR-006–FR-008 — and that the library refuses to infer where the secret travels, with no default header, query parameter, or path segment (FR-009b/009c/009e)
- [X] T029 [US2] Apply the existing `Masking`/PAN screen to inbound values on every path that logs, audits, or raises in `lib/bml_connect/webhooks.rb`, so no card-like data reaches output regardless of outcome (FR-011)

**Checkpoint**: a forgery cannot produce a false status, and no opt-out exists to be found later.

---

## Phase 5: User Story 3 — Diagnose a notification that did not arrive or was not accepted (Priority: P2)

**Goal**: An operator can tell apart a notification that never arrived, one that was rejected, and
one that was accepted but produced no action.

**Independent Test**: Handle an accepted notification and a rejected one, and confirm each leaves a
distinguishable, card-data-free record.

### Tests for User Story 3 (write FIRST; ensure they FAIL before implementing) ⚠️

- [X] T030 [P] [US3] Write `spec/unit/webhooks_audit_spec.rb` (failing): **every** outcome emits exactly one audit record — accepted, malformed, secret-rejected, unextractable, not-found, unreachable — each carrying the outcome, the transaction id where known, the claimed status, the disagreement flag, whether a re-check ran, and the advisory status; a rejection is distinguishable from an acceptance and from a transport failure; a status disagreement is recorded whether or not the re-check resolves it; the raw body is present but scrubbed; **neither secret value nor any card data appears** (FR-015, FR-016, FR-010d, FR-012, US3-1/2/3, SC-005, SC-009)
- [X] T031 [P] [US3] Write `spec/unit/webhooks_reconcile_spec.rb` (failing): for a transaction whose notification never arrived, `client.transactions.retrieve(id)` yields the authoritative status with the webhook handler entirely uninvolved — the documented fallback when a delivery is lost (US3-4)

### Implementation for User Story 3

- [X] T032 [US3] Emit one `Audit.emit_event` per handled notification in `lib/bml_connect/webhooks.rb` — `outcome: :success` or `:rejected` — with the subject fields above and the scrubbed raw body, placed so every early return and every raise passes through it; never put either secret value in the record (FR-015, FR-004b, research R13)

**Checkpoint**: every delivery, accepted or refused, leaves a diagnosable and leak-free trail.

---

## Phase 6: UAT Verification (the inbound half of the test setup)

**Purpose**: The hardest test setup in this repository so far — it needs **inbound** reachability from
BML UAT, not only outbound calls.

- [X] T033 [P] Write `spec/integration/webhooks_uat_spec.rb`, opt-in via `BML_RUN_UAT=1` through the existing `spec/integration/support.rb` gate: replay the recorded delivery fixture from T001 through `client.webhooks.handle` against a real UAT transaction, asserting the identifier extracts and the authoritative status returns (SC-011)
- [ ] T034 Save the delivery captured in T001 verbatim as `spec/support/fixtures/webhook_delivery.txt` and replay it in `spec/unit/webhooks_observed_delivery_spec.rb`, so the observation is enforced by the suite rather than remembered in prose (depends on T001, quickstart "Closing the release gate")

**Checkpoint**: the `[UNVERIFIED]` inbound surface is backed by something real.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T035 [P] Document the handler in `README.md`: the framework-agnostic wiring example, the advisory-status table, the secret's extract-it-yourself contract, and the re-check delay with its 3-second default and the instruction to set it to zero under a tighter response deadline (FR-010b, FR-016e, SC-008m/008n, SC-012)
- [X] T036 [P] Document in `README.md` that the library enforces **no** inbound body size or nesting limit and that bounding request size is the host application's job, and that with no secret configured every inbound request costs a real retrieve (FR-003c, FR-009c, SC-008n)
- [X] T037 [P] Add the feature to `CHANGELOG.md`, including the additive `retries:` keyword on `Transactions#retrieve` and the new `advisory_http_status` accessor and `WebhookRejectedError`
- [ ] T038 Reconsider the 3-second re-check default against `[UNVERIFIED]` #4 from T001: if UAT shows BML's read path is immediately consistent, the re-check is pure cost on every replayed delivery — record the finding in `specs/005-webhook-handler/contracts/bml-remote.md` and change the default in `lib/bml_connect/client.rb` only if the evidence supports it (spec Assumptions, research R14)
- [X] T039 Run `bundle exec rubocop` and `bundle exec rspec spec/unit spec/contract` clean, confirming no test sleeps for real and no stub hardcodes a host (Constitution II)
- [ ] T040 Walk `specs/005-webhook-handler/quickstart.md` end to end against the built gem, then mark the feature complete in `specs/005-webhook-handler/checklists/requirements.md` and update the spec's Status line

---

## Status — 2026-09-27

**37 of 41 complete.** `bundle exec rspec` is green (412 examples, 0 failures, 18 pending — the
pending ones are the credential-gated UAT suites) and rubocop is **2 offenses below** the repository's
pre-existing baseline of 130.

Four tasks remain open, all of them gated on the one thing that cannot be done from a keyboard here —
a real inbound delivery from BML UAT:

| Task | Why it is still open |
|---|---|
| **T001** ⛔ | Needs a publicly reachable endpoint that BML UAT can deliver to, plus a UAT transaction driven to a status change. **Release gate.** |
| **T034** | Needs T001's captured delivery to exist before it can be fixtured and replayed. |
| **T038** | Needs T001's answer to `[UNVERIFIED]` #4 (does BML's read path lag?) before the 3-second default can be re-judged. |
| **T040** | The quickstart walk-through ends at a live delivery; the rest of it has been exercised by the suite. |

T033's spec file is written and skips cleanly with a pointer to the observation procedure when no
fixture or credentials are present.

## Dependencies & Execution Order

### Phase dependencies

- **Phase 1 (Release Gate)**: independent of everything; blocks *release*, not build. Start it early
  — it needs a tunnel, a registered URL and a real transaction, so its lead time is the longest thing
  in the feature.
- **Phase 2 (Foundational)**: blocks all user stories. T002→T003, T004→T005, T006→T007 are
  test-then-implement pairs; T008 and T009 are independent.
- **Phase 3 (US1)**: depends on Phase 2. The MVP.
- **Phase 4 (US2)**: depends on Phase 2, and on T020 for a `handle` to gate. US2's *guarantees* are
  mostly assertions about US1's implementation — which is why the spec calls them inseparable.
- **Phase 5 (US3)**: depends on Phase 2 and on the outcome paths from US1 and US2 existing, since
  T032 must cover every one of them.
- **Phase 6 (UAT)**: T033 depends on Phase 3; T034 depends on T001.
- **Phase 7 (Polish)**: depends on the stories it documents. T038 depends on T001.

### User story dependencies

- **US1 (P1)**: the only story that can be built straight off the foundation.
- **US2 (P1)**: needs `handle` to exist (T020) before the secret gate can sit in front of it. Not
  independent of US1 in build order, and the spec says so: "Equal to User Story 1 and inseparable
  from it." A handler that trusts its input is a fraud vector, not a feature.
- **US3 (P2)**: needs the outcomes it audits to exist. Genuinely deferrable — the feature works
  without it, an operator just cannot diagnose it.

### Within each story

- Tests are written and MUST FAIL before implementation (Constitution II).
- Parsing before extraction before retrieval before the re-check.
- The value object (T019) is independent of the handler and can be built in parallel with T017/T018.

### Parallel opportunities

- T002, T004, T006, T008 — four independent spec files, one per foundational concern.
- T010–T016 — all seven US1 spec files touch different files and can be written together.
- T023–T026 — all four US2 spec files.
- T030, T031 — both US3 spec files.
- T035, T036, T037 — documentation, though T035 and T036 both edit `README.md`, so serialize those
  two or accept a merge.
- T017/T018/T020/T021/T022 all edit `lib/bml_connect/webhooks.rb` and **cannot** be parallelized.

---

## Parallel Example: User Story 1

```bash
# Write all seven US1 spec files together, then watch every one of them fail:
Task: "spec/unit/webhooks_parsing_spec.rb — formats, fallback order, header normalization"
Task: "spec/unit/webhooks_extraction_spec.rb — candidates, override, headers to extractor"
Task: "spec/unit/status_change_result_spec.rb — readers, masking, no payload reader"
Task: "spec/unit/webhooks_verify_spec.rb — retrieve happens, retries:false, verbatim state"
Task: "spec/unit/webhooks_recheck_spec.rb — one re-check, the cap, zero-delay"
Task: "spec/unit/webhooks_advisory_status_spec.rb — the full mapping, never 404"
Task: "spec/contract/webhooks_remote_spec.rb — URL off base_url, raw Authorization"

bundle exec rspec spec/unit spec/contract   # all red — now implement T017–T022
```

---

## Implementation Strategy

### MVP first (Phase 2 + User Story 1)

1. Phase 2 — foundation, including the `retries:` fix that makes the cap real.
2. Phase 3 — US1.
3. **STOP and VALIDATE**: hand the handler a representative delivery; confirm an authoritative record
   comes back and a status the gem has never seen survives verbatim.

Note what the MVP already gives you for free: because the status always comes from the retrieve,
verify-by-fetch is in place the moment US1 works. US2 adds the spend gate and the *proof* that no
opt-out exists — it does not add the protection.

### Incremental delivery

1. Foundation → US1 → handled deliveries (MVP).
2. US2 → the spend gate, the forgery proofs, the no-raw-payload guarantee.
3. US3 → the audit trail an operator needs at 3am.
4. Phase 6 → the observation that turns `[UNVERIFIED]` guesses into facts.

### Release gates (both mandatory)

- **T001** — the identifier field observed against a real UAT delivery (FR-019, SC-011).
- **T039/T040** — clean suite, clean rubocop, quickstart walked.

Everything else may merge before either.

---

## Notes

- [P] = different files, no dependency on an incomplete task.
- The whole inbound surface is `[UNVERIFIED]`; T001 is the only thing that changes that.
- No test may sleep for real — the re-check wait is injected (research R8).
- No stub may hardcode a host; every URL interpolates `client.base_url` (Constitution II).
- Commit after each task or logical pair. Stop at any checkpoint to validate a story on its own.
- If a task tempts you to add a state allow-list, a default secret location, a body-size limit, or a
  way to skip the retrieve — that is the feature's design being tested, and the answer is no.
