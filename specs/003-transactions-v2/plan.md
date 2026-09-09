# Implementation Plan: Transactions V2

**Branch**: `003-transactions-v2` | **Date**: 2026-09-07 (reconciled 2026-09-08) | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-transactions-v2/spec.md`

## Summary

Extend the existing `BMLConnect::Transactions` resource onto BML's documented
`POST /public/v2/transactions` endpoint, add `tokenizationDetails` support (the only way a stored
card comes into existence), and add the documented update, capture and cancel operations. The
existing v1 `create`, `get` and `list` keep their exact behavior and return types.

This is the only feature in the migration that touches **released, in-production** code. Six call
sites in `msgowl/website` depend on the current surface, so every change is additive.

## Technical Context

**Language/Version**: Ruby, 2.7-compatible syntax.

**Primary Dependencies**: None added. Reuses `faraday` and the shared infrastructure from `001`.

**Storage**: N/A — stateless client library.

**Testing**: RSpec + WebMock across unit, contract, OpenAPI-conformance and opt-in UAT tiers.
Plus a **backward-compatibility suite** asserting the v1 methods' request shape and return type
are byte-identical to today's.

**Target Platform**: Any Ruby runtime; server-side only.

**Project Type**: Single project — additive change to a released gem.

**Performance Goals**: Under 20ms in-process overhead per call excluding network.

**Constraints**: TLS only; no PAN/CVV; the hosted payment URL never logged or audited; **no
automatic retry on create or capture**; strict environment isolation.

**Scale/Scope**: 6 new operations, 1 new value object, 2 create variants implemented of 5.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Derived from `.specify/memory/constitution.md` **v2.0.0**.

| # | Gate (from principle) | How this plan satisfies it | Status |
|---|---|---|---|
| I | SAD never persisted; PAN never plaintext; secrets injected; TLS | Card entry is on BML's hosted page; the library never sees a PAN. A PAN screen rejects card-like input (FR-014). The payment URL is treated as a secret and excluded from logs and audit (FR-015). | PASS |
| II | Test-first; success/failure/rejection paths | Tests precede every operation, including each conditional `tokenizationDetails` rule and the no-retry-on-create assertion (SC-007). | PASS |
| II | Stub is not evidence; stub URLs derived from base URL | Conformance test extended to this feature's paths; the legacy v1 create is **explicitly allow-listed as undocumented** in that test with a comment, so the exception is visible rather than silent. | PASS |
| III | Contract from published spec; live verification; `[UNVERIFIED]` marking | `contracts/bml-remote.md` quotes the document and carries six open items, including the payment-URL field, which is declared a production blocker. The v1 exception is recorded, not hidden. | PASS |
| IV | Masked logs; audit on state change; actionable errors | Audit on create/capture/cancel/update (FR-017); payment URL excluded (FR-015); distinguishable errors. | PASS |
| V | Simplest design; no invented conveniences | `create_v2` implements only the two variants the gem can honestly support and rejects the other three by name rather than sending a body BML will refuse. No auto-retry is invented for a call with no documented idempotency key. | PASS |

**Initial Constitution Check: PASS**, with one recorded exception: the legacy v1 create path is
not in the published document. It is retained deliberately under FR-010/FR-011 because removing
it breaks production, and it is recorded in Complexity Tracking below.

## Phase 0 — Research

See [research.md](./research.md).

## Phase 1 — Design

- [data-model.md](./data-model.md)
- [contracts/bml-remote.md](./contracts/bml-remote.md)
- [contracts/library-api.md](./contracts/library-api.md)
- [quickstart.md](./quickstart.md)

**Post-Design Constitution Check: PASS**.

**2026-09-08 clarification reconciliation** — three spec clarifications were checked against the
existing design; no re-architecture required:

- **FR-008 (capture amount)**: capture now validates `amount` under the identical FR-005 rule
  (positive Integer, minor units; reject Float/String/zero/negative, no remote call). Design
  updated in `data-model.md`, `contracts/library-api.md`, `contracts/bml-remote.md`.
- **FR-011 (v1 deprecation warning)**: the one-time, deduplicated runtime warning was already
  specified in `contracts/library-api.md`, `research.md` R2, and `quickstart.md` — no change.
- **FR-019 (full parallel value-object surface)**: `create_v2`, `retrieve`, `update`, `capture`,
  `cancel` were already the planned surface (`research.md` R1) — no change.

`tasks.md` predates these clarifications; run `/speckit-tasks` (or `/speckit-analyze`) to fold the
strengthened capture-amount validation into the task list before implementing.

## Phase 2 — Tasks

See [tasks.md](./tasks.md).

## Project Structure

```
lib/bml_connect/
  transactions.rb                  (modified — additive only)
  models/
    transaction.rb                 (UNTOUCHED — v1 request builder)
    transaction_record.rb          (new — v2 response object)
    tokenization_details.rb        (new — input validation)

spec/
  unit/transactions_v2_spec.rb
  unit/tokenization_details_spec.rb
  contract/transactions_v2_remote_spec.rb
  contract/transactions_v1_compat_spec.rb    (new — pins existing behavior)
  integration/transactions_v2_uat_spec.rb
```

## Complexity Tracking

| Violation | Why needed | Simpler alternative rejected because |
|---|---|---|
| Calling an undocumented endpoint (`POST public/transactions`) | Six production call sites use it; it is live and working | Removing it breaks `msgowl/website` immediately. Silently proxying `create` to v2 was rejected — v2 has a different response shape and an unverified payment-URL field, so callers reading `resp.body[:url]` would break subtly rather than loudly |
| Two response conventions in one gem (raw Faraday vs value objects) | `create`/`get`/`list` must not change return type | Migrating them is a breaking change; queued for `v1.0.0` |
| Two classes named for a transaction (`Transaction`, `TransactionRecord`) | The v1 request builder already owns the good name | Renaming it breaks `transactions.create` |
