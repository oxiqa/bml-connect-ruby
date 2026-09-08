# Implementation Plan: Stored Card Tokens

**Branch**: `002-stored-card-tokens` | **Date**: 2026-09-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-stored-card-tokens/spec.md`

## Summary

Add a `Tokens` resource to the `bml_connect` gem covering BML's three documented stored-card
operations — list, retrieve, and delete — all nested under `/public-customers/{customerId}`.
The resource is read-and-delete only: BML publishes no endpoint that creates a token, so
creation lives entirely in feature `003`.

This feature replaces two retired features (`002-card-on-file-endpoints` and
`004-tokenization-endpoints`) that between them specified a separate card-on-file object and a
`POST /tokens` tokenize endpoint. Neither exists.

## Technical Context

**Language/Version**: Ruby, 2.7-compatible syntax (gemspec declares `>= 2.3.0`).

**Primary Dependencies**: None added. Reuses the shared `Resource`, `errors`, `masking`, and
`audit` infrastructure introduced by feature `001`. Retry/backoff (FR-013a) is a transport-level
concern that belongs in that shared layer and is configured on the client; this feature inherits
it rather than implementing bespoke retry code. If feature `001`'s transport does not yet retry,
adding it is a shared-infrastructure change consumed here (see research R9).

**Storage**: N/A — stateless client library. No cardholder data at rest, ever.

**Testing**: RSpec + WebMock across four tiers — unit, contract (stub URLs derived from
`client.base_url`), OpenAPI conformance, and an opt-in credential-gated UAT suite.

**Target Platform**: Any Ruby runtime; server-side only.

**Project Type**: Single project — additive change to an existing published gem.

**Performance Goals**: Under 20ms in-process overhead per call excluding network latency.

**Constraints**: TLS only; the library never accepts card input on this resource and never
returns a full PAN; masked structured logging; audit record on delete; strict environment
isolation; tokens strictly scoped to their owning customer. Transient failures (`429`, timeout,
`5xx`) are retried with bounded exponential backoff on all three operations — delete included,
because soft-delete is idempotent — then surfaced as the original distinguishable error
(FR-013a); non-transient errors are never retried.

**Scale/Scope**: 3 operations, 2 value objects, 1 resource class.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Derived from `.specify/memory/constitution.md` **v2.0.0**.

| # | Gate (from principle) | How this plan satisfies it | Status |
|---|---|---|---|
| I | SAD never persisted; PAN never plaintext; tokens non-reversible; no detokenization | No operation accepts card input (FR-006); only `paddedCardNumber` is ever returned (FR-007); no detokenize path exists or will (FR-008); whitelisting drops anything unexpected (FR-009). | PASS |
| II | Test-first; success/failure/rejection paths | Tests precede every operation, covering success, blank-input rejection, not-found, cross-customer access, auth, and availability. | PASS |
| II | Stub is not evidence; stub URLs derived from base URL | Conformance test (from `001` T004) covers this feature's three paths; every stub interpolates `client.base_url`. | PASS |
| III | Contract from published spec; live verification; `[UNVERIFIED]` marking | `contracts/bml-remote.md` quotes the document and carries **seven** open `[UNVERIFIED]` items, including the `requestBody`-vs-response anomaly on list. The verification table cannot close without UAT. | PASS |
| IV | Masked logs; audit on state change; actionable errors | Masked logging; audit on delete (FR-014); distinguishable errors (FR-013). A retried delete emits exactly **one** audit record capturing the final outcome, not one per attempt (FR-013a × FR-014). | PASS |
| V | Simplest design; **no invented conveniences** | The decisive gate here. The library exposes no `tokenize` method because BML has no such endpoint, even though callers will expect one. A unit test enforces the absence (SC-006). Retry/backoff (FR-013a) adds surface, but it is a *specified* need from clarification — not speculative — and lives once in the shared transport rather than being reimplemented per resource. | PASS |

**Initial Constitution Check: PASS** — no violations; Complexity Tracking not required.

## Phase 0 — Research

See [research.md](./research.md). Resolves: the merge of two retired features, absence of a
create path, the `id`-vs-`token` charge handle, list envelope uncertainty, and cross-customer
scoping as a security test.

## Phase 1 — Design

- [data-model.md](./data-model.md) — Token, collection, lifecycle.
- [contracts/bml-remote.md](./contracts/bml-remote.md) — the BML HTTP contract, quoted.
- [contracts/library-api.md](./contracts/library-api.md) — the public Ruby surface, including
  what deliberately does not exist.
- [quickstart.md](./quickstart.md) — usage and UAT verification.

**Post-Design Constitution Check: PASS**.

## Phase 2 — Tasks

See [tasks.md](./tasks.md).

## Project Structure

```
lib/bml_connect/
  client.rb                 (modified — add #tokens)
  tokens.rb                 (new — resource)
  models/
    token.rb                (new)
    token_list.rb           (new)

spec/
  unit/tokens_spec.rb
  contract/tokens_remote_spec.rb
  integration/tokens_uat_spec.rb
```

Depends on `errors.rb`, `masking.rb`, `audit.rb`, and `resource.rb` from feature `001`.

## Complexity Tracking

Not required — no constitutional gate was violated or waived.
