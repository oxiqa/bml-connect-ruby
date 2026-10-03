# Contract: Library API — Transaction Status Webhook Handler

**Feature**: `005-webhook-handler` | **Consumer**: integrators using the `bml_connect` gem.

## Reaching the resource

```ruby
client.webhooks.handle(body: …, headers: …)
```

Memoized on the client like `#customers` and `#tokens`. **No web-framework dependency is added**
(FR-001, SC-012): the gem is handed a body and headers and returns a value object. It does not own a
route, does not read the request, and does not write the response.

## `handle(body:, headers: {}, presented_secret: nil, extract_id: nil, actor: nil)`

| Keyword | Required | Type | Purpose |
|---|---|---|---|
| `body` | yes | `String` | the raw request body |
| `headers` | no | Hash-like | used for `Content-Type`; passed to `extract_id` |
| `presented_secret` | only when a secret is configured | `String` | the value **you** extracted from the delivery (FR-009a) |
| `extract_id` | no | callable | overrides the built-in candidate list outright (FR-002b) |
| `actor` | no | `String` | who/what is handling, for the audit record's `who` |

Returns `BMLConnect::Models::StatusChangeResult`. Raises on every other outcome.

### The one thing to understand

**The status you act on always comes from a fresh retrieve, never from the payload.** The payload is
an untrusted hint that *something* changed; it answers "look at this one", and BML answers "and here
is what is true about it". There is no option, flag, or mode that skips the retrieve (FR-007,
SC-004) — a forged "payment confirmed" cannot cause you to ship goods.

```ruby
result = client.webhooks.handle(body: request.body.read, headers: request.env)

result.status          # ← authoritative, from BML
result.claimed_status   # ← diagnostic only; never act on this
result.transaction      # ← BMLConnect::Models::TransactionRecord
```

## The result

| Reader | Type | Notes |
|---|---|---|
| `transaction_id` | `String` | the one field read from the payload and acted on |
| `transaction` | `TransactionRecord` | the authoritative record (feature `003`) |
| `status` | `String` | `transaction.state`, verbatim — never coerced or mapped |
| `changed_at` | `String` | `transaction.updated` |
| `claimed_status` | `String` / nil | the payload's claim, masked. **Diagnostic only.** |
| `disagreed?` | `Boolean` | the claim disagreed with the authoritative status |
| `rechecked?` | `Boolean` | a second retrieve ran |
| `advisory_http_status` | `Integer` | what to return to BML — advice, not control |

There is deliberately **no** `result.payload`, `result.body`, or `result.headers`. A payload-shaped
object on the result would invite `result.payload[:state]`, which is a status read from an untrusted
source, and would defeat the feature (FR-004a, SC-008i). The raw body is available where forensic
detail belongs: in the audit record.

## An unrecognized status is not an error

```ruby
result.status    # => "SOME_STATE_THIS_GEM_HAS_NEVER_SEEN"
```

The published contract enumerates no transaction states, so this library ships no allow-list and will
never coerce, drop, or reject a status it does not recognize (FR-005, SC-010). Treat
`result.status` as **current-as-of-retrieve**, not as final.

## Errors, and the advisory status

Every error carries `advisory_http_status` (FR-016a). It is **advice**: the library never writes a
response and does not require you to honor it (FR-016b).

| Outcome | Raises | Retrieves | Advisory | Redelivery |
|---|---|---|---|---|
| Accepted | — returns a result | 1–2 | `200` | — |
| Malformed / empty / unparseable body | `ValidationError(field: :body)` | **0** | `400` | permanent — do not redeliver |
| Secret absent or wrong | `WebhookRejectedError` | **0** | `401` | permanent |
| No identifier extractable | `ValidationError(field: :transaction_id)` | **0** | `422` | permanent |
| Transaction does not exist | `NotFoundError` | 1 | `422` | permanent |
| BML unreachable / timeout / 5xx | `AvailabilityError` | 1 | `503` | **transient — please redeliver** |
| Rate limited | `RateLimitError` | 1 | `503` | transient |
| Our API key rejected | `AuthenticationError` | 1 | `503` | transient |

**`404` is never advised.** A not-found transaction gets `422` instead: `404` from an HTTP endpoint
reads to a delivery system as "no such endpoint", and a sender that concludes your hook URL is gone
may stop delivering — turning one forged identifier into an outage for every genuine notification
after it. `422` says "received, unusable", which is the truth.

**A rejected credential advises transient**, even though redelivery cannot help until an operator
fixes the key. Advising permanent would discard genuine events for the whole duration of the
misconfiguration.

A persistent disagreement is **not** an error (FR-010d): it returns a result with `disagreed?` true.
That is the expected shape of a replayed or forged delivery.

## The verify-then-recheck sequence

```text
parse body ─▶ secret check ─▶ retrieve #1 ─▶ compare claimed vs authoritative
   │              │               │                    │
  raise         raise           raise          agree / no claim ─▶ return (1 retrieve)
 (0 calls)    (0 calls)       (1 call)                 │
                                              disagree + delay > 0
                                                       │
                                            wait ─▶ retrieve #2 ─▶ return (2 retrieves)
```

At most **two** retrieves per notification, neither auto-retried, no matter what the payload claims
(FR-009, FR-010a). No third call, no loop, no unbounded wait.

## Configuration

```ruby
client = BMLConnect::Client.new(
  api_key: ENV.fetch("BML_API_KEY"),
  mode:    "sandbox",
  options: {
    webhook_secret:        ENV["BML_WEBHOOK_SECRET"],  # optional
    webhook_recheck_delay: 3                            # seconds; 0 disables the re-check
  }
)
```

### `webhook_secret` — gates spend, not trust

An optional shared secret. When configured, a delivery whose presented value is absent or wrong is
rejected **before any retrieve is spent** (FR-009a). It is a cost control, and nothing more:

- A matching secret does **not** cause the payload to be believed.
- A matching secret does **not** skip the verifying retrieve.
- The same genuine notification reports an identical status with the secret and without it (FR-009b,
  SC-008f).

**You extract it; the library only compares it.** The library never guesses where the secret travels
— not from a header, not from a query parameter, not from a path segment, and it never asks for the
request URL (FR-009e). BML controls the callback's headers, so in practice a secret can only ride in
the URL you registered; that is your extraction, because a default location would be an invention.

```ruby
# secret in the registered hook URL: https://you.example/bml?t=SECRET
client.webhooks.handle(
  body:             request.body.read,
  headers:          request.env,
  presented_secret: request.params["t"]
)
```

Comparison is constant-time (SHA-256 digests compared by fixed-length XOR — research R9). The secret
never appears in a log, an audit record, an error message, or on a result (FR-012).

**With no secret configured, every inbound request costs a real retrieve** (FR-009c). Your endpoint
is public; protecting it is yours.

### `webhook_recheck_delay` — spent inside your request

Default **3 seconds**. When the payload's claimed status disagrees with the first retrieve, the
library waits this long and retrieves once more, then reports whatever the second retrieve says —
even if it still disagrees (FR-010).

**If your endpoint's response deadline is at or below 3 seconds, set this to `0`.** A sender that
times out will redeliver, converting a latency problem into a replay problem. With the delay at zero
the library performs exactly one retrieve, reports the first result, and still records the
disagreement (SC-008b).

Note the cost lands on every disagreeing delivery, including every **replay** — which disagrees
legitimately and gains nothing from the wait.

## Overriding identifier extraction

The built-in candidates are `transactionId`, `transaction_id`, `id` — top-level keys only, all
`[UNVERIFIED]` until a real delivery confirms one (FR-002a). If you have observed your own deliveries
and know the real field, say so and the library will not second-guess you:

```ruby
client.webhooks.handle(
  body:       body,
  headers:    headers,
  extract_id: ->(payload, headers) { payload.dig(:transaction, :id) }
)
```

The callable receives the **parsed payload and the normalized headers** — headers included because an
undocumented callback may well carry the identifier there, and a body-only hook would leave exactly
that merchant blocked (FR-002c). It is never handed the raw body.

Return the identifier, or `nil` for "not found" — which raises the same
`ValidationError(field: :transaction_id)` as an exhausted candidate list, with **no** remote call and
no guessed identifier. When you supply an extractor the built-in list is **not** consulted at all
(FR-002b).

## What this library does not do

| Not done | Why | Yours to do |
|---|---|---|
| Deduplicate deliveries | The gem owns no datastore | Key on `result.transaction_id` |
| Guarantee ordering | Nothing in the contract promises it | Two deliveries in either order both report current truth |
| Register the hook URL | Out of scope | Merchant portal, or `webhook:` on `create_v2` |
| Bound the request size | The gem does not own the socket (FR-003c) | Bound it at your web server |
| Route, authenticate, or respond | FR-001 | Your endpoint |
| Enumerate transaction states | The contract defines none (FR-005) | Compare `result.status` to what BML tells you |

Handling the same notification twice produces equivalent results and no side effect beyond the
retrieve (FR-013, FR-014).

## Header naming

Headers are normalized for you: `downcase`, `_` → `-`, and a leading `http-` stripped. So
`Content-Type`, `content_type`, `CONTENT_TYPE` and Rack's `HTTP_CONTENT_TYPE` all resolve — pass
`request.headers` (Rails), `request.env` (Rack), or a plain hash.

## Auditing

Every handled notification emits one masked structured audit line through the client's logger,
including rejections (FR-015) — a rejected delivery is the observable signature of a forgery attempt,
and an operator needs to see it. The record carries the outcome, the transaction id where known, the
claimed status, whether it disagreed, whether a re-check ran, the advisory status, and the scrubbed
raw body. It never carries card data or either secret value.

## Change to an existing method

`Transactions#retrieve` gains an optional keyword:

```ruby
retrieve(id, actor: nil, retries: true)
```

The default preserves released behavior exactly. The webhook handler passes `retries: false`, because
FR-009's two-retrieve cap counts HTTP calls — with retry left on, one notification during a BML
wobble could make six requests (research R3).
