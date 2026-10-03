# Phase 0 Research: Transaction Status Webhook Handler

**Feature**: `005-webhook-handler` | **Date**: 2026-09-27

Fourteen decisions. R3, R6 and R9 are the ones that changed the design; the rest record choices the
spec's clarifications implied but did not pin to this codebase.

## R1. Where the handler lives: a new resource, `client.webhooks`

- **Decision**: `BMLConnect::Webhooks`, memoized on the client as `#webhooks`, exactly like
  `#customers` and `#tokens`. One public method, `#handle`. **Not** a `Resource` subclass — see the
  correction in R2.
- **Rationale**: It matches the shape every other resource in this gem already has, so the
  integrator's mental model does not change.
- **It issues no HTTP of its own.** `Resource#request` is inherited but unused: the verifying
  retrieve goes through `client.transactions.retrieve`, so the library has exactly one
  implementation of a transaction read and the webhook path inherits its status→error mapping.
- **Alternatives considered**: A bare module function `BMLConnect::Webhooks.handle(client, ...)`
  (rejected — inconsistent with every other resource, and awkward to configure); a
  `WebhookHandler` class the integrator instantiates themselves (rejected — the secret and the
  re-check delay belong with the client's other configuration).

## R2. Not a `Resource` at all — corrected during implementation

- **Original decision**: subclass `Resource` for its shared helpers while never calling `#request`.
- **Corrected decision**: `Webhooks` does not inherit from anything. Two findings forced it:
  1. **There were no helpers to inherit.** `blank?`, `symbolize`, `screen_for_pan!` and `audit` are
     private to `Transactions` (and `Customers`), not to `Resource`. `Resource` carries transport
     only. The handler defines the three small helpers it actually needs and calls `Audit` and
     `Masking` directly, as module functions.
  2. **`Resource#handle` would have collided.** `Resource#handle(response)` is a private method that
     `#request` calls to map a Faraday response. A subclass defining a public
     `#handle(body:, headers:, ...)` overrides it, so any inherited transport path would have invoked
     the public method with a Faraday response and raised `ArgumentError`. Renaming the public method
     was not an option — `client.webhooks.handle` is the documented API.
- **Consequence**: FR-009's cap is structurally safe rather than safe-by-discipline. The handler has
  no retry machinery to accidentally reach for; the only HTTP it can cause is
  `client.transactions.retrieve(id, retries: false)`.

## R3. `transactions.retrieve` auto-retries today, and that breaks FR-009

- **Finding**: `Transactions#retrieve` calls `request(:get, …)` with the default `retries: true`, so
  it makes up to `client.max_retries + 1` HTTP calls (default 3). Its own RDoc says "MAY retry
  (FR-016)" — correct for feature `003`, wrong for this one.
- **Consequence if unaddressed**: A single notification arriving while BML is flaky would produce up
  to **six** HTTP requests (3 per retrieve × 2 retrieves), and SC-008d — "no inbound request causes
  more than two retrieves" — would fail against a live-ish failure mode while passing every
  happy-path stub. A forger could use a flaky BML to triple their amplification.
- **Decision**: Add an additive keyword: `retrieve(id, actor: nil, retries: true)`, forwarded to
  `request`. The webhook handler calls `retrieve(id, retries: false)`.
- **Rationale**: Backward compatible (the default preserves released behavior for feature `003`
  callers), keeps one implementation of the transaction read, and puts the retry decision at the
  call site where the requirement lives. FR-009 says the verifying retrieve "MUST NOT be
  auto-retried on transport failure" — this is how that becomes true rather than aspirational.
- **Alternatives considered**: Reimplement the retrieve inside `Webhooks` with `retries: false`
  (rejected — duplicates transport, and the spec's own assumptions say this feature is "a consumer
  of it, not a reimplementation"); temporarily set `client.max_retries = 0` around the call
  (rejected — mutates shared state, not thread-safe, and would silently affect concurrent
  operations on the same client); give `Webhooks` its own Faraday connection (rejected — a second
  connection with its own headers is exactly the divergence Principle III warns about).
- **Also note**: `retries: false` routes through `Resource#single_attempt`, which already converts a
  `Faraday::TimeoutError`/`ConnectionFailed` into `AvailabilityError` immediately. That is precisely
  the FR-008 behavior this feature wants, already written and tested.

## R4. Body parsing: JSON then form-encoded, stdlib only

- **Decision**: Select by the delivery's `Content-Type` media type (the part before `;`):
  `application/json` or any `+json` suffix → `JSON.parse`; `application/x-www-form-urlencoded` →
  `URI.decode_www_form`. Absent or unrecognized → attempt **JSON first, then form-encoded**, and
  reject when neither parses. An empty or whitespace-only body is rejected before either attempt.
- **Rationale**: `json` and `uri` are stdlib, so FR-001's no-new-dependency constraint and SC-012
  hold. JSON goes first in the fallback because `URI.decode_www_form` is far too permissive — it
  will "successfully" parse `{"id":"x"}` into a single garbage key rather than failing, so trying it
  first would mask every JSON payload. JSON, by contrast, raises cleanly on a form body.
- **Charset**: the body is read as UTF-8 and a body with invalid UTF-8 bytes is rejected as
  malformed rather than silently scrubbed.
- **Alternatives considered**: JSON only (rejected in clarification — a form-encoded callback would
  fail totally, and nothing in the published document rules it out); content-type-agnostic sniffing
  on every delivery (rejected — FR-003a forbids treating "it happened to parse" as evidence);
  a caller-supplied parser hook (rejected as speculative under Principle V — `extract_id:` already
  covers the caller who knows their payload).
- **Depth/size**: none enforced, per FR-003c. `JSON.parse` has no nesting limit by default and that
  is the documented, accepted position: the host application owns the socket.

## R5. Header lookup must survive Rack's `HTTP_*` naming

- **Decision**: Normalize every inbound header key once: `to_s`, `downcase`, `_` → `-`, then strip a
  leading `http-`. So `Content-Type`, `content_type`, `CONTENT_TYPE` and `HTTP_CONTENT_TYPE` all
  resolve to `content-type`. Duplicate keys after normalization: first wins, and the collision is
  not an error.
- **Rationale**: Integrators will pass `request.headers` (Rails), `request.env` (Rack), or a plain
  hash. Without this, the `Content-Type` selection of R4 silently misses on a Rack `env` and every
  delivery falls into the fallback path — working, but by accident. This is a documented, tested
  normalization over a well-known convention, not a security fallback.
- **Alternatives considered**: Require the caller to pass canonical headers (rejected — an easy
  integration bug that produces confusing behavior rather than an error); depend on
  `Rack::Utils` (rejected — adds a web-framework dependency, forbidden by FR-001).

## R6. The candidate field lists — short, ordered, and each citable

Every entry below is `[UNVERIFIED]` until a real delivery is observed (FR-002a, FR-003b).

**Transaction identifier** (FR-002), in resolution order:

| Candidate | Why it is on the list |
|---|---|
| `transactionId` | The exact name BML uses for this value everywhere it *is* documented: the path parameter of `/public/transactions/{transactionId}` and the `transactionId` field of the charge body. The strongest available inference. |
| `transaction_id` | The snake_case spelling of the same name. Costs nothing and covers a callback emitted by a different service than the REST API. |
| `id` | The field name carried by the `Transaction` schema itself, so a payload that embeds a transaction record (rather than naming one) would use it. |

- **Top-level keys only.** A nested payload (`{"transaction": {"id": …}}`) is exactly what
  `extract_id:` exists for. Walking arbitrary nesting would mean inventing a search strategy over a
  document that describes no payload at all — Principle V.
- **Value must be a non-blank `String`.** A candidate present but holding a Hash, Array, number, or
  blank string is skipped as though absent, and if no candidate yields a `String` the library raises
  (FR-002). This is explicit and documented, not a silent coercion — an id we made up out of an
  integer would fail at the retrieve anyway, one HTTP call later.
- **`localId` is deliberately excluded.** It is the *merchant's* reference, not BML's transaction id;
  retrieving by it would 404 and land on the not-found path, which FR-016d advises permanently. A
  plausible-looking candidate that produces a confidently wrong outcome is worse than no candidate.

**Claimed status** (FR-010c), in resolution order: `state`, then `status`.

- `state` is the field name on the `Transaction` schema, so it is the documented spelling.
- `status` is the common alternative in callback payloads generally.
- Absent or non-`String` → no comparable status, so **no re-check** (FR-010c). The library does not
  speculate.

## R7. Status comparison: normalized for the comparison only, never for reporting

- **Decision**: Compare `claimed.strip.upcase` against `authoritative.strip.upcase`. Report both
  verbatim; the normalization exists only to decide whether they disagree.
- **Rationale**: The two states observable in the published document are `INITIATED` and
  `QR_CODE_GENERATED` — uppercase. A callback spelling one of them `initiated` would otherwise be
  read as a disagreement and pay the 3-second re-check for nothing, on every delivery. Normalizing
  the *comparison* is safe; normalizing the *reported value* would violate FR-005's verbatim
  pass-through.
- **Alternatives considered**: Exact byte comparison (rejected — spurious re-checks, pure latency
  cost); normalizing the reported status too (rejected — FR-005, SC-007).

## R8. The re-check: injectable wait, default 3 seconds

- **Decision**: `client` gains `webhook_recheck_delay` (default `3`, `0` disables), pulled from
  `options:` like `timeout`/`max_retries`/`retry_backoff` already are. The handler's wait goes
  through one private method so tests replace it; **no test sleeps for real**.
- **Rationale**: SC-008b asserts "no added latency" with the delay at zero and SC-008m asserts the
  default is 3 — both need the wait observable without a 3-second test suite. A negative or
  non-numeric configured delay is rejected at handle time as a configuration error rather than
  coerced.
- **Ordering**: the re-check fires only when (a) a comparable claimed status exists, (b) it
  disagrees, and (c) the delay is greater than zero. With the delay at zero the library performs
  exactly one retrieve and reports the first result, still recording the disagreement (FR-010d).

## R9. Constant-time comparison: SHA-256 + fixed-length XOR

- **Finding**: `OpenSSL.fixed_length_secure_compare` is **not available** on this toolchain —
  verified directly on Ruby 2.7.4 (`OpenSSL.respond_to?(:fixed_length_secure_compare) # => false`).
  `Rack::Utils.secure_compare` is out of reach (FR-001 forbids the dependency).
- **Decision**: Digest both values with `Digest::SHA256.digest`, then compare the two 32-byte strings
  with a XOR-accumulate loop that always runs all 32 iterations.
- **Rationale**: Digesting first makes both operands a fixed 32 bytes, so neither the comparison time
  nor the loop count leaks the secret's length — the weakness a naive length check introduces. Pure
  stdlib (`digest`), works on 2.7, and is a few lines that can be read and reviewed in full.
- **Presented value absent** (`nil` or blank) → reject immediately without digesting. This leaks only
  "something was presented or not", which the caller already knows.
- **Alternatives considered**: `==` (rejected — FR-009d); `OpenSSL.secure_compare` behind a
  `respond_to?` guard (rejected — a security control that silently changes shape by runtime is worse
  than one that always behaves the same way); HMAC over the body (rejected — that is a *signature*
  scheme, and inventing one BML does not document would be Principle V's exact failure).

## R10. The advisory status mapping — and why not `404`

- **Decision**:

| Outcome | Advisory | Kind |
|---|---|---|
| Accepted, authoritative record returned | `200` | — |
| Malformed / empty / unparseable body | `400` | permanent |
| Secret configured, presented value absent or wrong | `401` | permanent |
| No transaction identifier extractable | `422` | permanent |
| BML reports the transaction does not exist | `422` | permanent |
| BML unreachable, timed out, 5xx, or rate-limited | `503` | transient |
| Our API key rejected by BML (401/403 on the retrieve) | `503` | transient |
| Anything unexpected | `500` | transient |

- **Why a not-found transaction advises `422` and not `404`**: FR-016d requires a permanent status,
  and `404` is permanent — but `404` from an HTTP endpoint means "no such endpoint" to almost every
  delivery system, and a sender that concludes the hook URL is gone may stop delivering or disable
  it. That converts a forged identifier into an outage for every genuine notification after it.
  `422` says "I received this and it is unusable", which is the truth, and cannot be misread as the
  endpoint being absent.
- **Why a rejected credential advises a transient `503`**: it is our misconfiguration, not the
  sender's fault. Advising permanent would discard genuine events for as long as the key is wrong;
  advising transient means they are redelivered once an operator fixes it. FR-016c only mandates
  transient for an unreachable BML, so this is an additional judgment, recorded here for review.
- **Carrying the value**: `BMLConnect::Error` gains an `advisory_http_status` accessor (nil by
  default), and the handler tags each error object before it propagates. No error class is replaced
  and no existing raise site changes. See R11.
- **Alternatives considered**: New parallel error classes per advisory status (rejected — a
  combinatorial explosion, and it would break callers matching on `AvailabilityError`); returning a
  result object instead of raising for failures (rejected — FR-003/FR-008 say raise, and a result
  for a rejected forgery is exactly the "something that could be mistaken for an event" US1-2
  forbids).

## R11. Distinguishing the outcomes (FR-016, SC-008)

- **Decision**:

| Outcome | Class | Distinguishing detail |
|---|---|---|
| Malformed body | `ValidationError` | `field: :body` |
| Unextractable identifier | `ValidationError` | `field: :transaction_id` |
| Failed secret check | `WebhookRejectedError` (**new**) | its own class |
| Transaction not found | `NotFoundError` | existing, from the retrieve |
| Transport failure | `AvailabilityError` | existing, from the retrieve |
| Accepted | — | returns `StatusChangeResult` |

- **Rationale for the one new class**: a failed secret check must be distinguishable from a malformed
  body (FR-016, SC-008), and distinguishing a *security rejection* only by a `field:` value is too
  weak for something operators alert on. Everything else reuses the existing hierarchy.

## R12. The result object exposes no payload (FR-004a, SC-008i)

- **Decision**: `Models::StatusChangeResult` with readers `transaction_id`, `transaction`, `status`,
  `claimed_status`, `disagreed?`, `rechecked?`, `advisory_http_status`. No `payload`, no `body`, no
  `raw`, no `to_h` of anything payload-shaped. `claimed_status` is passed through `Masking.scrub`.
  `#inspect` and `#to_h` are whitelisted, following `TransactionRecord`.
- **Rationale**: FR-004a's reasoning is behavioral, not cosmetic — a payload-shaped object on the
  result invites `result.payload[:state]`, which is a status read from an untrusted source and
  defeats the entire feature. The absence of the accessor is the control.
- **The raw body still reaches the audit record** (FR-004b, FR-015), scrubbed, which is where
  forensic detail belongs.

## R13. Auditing every outcome, including rejections

- **Decision**: One `Audit.emit_event` call per handled notification, with `outcome: :success` or
  `:rejected`, and a `subject` carrying the transaction id where known, the claimed status, the
  disagreement flag, whether a re-check ran, the advisory status, and the scrubbed raw body.
- **Rationale**: `Audit.emit_event` already scrubs the whole serialized line through
  `Masking.scrub`, so the raw body is safe to include. FR-015 requires rejections to audit too,
  which is broader than the constitution's "state-changing operations" floor — deliberately, since a
  rejected delivery is the observable signature of a forgery attempt.
- **The secret never enters the record.** Neither the configured value nor the presented one is put
  in `subject`; only whether the check passed. `Masking.scrub` catches PANs, not secrets, so this is
  enforced by not writing them rather than by filtering them.

## R15. Two defects the specs caught during implementation

Both were found by tests written before the code, which is the whole argument for Principle II.

- **BML's own error text was reaching exception messages unmasked.** `Resource#map_error` builds a
  message from the upstream response body, so a card-like value in a BML error body would have landed
  in an exception message and any log that printed it — a direct FR-011/Constitution I breach, and one
  that had nothing to do with this feature's own code. **Fixed at the source**: `map_error` now passes
  the extracted message through `Masking.scrub`, so every resource benefits, not just this one.
- **An invalid-UTF-8 body took down its own audit record.** The parser correctly rejects such a body
  as malformed, but the rejection path then writes the raw body into the audit record, and
  `JSON.generate` raised `JSON::GeneratorError` on the illegal bytes — so the error a caller saw was a
  generator crash rather than the descriptive validation error FR-003 promises, and the delivery most
  worth recording produced no record. **Fixed** with an encoding scrub (`String#scrub`) applied to the
  body before it enters the audit subject, on top of the existing PAN masking.

## R14. What this feature deliberately does not build

- **Registration.** `POST` and `DELETE /public/webhooks` are documented in
  `reference/Connect-API.json` and implementable, and are out of scope by clarification. Noted here
  so a future reader knows the omission was a decision.
- **Deduplication, queuing, persistence.** No datastore (FR-014). The identifier is surfaced so the
  caller can do it.
- **Any state enumeration.** FR-005/SC-010. The published contract defines none.
- **A body-size or nesting limit.** FR-003c, by clarification: the library does not own the socket.
- **Thread-safety note**: the handler holds no mutable state; the wait is per-call and the
  configuration is read, never written. Two threads handling two deliveries on one client do not
  interact.

## The one open unknown

Which field carries the transaction identifier (FR-019, SC-011). Not resolvable from
`reference/Connect-API.json` — it documents the callback nowhere. It is a **release** gate, not a
merge gate: a wrong candidate fails loudly at extraction or at the retrieve, and `extract_id:` lets
a merchant who has observed their own deliveries bypass the list entirely. See
[contracts/bml-remote.md](./contracts/bml-remote.md) for the observation procedure.
