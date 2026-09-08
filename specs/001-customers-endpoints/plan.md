# Implementation Plan: Customers Endpoints

**Branch**: `001-customers-endpoints` | **Date**: 2026-09-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-customers-endpoints/spec.md`

## Summary

Add a `Customers` resource to the existing `bml_connect` gem covering BML's five documented
customer operations — create, retrieve, list, partial update, and archive — under the
`/public-customers` path family. The resource is reached through the existing configured
`BMLConnect::Client`, reuses its base URL, mode and raw-`Authorization` credential handling, and
returns whitelisted value objects. It is the anchor feature: features `002` and `004` both
address resources by `customerId`.

Technical approach: one resource class plus two value objects, layered on the client's existing
Faraday plumbing, following the pattern `BMLConnect::Transactions` already sets. Contract tests
assert conformance against the vendored `reference/Connect-API.json` itself, not against
hand-written URL strings.

## Technical Context

**Language/Version**: Ruby. The gemspec declares `required_ruby_version >= 2.3.0`; the installed
toolchain is 2.7.4. New code MUST stay within 2.7-compatible syntax — no pattern matching, no
endless methods, no `Hash#except`.

**Primary Dependencies**: None added. Reuses the gem's existing `faraday ~> 1.0`,
`faraday_middleware ~> 1.0`, and `deep_merge ~> 1.2`.

> The retired `bml_tokenization` used stdlib `net/http`. This gem is already on Faraday and
> switching would be a breaking change to `Client#set_http_client`, which consumers may use to
> inject a test double. Faraday stays (Constitution V — no unjustified churn).

**Storage**: N/A — stateless client library. No cardholder data at rest, ever.

**Testing**: RSpec + WebMock. Three tiers: unit (validation, mapping, masking), contract
(request shape and error mapping, with stub URLs **derived from `Client#base_url`**), and an
opt-in credential-gated UAT suite. A fourth, new tier: a **spec-conformance test** that parses
`reference/Connect-API.json` and asserts every path the resource can emit exists in it.

**Target Platform**: Any Ruby runtime; server-side only.

**Project Type**: Single project — a Ruby gem. Additive change to an existing published gem.

**Performance Goals**: In-process overhead under 20ms per call excluding network latency.

**Constraints**: TLS only; no PAN/CVV anywhere; masked structured logging; audit record on every
state change; strict environment isolation.

**Scale/Scope**: 5 operations, 2 value objects, 1 resource class, ~6 mapped error conditions.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Derived from `.specify/memory/constitution.md` **v2.0.0**.

| # | Gate (from principle) | How this plan satisfies it | Status |
|---|---|---|---|
| I | SAD never persisted; PAN never plaintext; secrets injected; TLS | The resource neither accepts nor returns card data; a PAN screen rejects it on input (FR-014); attribute whitelisting drops it on output; credentials come from existing client config; Faraday over HTTPS. | PASS |
| II | Test-first; success/failure/rejection paths | Tasks order failing tests before implementation, covering success, local-validation rejection, not-found, auth, and availability. | PASS |
| II | **Stub is not evidence; stub URLs derived from base URL** | T004 adds a conformance test reading `Connect-API.json`; every contract stub interpolates `client.base_url` rather than hardcoding a host. This is the direct fix for the failure that produced 28 broken specs in the retired gem. | PASS |
| III | Contract from published spec; live verification; `[UNVERIFIED]` marking | `contracts/bml-remote.md` quotes the document throughout, marks pagination and 404 behavior `[UNVERIFIED]`, and carries a verification table that cannot be closed without UAT observation. | PASS |
| IV | Masked structured logs; audit on state change; actionable errors | Masked logger; audit on create/update/archive (FR-012); distinguishable error hierarchy (FR-011). | PASS |
| V | Simplest design; no invented conveniences | One class, no new dependency, no cross-resource orchestration. `archive` is named for what BML does rather than presented as a hard delete. | PASS |

**Initial Constitution Check: PASS** — no violations; Complexity Tracking not required.

## Phase 0 — Research

See [research.md](./research.md). Resolves: transport choice, partial-update serialization,
pagination absence, soft-delete naming, `count` typing, and the PAN-screen placement.

## Phase 1 — Design

- [data-model.md](./data-model.md) — Customer and list envelope, validation, lifecycle.
- [contracts/bml-remote.md](./contracts/bml-remote.md) — the BML HTTP contract, quoted.
- [contracts/library-api.md](./contracts/library-api.md) — the public Ruby surface.
- [quickstart.md](./quickstart.md) — running the suites, including against UAT.

**Post-Design Constitution Check: PASS** — the design adds no abstraction beyond one resource
class and two value objects, and introduces no runtime dependency.

## Phase 2 — Tasks

See [tasks.md](./tasks.md).

## Project Structure

```
lib/bml_connect/
  client.rb                 (modified — add #customers)
  customers.rb              (new — resource)
  models/
    customer.rb             (new)
    customer_list.rb        (new)
  errors.rb                 (new — shared hierarchy)
  masking.rb                (new — shared)
  audit.rb                  (new — shared)

spec/
  unit/customers_spec.rb
  contract/customers_remote_spec.rb
  contract/openapi_conformance_spec.rb   (new — reads reference/Connect-API.json)
  integration/customers_uat_spec.rb      (opt-in, credential-gated)
```

`errors.rb`, `masking.rb` and `audit.rb` are shared infrastructure introduced by this feature and
consumed by `002`, `003` and `004`. They are ported from `bml_tokenization` — the one part of it
whose engineering was sound, since it never depended on the wrong API shape.

## Complexity Tracking

Not required — no constitutional gate was violated or waived.
