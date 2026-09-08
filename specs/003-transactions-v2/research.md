# Phase 0 Research: Transactions V2

**Feature**: `003-transactions-v2` | **Date**: 2026-09-07

## R1. Backward compatibility is the binding constraint

- **Decision**: Add `create_v2`, `retrieve`, `update`, `capture`, `cancel`. Change nothing about
  `create`, `get`, `list`.
- **Rationale**: `msgowl/website` calls this gem at six sites and reads `resp.status`,
  `resp.body[:id]`, `resp.body[:url]`, `resp.body[:state]`, `resp.body[:expires]`,
  `resp.body[:merchantId]` and `resp.body[:paddedCardNumber]`. Any change to the return type
  breaks all of them at once, in a payment path.
- **Alternatives considered**: Proxy `create` to v2 transparently (rejected — v2's response shape
  differs and its payment-URL field is unverified, so callers reading `body[:url]` would get nil
  and send cardholders to a blank page: a silent failure in checkout); a major version bump that
  changes everything (rejected — out of scope, and the migration should not force a rewrite of a
  working integration).

## R2. Keeping an undocumented endpoint alive

- **Decision**: Keep `POST public/transactions` on the v1 `create`; mark it deprecated in
  documentation and with a one-time runtime warning.
- **Rationale**: It is absent from `Connect-API.json` but demonstrably live — UAT answers it with
  the BML application's `PP-C-004`, not the gateway's `Forbidden`. Removing a working payment path
  because it is undocumented would take production down to satisfy a principle. Recording the
  exception openly (in the contract, the plan's Complexity Tracking, and the conformance test's
  allow-list) satisfies Constitution III's intent, which is that unverified things be *visible*,
  not that they be deleted.
- **Risk**: if BML retires it, `create` breaks. The deprecation warning gives callers a migration
  target before that happens.

## R3. Signature — keep on v1, omit on v2

- **Decision**: Keep computing and sending `signature` on v1. Send none on v2.
- **Rationale**: `signature` appears **zero** times in the document, yet v1 works today with it.
  Two possibilities — v2 ignores it, or v2 rejects it — and the cost of guessing wrong differs:
  sending an unexpected field is more likely to be rejected outright than omitting one is to be
  silently mis-signed. Omit on v2, observe, then decide (FR-012).
- **Alternatives considered**: Send it on v2 for symmetry (rejected — unjustified by the
  contract); strip it from v1 too (rejected — v1 works today; changing a working money path on
  the strength of its absence from a document that omits the whole endpoint is reckless).

## R4. No automatic retry on create

- **Decision**: Create and capture are never retried automatically. Retrieve, list, update and
  cancel are.
- **Rationale**: Retry on a charging call is safe **only** with a server-side idempotency key.
  None is documented for `/public/v2/transactions`. The retired gem retried create on the basis
  of an idempotency guarantee it had invented for itself — a double-charge risk built on an
  assumption. A caller who times out reconciles by `localId` instead.
- **Alternatives considered**: Retry with `localId` as a de-facto idempotency key (rejected —
  nothing in the document says BML deduplicates on `localId`; that is the same class of
  assumption); retry only on connection-refused (rejected — a refused connection after the
  request was written is indistinguishable from one before).

## R5. Amount type — reject rather than coerce

- **Decision**: `create_v2` requires a positive Integer in minor units and rejects Float and
  String.
- **Rationale**: `100.0` is ambiguous — MVR 100.00 in minor units would be `10000`, but a caller
  may well mean `100`. Guessing on a money field is unacceptable, and a loud local error costs a
  developer one minute while a silent 100× error costs real money. The website's existing string
  form stays valid on the untouched v1 `create`.

## R6. Which create variants to implement

- **Decision**: Implement variants 3 and 4 (direct amount, with `customerId` or an inline
  `customer`). Reject variants 1, 2 and 5 by name.
- **Rationale**: 1 and 2 need the shops/products/order-fields surface, out of scope for this gem.
  5 needs an `fxQuoteId` from a quote flow documented nowhere in the file, so it could not be
  implemented correctly even if wanted. Rejecting them locally with a named error is better than
  forwarding a body BML will refuse with an opaque message (Constitution V).

## R7. The payment-URL field is a production blocker

- **Decision**: `#payment_url` reads the first present of `url`, `redirectUrl`, `qr.url` and
  **raises** if none is present. The item is flagged as blocking production use of v2 create.
- **Rationale**: The v1 response carries `url`; the v2 schema does not list it. `redirectUrl` is
  also a request field and is probably echoed rather than being the payment link. Without the
  right field there is nowhere to send the cardholder. Raising makes the failure loud in
  development; returning nil would surface as a blank redirect in checkout.
- **Resolution path**: one UAT create settles it (T021).

## R8. `state` is passed through, never normalized

- **Decision**: Expose BML's `state` string verbatim.
- **Rationale**: The document declares no enum. Production code branches on `CONFIRMED`,
  `CANCELLED`, `FAILED`, observed from v1. The retired gem normalized to
  `pending`/`succeeded`/`failed`/`cancelled` via a 20-entry alias table it invented — which would
  silently break every existing `case` statement in the website. Passing through is both simpler
  and safer.

## R9. Class naming collision

- **Decision**: New response object is `Models::TransactionRecord`; the existing
  `Models::Transaction` request builder is untouched.
- **Rationale**: The good name is taken by a released class that `create` depends on. An ugly but
  non-breaking name beats a clean but breaking rename. Queued for reconciliation in `v1.0.0`.

## R10. Tokenization is asynchronous

- **Decision**: `create_v2` never reports that a card was stored. It reports the transaction only.
- **Rationale**: The token exists only after the cardholder completes payment on the hosted page,
  which happens out of band. Any claim at create time would be a guess. Callers confirm via
  `client.tokens.list(customer_id)` (feature `002`).

## R11. A latent Ruby 2.7 bug in the code this feature keeps alive

- **Finding**: `BMLConnect::Models::Transaction#initialize` builds its error message with
  `REQUIRED_FIELDS.join(', ')`, where `REQUIRED_FIELDS` is a `Set`. **`Set#join` was added in
  Ruby 3.0.** The gemspec declares `required_ruby_version >= 2.3.0`.
- **Effect**: on any Ruby below 3.0, a `create` call missing `amount` or `currency` raises
  `NoMethodError: undefined method 'join' for #<Set: {:amount, :currency}>` instead of the
  intended `ArgumentError` naming the missing fields. The gem's own `spec/transaction_spec.rb:4`
  fails on Ruby 2.7 for this reason, and has presumably been failing since the Set was introduced
  — CI evidently runs a Ruby where it passes.
- **Why it matters here**: `msgowl/website` runs Ruby 2.7.4. A malformed transaction create in
  production surfaces as a confusing `NoMethodError` from deep inside the gem rather than a clear
  validation error. Feature `003` explicitly keeps this v1 `create` alive (FR-010), so the bug
  stays live unless fixed.
- **Decision**: fix it in this feature as a one-line change — `REQUIRED_FIELDS.to_a.join(', ')`.
  This is a **bug fix, not a behavior change**: it makes the code do what its own test already
  asserts, so it does not violate the backward-compatibility constraint. Scheduled as T035.
- **Alternatives considered**: Raise the gemspec floor to 3.0 (rejected — the website is on 2.7
  and this would be a breaking packaging change to fix a typo); leave it (rejected — a broken
  validation path in a payment call, in code this feature deliberately preserves).
