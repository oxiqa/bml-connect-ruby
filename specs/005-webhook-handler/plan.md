# Implementation Plan: Transaction Status Webhook Handler

**Branch**: `005-webhook-handler` | **Date**: 2026-09-27 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-webhook-handler/spec.md`

## Summary

Accept an inbound BML transaction-status notification, treat every byte of it as untrusted, and
return an authoritative `TransactionRecord` fetched fresh from BML. The library is handed a body,
headers, and (optionally) a presented secret; it returns a value object or raises. It owns no
route, no response, and no datastore.

The published contract documents the notification **nowhere** — not its method, payload, signature,
or event set. So the design is built to need almost nothing from it: one field (the transaction id)
to know what to fetch, and one optional field (a claimed status) used solely for a comparison that
is never reported as fact.

Three findings shape the build:

1. **`transactions.retrieve` currently auto-retries**, which silently breaks the two-retrieve cap
   (FR-009) — one transport failure would become three HTTP requests. It needs an additive
   `retries:` keyword. This is the one change to existing behavior the feature requires.
2. **`OpenSSL.fixed_length_secure_compare` is unavailable on this toolchain** (verified on Ruby
   2.7.4), so the constant-time secret comparison (FR-009d) is SHA-256 digests compared by a
   fixed-length byte XOR — pure stdlib, no new dependency.
3. **A 404 advisory status would be actively dangerous.** FR-016d requires a permanent status for a
   not-found transaction, but advising `404` from a notification endpoint reads to a sender as "this
   endpoint does not exist" and risks the hook being disabled. The mapping uses `422`.

## Technical Context

**Language/Version**: Ruby, 2.7-compatible syntax (toolchain is 2.7.4; `.rubocop.yml` targets 2.7).

**Primary Dependencies**: **None added.** Parsing uses stdlib `json` and `uri`
(`URI.decode_www_form`); the constant-time compare uses stdlib `digest`. No Rack, no web framework —
FR-001 and SC-012 forbid it.

**Storage**: N/A — stateless client library. Deduplication is explicitly the caller's (FR-014).

**Testing**: RSpec + WebMock across unit, contract, and opt-in UAT tiers. The re-check delay is
injected so no test sleeps for real.

**Target Platform**: Any Ruby runtime; server-side only. The host application owns the HTTP endpoint.

**Project Type**: Single project — additive change to a released gem.

**Performance Goals**: Under 20ms in-process overhead excluding network and the configured re-check
delay.

**Constraints**: TLS only; no PAN/CVV/secret in any output; **at most two retrieves per
notification, neither auto-retried**; audit on every outcome including rejections; the re-check
delay is spent inside the caller's request (default 3s, zero disables).

**Scale/Scope**: 1 public operation, 1 new value object, 1 new error class, 6 modified files.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Derived from `.specify/memory/constitution.md` **v2.0.0**.

| # | Gate (from principle) | How this plan satisfies it | Status |
|---|---|---|---|
| I | SAD never persisted; PAN never plaintext; TLS; secrets from config | Inbound bodies are screened and scrubbed before any log or audit write; the presented secret and the configured secret are never logged, never on the result, never in an error message; the secret is a constructor option, never a constant. | PASS |
| II | Test-first; success/failure/rejection paths | Tests precede implementation across accepted, malformed, unparseable, unextractable, secret-absent, secret-wrong, secret-right, disagreeing, persistently-disagreeing, not-found, unreachable, and card-data-bearing deliveries. | PASS |
| II | Stub is not evidence; stub URLs derived from base URL | The verifying retrieve reuses `transactions.retrieve`, already covered by the conformance spec; every stub interpolates `client.base_url`. **The inbound side has no endpoint to stub against** — which is exactly why FR-019/SC-011 make a real UAT delivery a release gate. | PASS |
| III | Contract from published spec; live verification; `[UNVERIFIED]` marking | The entire inbound surface is marked `[UNVERIFIED]` in `contracts/bml-remote.md` with every candidate field individually justified against `reference/Connect-API.json`. The only outbound call is `GET /public/transactions/{transactionId}`, already implemented and cited. | PASS |
| IV | Masked logs; audit on state change; actionable errors | Every outcome audits, including rejections (FR-015), which is broader than the constitution's floor — a rejected notification is the signature of a forgery attempt and an operator needs to see it. Errors name the transaction id where known. | PASS |
| V | Simplest design; **no invented conveniences** | No opt-out of verification (FR-007), no state enumeration (FR-005), no dedup store, no registration methods, no body-size limit, no guessed secret location (FR-009e). The library refuses to infer where the secret travels rather than shipping a plausible default. | PASS |

**Initial Constitution Check: PASS** — no violations; Complexity Tracking not required.

One judgment recorded for review: adding `BMLConnect::WebhookRejectedError` is a new class, which
Principle V asks to justify. FR-016 and SC-008 require a failed secret check to be observably
distinguishable from a malformed body. Both would otherwise be `ValidationError`, distinguishable
only by a `field:` value — too weak for a security rejection that an operator will alert on.

## Phase 0 — Research

See [research.md](./research.md). Fourteen decisions, including the three findings above, the
candidate field lists and their justifications, the advisory-status mapping, and the header-name
normalization that makes a Rack `env` hash work without a Rack dependency.

No `NEEDS CLARIFICATION` items remain: the spec's five 2026-09-27 clarifications closed the design
questions, and the one outstanding unknown (which field carries the transaction id) is a release
gate with a shipped mitigation, not a planning blocker.

## Phase 1 — Design

- [data-model.md](./data-model.md)
- [contracts/bml-remote.md](./contracts/bml-remote.md)
- [contracts/library-api.md](./contracts/library-api.md)
- [quickstart.md](./quickstart.md)

**Post-Design Constitution Check: PASS.** Design review surfaced one hazard the initial check had
not: `transactions.retrieve`'s existing retry would have broken FR-009's cap. Resolved additively
(R3) rather than by reimplementing transport, which would have violated Principle V and the spec's
own "consumer of it, not a reimplementation" assumption.

## Phase 2 — Tasks

Not created by this command. Run `/speckit-tasks`.

## Project Structure

### Documentation (this feature)

```text
specs/005-webhook-handler/
├── plan.md              # This file
├── research.md          # Phase 0
├── data-model.md        # Phase 1
├── quickstart.md        # Phase 1
├── contracts/
│   ├── bml-remote.md    # Phase 1 — the [UNVERIFIED] inbound surface
│   └── library-api.md   # Phase 1 — the public Ruby surface
├── checklists/
│   └── requirements.md  # existing, 16/16
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
lib/bml_connect/
├── webhooks.rb                            (new — the handler)
├── models/status_change_result.rb         (new — the returned value object)
├── client.rb                              (modified — #webhooks, webhook_secret, webhook_recheck_delay)
├── errors.rb                              (modified — Error#advisory_http_status, WebhookRejectedError)
├── transactions.rb                        (modified — retrieve(id, retries: true))
├── resource.rb                            (modified — mask BML's error text before it becomes a message)
├── models.rb                              (modified — require the new model)
└── ../bml_connect.rb                      (modified — require webhooks)

spec/
├── unit/webhooks_parsing_spec.rb           # FR-003/003a/003b — JSON, form, fallback, rejection
├── unit/webhooks_extraction_spec.rb        # FR-002/002a/002b/002c — candidates, override, headers
├── unit/webhooks_verify_spec.rb            # FR-006/007/008 — fetch-authoritative, no fallback
├── unit/webhooks_secret_spec.rb            # FR-009a/009b/009d/009e — spend gate, not a trust gate
├── unit/webhooks_recheck_spec.rb           # FR-010–010d — one re-check, cap, zero-delay
├── unit/webhooks_advisory_status_spec.rb   # FR-016a–016e — the full mapping
├── unit/webhooks_surface_spec.rb           # SC-004/008i — no opt-out, no raw body reachable
├── unit/webhooks_audit_spec.rb             # FR-015/FR-011/FR-012 — every outcome, nothing leaked
├── unit/webhooks_forgery_spec.rb           # SC-002/003 — the defining threat
├── unit/webhooks_pan_screening_spec.rb     # FR-011/011a — masked, and still handled
├── unit/webhooks_idempotence_spec.rb       # FR-014/SC-006/006a — equal given an unchanged record
├── unit/webhooks_reconcile_spec.rb         # US3-4 — the fallback when nothing arrives
├── unit/webhooks_errors_spec.rb            # FR-016a — the advisory carrier
├── unit/webhooks_client_config_spec.rb     # FR-009a/010b — the two knobs
├── unit/transactions_retrieve_retries_spec.rb # research R3 — the retry fix
├── unit/status_change_result_spec.rb       # the value object in isolation
├── contract/webhooks_remote_spec.rb        # the verifying retrieve, stubs off client.base_url
├── integration/webhooks_uat_spec.rb        # opt-in; the recorded-delivery replay + manual procedure
└── support/webhooks_helpers.rb             # delivery builders (JSON + form), fake logger
```

**Structure Decision**: A new `BMLConnect::Webhooks` class reached as `client.webhooks`, memoized
exactly like `#customers` and `#tokens`. It **issues no HTTP of its own** — the verifying retrieve is
delegated to `client.transactions.retrieve`, so there is one implementation of the transaction read
in the library and the webhook path inherits its error mapping for free.

**It is deliberately NOT a `Resource` subclass** (corrected during implementation; this plan
originally said it was). Two reasons, both concrete. First, the helpers the plan expected to inherit
— `blank?`, `symbolize`, `screen_for_pan!`, `audit` — are private to `Transactions`, not to
`Resource`, so there was nothing to inherit. Second and decisive: `Resource#handle(response)` is a
private method, and a subclass defining a public `#handle(body:, ...)` overrides it, so the inherited
`request` would call the public method with a Faraday response and raise `ArgumentError`. Nothing in
`Resource` is needed here, so the class stands alone with a handful of local helpers.

## Release gate

**This feature MUST NOT be declared complete until a genuine UAT delivery is observed** (FR-019,
SC-011): register a reachable URL, drive a transaction to a status change, record the raw delivery
verbatim in `contracts/bml-remote.md`, and confirm or correct the candidate lists. Every candidate
stays `[UNVERIFIED]` until then.

It may be built, merged, and tested before that: a wrong candidate fails loudly at extraction or at
the retrieve rather than reporting a false status, and `extract_id:` lets a merchant who has seen
their own deliveries bypass the library's guess entirely.

Two things the same observation should also settle, while the endpoint is up:

- **The body format** (FR-003b) — JSON or form-encoded. Both are implemented; only one is real.
- **Whether BML's read path lags at all.** If the first retrieve is always immediately consistent,
  the 3-second default re-check is pure cost on every replayed delivery and should be reconsidered.
  The spec already flags this (Assumptions); the UAT run is when to answer it.

## Complexity Tracking

Not required — no constitutional gate was violated or waived. The one new error class is justified
in the Constitution Check above.
