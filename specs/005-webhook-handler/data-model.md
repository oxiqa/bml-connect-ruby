# Data Model: Transaction Status Webhook Handler

**Feature**: `005-webhook-handler` | **Date**: 2026-09-27

Two entities, one of which never exists as an object at all. The asymmetry is the design.

## 1. Inbound Notification — input only, never an object

The raw delivery. It is **not** modelled as a class, and that is deliberate (FR-004a): a
`Notification` object with a `state` reader would be read as fact by the first integrator who found
it, which is the failure mode the whole feature exists to prevent.

It exists only as three arguments and two derived locals.

| Part | Type | Trust | Used for |
|---|---|---|---|
| `body` | `String` | none | parsed once; kept for the audit record (scrubbed) |
| `headers` | Hash-like | none | `Content-Type` selection; passed to a caller extractor |
| `presented_secret` | `String` / nil | none | the FR-009a comparison, then discarded |
| *parsed payload* | `Hash` (local) | none | candidate lookup only; never returned |
| *claimed status* | `String` / nil | none | the FR-010 comparison only; never reported as fact |

### Parsing (FR-003, FR-003a)

| Declared media type | Parser |
|---|---|
| `application/json`, `*/*+json` | `JSON.parse` |
| `application/x-www-form-urlencoded` | `URI.decode_www_form` |
| absent or unrecognized | `JSON.parse`, then `URI.decode_www_form` (documented order, R4) |

Rejected as `ValidationError(field: :body)`, with **no remote call**: an empty or whitespace-only
body, invalid UTF-8, a body neither parser accepts, and a parse result that is not a Hash (a bare
JSON array or scalar).

No size or nesting limit is enforced (FR-003c) — the host application owns the socket.

### Header normalization (R5)

Keys are normalized once: `to_s` → `downcase` → `_` becomes `-` → strip a leading `http-`. So
`Content-Type`, `content_type`, `CONTENT_TYPE` and Rack's `HTTP_CONTENT_TYPE` all resolve. First key
wins on collision; a collision is not an error.

### Identifier extraction (FR-002, FR-002a, FR-002b, FR-002c)

```text
extract_id: supplied?  ──yes──▶  extractor.call(payload, headers)
                                   │
                                   ├─ non-blank String  ──▶  use it
                                   └─ nil / blank / other ──▶ raise (NO fallback to candidates)
       │
       └──no──▶  first of transactionId, transaction_id, id
                 whose value is a non-blank String
                   │
                   └─ none  ──▶  raise ValidationError(field: :transaction_id)
```

All three candidates are `[UNVERIFIED]`. A candidate holding a Hash, Array, number, or blank string
is skipped as though absent (R6). A caller extractor is **never** supplemented by the built-in list
(FR-002b) — a caller who knows the true field is never overridden by a guess.

### Claimed status (FR-010c)

First non-blank `String` among `state`, then `status`. Both `[UNVERIFIED]`. Absent or non-`String`
means **no comparable status**, so no re-check — the library does not speculate.

## 2. `BMLConnect::Models::StatusChangeResult` — what `#handle` returns

A read-only value object. Follows `TransactionRecord`'s conventions: whitelisted `#to_h`, whitelisted
`#inspect`, value equality.

| Reader | Type | Source | Notes |
|---|---|---|---|
| `transaction_id` | `String` | payload (FR-002) | the one field taken from the payload and acted on |
| `transaction` | `TransactionRecord` | **BML retrieve** | the authoritative record; feature `003`'s model, unchanged |
| `status` | `String` | `transaction.state` | verbatim, never coerced or mapped (FR-005) |
| `changed_at` | `String` | `transaction.updated` | the time of the change (FR-004) |
| `claimed_status` | `String` / nil | payload, **scrubbed** | diagnostic only; never the reported status |
| `disagreed?` | `Boolean` | comparison | claimed vs authoritative, normalized for comparison only (R7) |
| `rechecked?` | `Boolean` | control flow | whether the second retrieve ran |
| `advisory_http_status` | `Integer` | mapping (R10) | `200` on this object; advice only (FR-016b) |

**Deliberately absent** (FR-004a, SC-008i): `payload`, `body`, `raw`, `headers`, and any reader
returning a payload-shaped Hash. There is no route from a result to an unmasked inbound field. The
absence of the accessor *is* the control — a test asserts the public surface offers no such route.

`#to_h` covers exactly the readers above. `claimed_status` is passed through `Masking.scrub` on
construction, so it is safe in a log line even though nothing should read a status from it.

## 3. Reused unchanged

- **`Models::TransactionRecord`** (feature `003`) — the authoritative record. This feature adds no
  transaction entity and does not redefine `state`. `state` remains a pass-through string with no
  allow-list (FR-005, SC-010).
- **`Audit`** — one masked structured log line per handled notification, through the client's logger.
  No new sink.
- **`Masking`** — the existing PAN detector/scrubber, applied to inbound values (FR-011).

## 4. Configuration added to `Client`

| Option | Default | Purpose |
|---|---|---|
| `webhook_secret` | `nil` | FR-009a. When nil, no secret gate; every delivery costs a retrieve (FR-009c). |
| `webhook_recheck_delay` | `3` | FR-010b. Seconds. `0` disables the re-check. Spent inside the caller's request. |

Both are pulled out of `options:` before Faraday sees them, exactly as `timeout`, `max_retries` and
`retry_backoff` already are. `webhook_secret` is a constructor option supplied from the environment
by the integrator — never a constant, never logged, never on a result (FR-012).

A `webhook_recheck_delay` that is negative or non-numeric raises `ValidationError` at handle time
rather than being coerced.

## 5. Outcome taxonomy

Every row is observably distinguishable (FR-016, SC-008) and every row audits (FR-015).

| Outcome | Returns / raises | Retrieves | Advisory | Kind |
|---|---|---|---|---|
| Accepted, statuses agree or no comparable status | `StatusChangeResult` | 1 | `200` | — |
| Accepted after a re-check | `StatusChangeResult` (`rechecked?`) | 2 | `200` | — |
| Accepted, still disagrees after re-check | `StatusChangeResult` (`disagreed?`) | 2 | `200` | — |
| Malformed / empty / unparseable body | `ValidationError(field: :body)` | **0** | `400` | permanent |
| Secret configured, value absent or wrong | `WebhookRejectedError` | **0** | `401` | permanent |
| No identifier extractable | `ValidationError(field: :transaction_id)` | **0** | `422` | permanent |
| Transaction does not exist | `NotFoundError` | 1 | `422` | permanent |
| BML unreachable / timeout / 5xx / 429 | `AvailabilityError` or `RateLimitError` | 1 | `503` | transient |
| Our API key rejected | `AuthenticationError` | 1 | `503` | transient |
| `webhook_recheck_delay` misconfigured | `ValidationError(field: :webhook_recheck_delay)` | **0** | `500` | transient |
| `actor` contains card-like data | `ValidationError(field: :actor)` | **0** | `500` | transient |

The last two are caller/operator mistakes rather than delivery outcomes, so both advise a transient
status: a redelivery after the mistake is corrected should succeed, and advising permanent would
discard genuine events for the duration of the error.

**Card-like data in the payload is deliberately NOT a row here.** It does not reject the delivery
(FR-011a): the value is masked and handling continues, so the outcome is whichever row the delivery
would have landed on anyway. Adding a row would imply a refusal that does not exist.

A persistent disagreement is a **success** row, not an error (FR-010d) — it is the expected shape of
a replayed or forged delivery.

`404` is never advised. `422` covers the not-found case instead, because `404` from an HTTP endpoint
reads as "no such endpoint" and risks the hook being disabled (R10).

## 6. Advisory status transport

`BMLConnect::Error` gains one accessor:

```ruby
class Error < StandardError
  attr_accessor :advisory_http_status   # nil unless set by the webhook path
end
```

The handler tags each error object before it propagates. No existing error class is replaced, no
existing raise site changes, and every error this feature produces carries the value (FR-016a).
`BMLConnect::WebhookRejectedError < Error` is the single new class (justified in `plan.md`).

## 7. State transitions

None. The library owns no state machine here: a notification triggers a read, and the
`TransactionRecord`'s `state` is BML's, reported verbatim. Handling is side-effect-free beyond the
retrieve(s), the optional wait, logging, and auditing (FR-013).
