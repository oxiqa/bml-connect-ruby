# Migration: `bml_tokenization` → `bml-connect-ruby`

**Date**: 2026-09-07
**Decision**: Tokenization work moves into this gem. The separate `bml_tokenization` gem is
retired before release and MUST NOT be published.

## Why

`bml_tokenization` was specified and implemented against an **assumed** BML API contract. Its
own contract documents said so — *"the platform is the source of truth for exact paths, field
names… the shapes below are the expected contract"* — and every one of its tests was a WebMock
stub of those assumed shapes. Nothing in it had ever reached Bank of Maldives.

When BML's published OpenAPI document (`reference/Connect-API.json`) was obtained, the
assumptions turned out to be wrong at every level:

### Paths

Probing UAT with a deliberate garbage path as a control showed the gem's routes were
indistinguishable from routes that do not exist:

| Probe | UAT response |
|---|---|
| `/definitely-not-a-real-route` (control) | `403 {"message":"Forbidden"}` |
| `/customers` | `403 {"message":"Forbidden"}` |
| `/cards-on-file` | `403 {"message":"Forbidden"}` |
| `/tokens` | `403 {"message":"Forbidden"}` |

The published spec confirms it. Correct mapping:

| `bml_tokenization` assumed | Actual (`Connect-API.json`) |
|---|---|
| `POST /customers` | `POST /public-customers` |
| `GET /customers/{id}` · `PUT` | `GET` · `PATCH` · `DELETE /public-customers/{customerId}` |
| `GET /cards-on-file` | `GET /public-customers/{customerId}/tokens` |
| `POST /tokens` (exchange a `card_handle`) | **does not exist** — see *Flow* below |
| `POST /tokens/{ref}/revoke` | `DELETE /public-customers/{customerId}/tokens/{tokenId}` |
| `POST /transactions` | `POST /public/v2/transactions` |
| `GET /transactions/{id}` | `GET /public/transactions/{transactionId}` |
| `GET /transactions` (list) | **not documented** |

### Authentication

The gem sent `Authorization: Bearer <key>` plus an `X-App-Id` header. The spec's
`securitySchemes` is `type: apiKey, in: header, name: Authorization` — the raw key, no scheme
prefix. The strings `Bearer`, `X-App-Id`, and `appId` appear **zero** times in the document.
This gem's existing `BMLConnect::Client` already does it correctly.

### Data model

The gem required `first_name` / `last_name` / `email`. BML requires a single `name` plus
`email`, alongside `billingEmail`, `billingAddress1`, `billingCity`, `billingCountry`,
`billingPostCode`, `customerGroup`, `invoicePrefix`, `taxInformation`, and `taxId`.

### Flow

The deepest error. `bml_tokenization` modelled tokenization as *capture a card → receive a
single-use `card_handle` → exchange it at `POST /tokens` for a token*. **No such flow exists.**

In BML Connect a token is a **side effect of a transaction**. The caller sets
`tokenizationDetails` on `POST /public/v2/transactions`:

```json
{
  "tokenize": true,
  "paymentType": "RECURRING",
  "recurringFrequency": "MONTHLY",
  "expiryDate": "2027-01-01"
}
```

The cardholder completes that transaction on BML's hosted page, and the resulting token is
then listed under the customer. Later charges are a **two-step** flow — create a transaction,
then `POST /public-customers/charge` with `{customerId, transactionId, tokenId}`. The gem's
"pass `card_reference` to `create` and it charges server-side in one call" does not exist
either.

## Feature realignment

The four old features did not survive contact with the real API. `002-card-on-file-endpoints`
and `004-tokenization-endpoints` described the same underlying resource — BML has one stored-card
concept, the customer token — and nothing covered the charge flow at all.

| Old (`bml_tokenization`) | New (this repo) |
|---|---|
| `001-customer-api-endpoints` | `001-customers-endpoints` |
| `002-card-on-file-endpoints` | merged → `002-stored-card-tokens` |
| `004-tokenization-endpoints` | merged → `002-stored-card-tokens` |
| `003-transaction-endpoints` | `003-transactions-v2` |
| *(no equivalent)* | `004-token-charge` |

## What carried over

The old specs were wrong about BML, but much of their *engineering* reasoning stands and has
been retained in the new features:

- Environment isolation — a sandbox client can never route to production.
- Bounded retry with exponential backoff; `Retry-After` honoured on 429.
- A distinguishable error hierarchy rather than raw HTTP codes.
- Masked structured logging; audit records on state changes.
- Attribute whitelisting on response objects, so unexpected sensitive fields are dropped.
- Local validation before any remote call.

## Constitution

Amended to **2.0.0**. Principle III now requires that contracts derive from
`reference/Connect-API.json` and be verified against a live environment; Principle II gains an
explicit gate that a stubbed test is not evidence an endpoint exists; Principle V gains a rule
against inventing conveniences the platform does not offer. See `.specify/memory/constitution.md`.

## Status of `bml_tokenization`

Left in place, untouched, for reference. It is **not** to be published to RubyGems and should
not be added to any Gemfile. Its `lib/` remains useful only as a source of the retry/masking/audit
patterns listed above.

## Consumer impact

`msgowl/website` uses `BMLConnect::Client` at six call sites and is **unaffected** by this
migration — no existing behavior changes. Adding saved cards there becomes a change to the
existing create call (move to `/public/v2/transactions`, add `customerId` and
`tokenizationDetails`) rather than the adoption of a second gem. Tracked separately.
