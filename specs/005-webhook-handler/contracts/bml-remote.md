# Contract: Remote BML — Transaction Status Webhook

**Feature**: `005-webhook-handler` | **Counterparty**: Bank of Maldives Connect API v2.0

**Source of truth**: `reference/Connect-API.json`. Anything not in it is **[UNVERIFIED]**.

This contract is unlike every other one in this repository: the traffic it describes runs
**inbound**, and the published document describes none of it. Read the two sections in order — what
the document says, then what it does not.

## Common

Servers, auth and transport for the outbound call as in
[`001`](../../001-customers-endpoints/contracts/bml-remote.md#common) — raw `Authorization` API key,
no `Bearer`, no `X-App-Id`, JSON over TLS (FR-017).

## Outbound: the verifying retrieve — `GET /public/transactions/{transactionId}`

The **only** call this feature makes. Operation id `get-public-transactions-transactionId`, summary
"Get Transaction", tag `Transactions`.

Already implemented as `Transactions#retrieve` (feature `003`) and covered by
`spec/contract/openapi_conformance_spec.rb`. This feature is a consumer, not a reimplementation.

| Property | Value | Requirement |
|---|---|---|
| Calls per notification | **at most 2** — the verify, plus at most one re-check | FR-009, FR-010a |
| Auto-retry | **none** — `retries: false` | FR-009 |
| On transport failure | `AvailabilityError` after exactly one attempt | FR-008 |
| On 404 | `NotFoundError`, distinct from transport failure | FR-008, FR-016 |

> **`retries: false` is load-bearing.** `Transactions#retrieve` defaults to `retries: true` and will
> otherwise make up to `client.max_retries + 1` HTTP calls, turning one notification into as many as
> six requests and breaking SC-008d against exactly the failure mode the cap exists for. See
> research R3.

Response `200` is a full transaction record — the same body feature `003` documents, mapped to
`Models::TransactionRecord`. `state` is passed through verbatim; this library ships no enumeration of
states, because the document enumerates none (FR-005, SC-010).

## Documented but deliberately not implemented

| Endpoint | Operation id | Status |
|---|---|---|
| `POST /public/webhooks` | `post-public-webhooks` | **Out of scope.** Body is `{ "hookUrl": "…" }`, `hookUrl` required, described as "A URL where you'd like to be notified for any update". Company-wide. |
| `DELETE /public/webhooks` | `delete-public-webhooks` | **Out of scope.** Deletes by the same `hookUrl`. |

Registration stays with the merchant portal or the per-transaction `webhook` field shipped in feature
`003`. Recorded here so a future reader knows the omission was a decision, not an oversight.

The `Webhook` schema (`id`, `companyId`, `hookUrl`, `created`, `updated`; only `hookUrl` required)
describes the **registration record** — not the notification. Nothing in it constrains the callback.

---

## ⚠️ Inbound: the notification — the entire surface is [UNVERIFIED]

`reference/Connect-API.json` documents how to register a hook and **nothing whatsoever** about the
delivery it produces. There is no callback object, no `callbacks:` key, no webhook payload schema, no
event list, no signature scheme, and no delivery-semantics statement anywhere in the document.

| Not documented | How this library copes |
|---|---|
| The callback's HTTP method | Irrelevant — the host application owns the route (FR-001) |
| The payload shape | Never trusted; only an id is read from it (FR-006) |
| Any signature, secret, or authentication | No signature is invented; an optional shared secret gates *spend, not trust* (FR-009a/009b) |
| Which events fire | Irrelevant — every delivery is handled the same way |
| The set of `state` values | Passed through verbatim; no allow-list (FR-005) |
| Retry, ordering, at-least-once | Assumed at-least-once and possibly out of order (spec Assumptions) |
| The `Content-Type` | Two formats accepted; see below |

The `Transaction.state` field is typed only as a non-empty string. The sole states observable
anywhere in the document are `INITIATED` and `QR_CODE_GENERATED`, both from a single example.

### [UNVERIFIED] #1 — which field carries the transaction identifier ⚠️ RELEASE GATE

Candidates in resolution order. Each is an inference from the published document, and each is
`[UNVERIFIED]` until a real delivery is observed (FR-002a).

| # | Candidate | Justification in the published document |
|---|---|---|
| 1 | `transactionId` | The exact spelling BML uses for this value wherever it *is* documented: the path parameter of `/public/transactions/{transactionId}`, and the `transactionId` field of the `post-public-charge` body. The strongest available inference. |
| 2 | `transaction_id` | snake_case spelling of the same name; covers a callback emitted by a different service than the REST API. |
| 3 | `id` | The field name on the `Transaction` schema itself, for a payload embedding a record rather than naming one. |

**Not a candidate: `localId`.** It is the merchant's own reference, not BML's transaction id.
Retrieving by it would 404 and land on the permanent-advisory path (FR-016d) — a plausible-looking
candidate that produces a confidently wrong outcome is worse than no candidate at all.

Only top-level keys are searched, and only a non-blank `String` counts. Nested payloads are what
`extract_id:` is for (FR-002c).

**Mitigations that keep this off the critical path**: verify-by-fetch means a wrong guess cannot
report a false status — it fails loudly at extraction or at the retrieve; and `extract_id:` lets a
merchant who has observed their own deliveries override the list outright (FR-002b).

### [UNVERIFIED] #2 — which field carries a claimed status, if any

Candidates: `state` (the `Transaction` schema's spelling), then `status`.

Used **only** for the FR-010 disagreement comparison, normalized with `strip.upcase` for the
comparison alone (research R7). Never reported as fact. When no comparable status is present the
library performs one retrieve and does not re-check (FR-010c) — the document does not promise the
payload carries a status at all.

### [UNVERIFIED] #3 — the body format

Both `application/json` and `application/x-www-form-urlencoded` are accepted (FR-003a). Only one is
real. Selected by declared `Content-Type`; when absent or unrecognized the library attempts JSON
then form-encoded, in that order and for the reason given in research R4.

### [UNVERIFIED] #4 — whether BML's read path lags the event

The re-check (FR-010) is a defensive measure against a plausible-but-undocumented behavior, with a
3-second default delay that is itself a judgment rather than an observed figure. **If the retrieve
turns out to be immediately consistent, the re-check is pure cost on every replayed delivery and the
default should be reconsidered.**

### [UNVERIFIED] #5 — whether any delivery metadata exists

No delivery id, attempt counter, or timestamp header is documented. The library reads none and
requires none. If an observed delivery carries one, record it here — an attempt counter in particular
would be genuinely useful to a caller doing their own deduplication.

---

## Observation procedure (FR-019, SC-011)

Harder than any previous feature in this repository: it needs **inbound** network reachability from
BML UAT, not just outbound calls.

1. Stand up a publicly reachable endpoint that logs the raw request verbatim — method, full header
   set, and body bytes. A tunnel (`cloudflared`, `ngrok`) in front of a local sink is sufficient.
2. Register it, either through the merchant portal or per-transaction via the `webhook` field on
   `transactions.create_v2` (feature `003`, already shipped).
3. Drive a transaction through UAT to a status change.
4. Capture the delivery **verbatim**, redacting nothing but obvious secrets.
5. Record it below, then resolve #1, #2, #3 and #5 against it. Correct the candidate lists in
   `lib/bml_connect/webhooks.rb` and in this document. Leave every candidate still unconfirmed marked
   `[UNVERIFIED]`.
6. While the endpoint is up, answer #4: compare the notification's claimed status against an
   immediate retrieve. If they always agree, say so here and revisit the 3-second default.
7. Add the captured body as a fixture and replay it in a unit test, so the observation is enforced by
   the suite rather than living only in prose.

### Observed delivery

```text
NOT YET OBSERVED — see the release gate in plan.md.

Record here, verbatim:
  request line + method
  full headers
  body bytes
  the retrieve's status at the moment of delivery (for #4)
```

## Verification table

| Item | Status | Blocks |
|---|---|---|
| `GET /public/transactions/{transactionId}` | verified (feature `003`) | — |
| `retries: false` on the verifying retrieve | to be covered by this feature's specs | merge |
| #1 identifier field | **[UNVERIFIED]** | **release** |
| #2 claimed-status field | **[UNVERIFIED]** | release (degrades safely: no re-check) |
| #3 body format | **[UNVERIFIED]** | release (both implemented) |
| #4 read-path lag | **[UNVERIFIED]** | nothing — informs the default |
| #5 delivery metadata | **[UNVERIFIED]** | nothing — read by neither library nor caller |
