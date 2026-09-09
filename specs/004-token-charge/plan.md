# Implementation Plan: Token Charge

**Branch**: `004-token-charge` | **Date**: 2026-09-07 (reconciled 2026-09-09 to the FR-001 clarification: the charge lives on the `Customers` resource) | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-token-charge/spec.md`

## Summary

Add a single operation — `POST /public-customers/charge` — letting a merchant take payment from a
previously stored card without the cardholder present. It is the smallest feature in the
migration and the one with the highest blast radius: it moves money with no idempotency key and
no cardholder in the loop.

The design is therefore dominated by three refusals: no automatic retry, no combined
create-and-charge convenience, and no shipping until the `tokenId` identifier is confirmed.

## Technical Context

**Language/Version**: Ruby, 2.7-compatible syntax.

**Primary Dependencies**: None added. Reuses shared infrastructure from `001` and the
`TransactionRecord` model from `003`.

**Storage**: N/A — stateless client library.

**Testing**: RSpec + WebMock across unit, contract, conformance and opt-in UAT tiers. The UAT
tier here requires a genuinely stored card, which requires a human to complete a hosted payment.

**Target Platform**: Any Ruby runtime; server-side only.

**Project Type**: Single project — additive change to a released gem.

**Performance Goals**: Under 20ms in-process overhead excluding network.

**Constraints**: TLS only; no PAN/CVV; **no automatic retry under any circumstance**; audit on
every charge including failures; strict environment isolation.

**Scale/Scope**: 1 operation, 1 input structure, 0 new response entities.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Derived from `.specify/memory/constitution.md` **v2.0.0**.

| # | Gate (from principle) | How this plan satisfies it | Status |
|---|---|---|---|
| I | SAD never persisted; PAN never plaintext; TLS | The charge body carries three opaque ids and nothing else; a PAN screen rejects card-like input (FR-008); TLS enforced. | PASS |
| II | Test-first; success/failure/rejection paths | Tests precede implementation and cover success, decline, each missing field, deleted token, customer/token mismatch, and the no-retry assertion (SC-004). | PASS |
| II | Stub is not evidence; stub URLs derived from base URL | Conformance test extended to this path; stubs interpolate `client.base_url`. | PASS |
| III | Contract from published spec; live verification; `[UNVERIFIED]` marking | Five open items recorded, one of them **release-blocking**. The verification table cannot close without UAT. | PASS |
| IV | Masked logs; audit on state change; actionable errors | Audit on every charge including failures (FR-011); `AvailabilityError` names the transaction id so recovery is actionable (FR-005). | PASS |
| V | Simplest design; **no invented conveniences** | The decisive gate. No combined create-and-charge method, no `amount` parameter, no retry. Each would be a convenience the platform does not offer, wrapped around a money movement. | PASS |

**Initial Constitution Check: PASS** — no violations; Complexity Tracking not required.

## Phase 0 — Research

See [research.md](./research.md).

## Phase 1 — Design

- [data-model.md](./data-model.md)
- [contracts/bml-remote.md](./contracts/bml-remote.md)
- [contracts/library-api.md](./contracts/library-api.md)
- [quickstart.md](./quickstart.md)

**Post-Design Constitution Check: PASS**.

## Phase 2 — Tasks

See [tasks.md](./tasks.md).

## Project Structure

```
lib/bml_connect/
  customers.rb             (modified — add #charge)

spec/
  unit/customers_charge_spec.rb
  contract/customers_charge_remote_spec.rb
  integration/customers_charge_uat_spec.rb
```

No new files beyond specs. The operation is one method on the existing `Customers` resource
(whose `PATH` is already `/public-customers`, so the charge posts to `"#{PATH}/charge"`),
returning a model feature `003` already defines.

## Release gate

**This feature MUST NOT be released until `[UNVERIFIED]` item #1 — whether `tokenId` is
`Token#id` or `Token#token` — is resolved against UAT.** Everything else may be built and merged;
adoption waits on that answer. Charging the wrong identifier is a money-movement defect.

## Complexity Tracking

Not required — no constitutional gate was violated or waived.
