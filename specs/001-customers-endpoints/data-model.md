# Data Model: Customers Endpoints

**Feature**: `001-customers-endpoints` | **Derived from**: `reference/Connect-API.json`

## Entity: Customer

A payer registered under the merchant's company. Holds contact and billing details only —
**never** card data. Stored cards attach to a customer as tokens (feature `002`).

### Attributes

| Attribute | Type | Origin | Create | Update | Notes |
|---|---|---|---|---|---|
| `id` | string | platform | — | — | BML-assigned; the handle for tokens and charges |
| `name` | string | caller | **required** | optional | Single field. Not first/last. `minLength: 1` |
| `email` | string | caller | **required** | optional | `minLength: 1` |
| `companyId` | string | platform | — | — | Required in the response schema; the merchant |
| `currency` | string | platform | — | optional | Required in response; settable only on update |
| `customerGroupId` | string | platform | — | — | Resolved from `customerGroup` on create |
| `customerGroup` | string | caller | optional | — | Create-only; resolves to `customerGroupId` |
| `deleted` | boolean | platform | — | — | Archive flag; see lifecycle below |
| `billingEmail` | string | caller | optional | optional | |
| `billingAddress1` | string | caller | optional | optional | |
| `billingAddress2` | string | caller | optional | optional | |
| `billingCity` | string | caller | optional | optional | |
| `billingCountry` | string | caller | optional | optional | |
| `billingPostCode` | string | caller | optional | optional | |
| `paymentDue` | number | caller | — | optional | Update-only |
| `invoicePrefix` | string | caller | optional | optional | |
| `taxInformation` | string | caller | optional | optional | |
| `taxId` | string | caller | optional | optional | |
| `created` | string | platform | — | — | Timestamp |
| `updated` | string | platform | — | — | Timestamp |

Note the asymmetry: `customerGroup` is create-only, while `currency` and `paymentDue` are
update-only. This mirrors BML's two request schemas exactly and is not a library choice.

### Whitelisting

The model exposes **only** the attributes above. Any other key in a BML response is dropped at
construction. This is a security control (Constitution I): if BML ever returns a card field on a
customer payload, it cannot reach the object, a log line, or an audit record.

### Validation (local, pre-remote)

| Rule | Applies to | Error |
|---|---|---|
| `name` present and non-blank | create | `ValidationError(field: :name)` |
| `email` present and non-blank | create | `ValidationError(field: :email)` |
| `customer_id` present and non-blank | retrieve, update, archive | `ValidationError(field: :customer_id)` |
| `changes` non-empty | update | `ValidationError(field: :changes)` |
| No value matches a PAN pattern | all | `ValidationError` |
| `actor` does not match a PAN pattern | all | `ValidationError(field: :actor)` |

Validation order is presence → shape → PAN screen. No remote call is made when any rule fails.

`email` is checked for presence only. BML is the authority on address validity; imposing a
stricter local regex risks rejecting an address BML would accept (Constitution V).

### Lifecycle

```
      create
        │
        ▼
   ┌─────────┐   update    ┌─────────┐
   │ active  │◄───────────►│ active  │
   │deleted=f│             │ (edited)│
   └────┬────┘             └─────────┘
        │ archive (DELETE → 204)
        ▼
   ┌─────────┐
   │ archived│  deleted = true
   └─────────┘
```

Archiving is terminal from this library's perspective — no un-archive operation is documented.
Whether an archived customer's tokens survive is **[UNVERIFIED]**.

## Entity: Customer List Envelope

BML's list response shape.

| Attribute | Type | Notes |
|---|---|---|
| `count` | string | **Typed `string` in the document**, not integer. The library coerces to Integer and MUST tolerate a non-numeric value by falling back to `items.size`. |
| `items` | array | Customer objects. Item schema requires `name` and `email`; `id` is not marked required. |

Exposed as `BMLConnect::Models::CustomerList`, which is `Enumerable` over `items`.

## Relationships

```
Company (from API key)
  └── Customer  (1:N)          feature 001
        └── Token  (1:N)       feature 002 — /public-customers/{customerId}/tokens
              └── charged by   feature 004 — /public-customers/charge
```

A `Customer#id` is the required input to every operation in features `002` and `004`. This is
why customers is feature `001`: nothing downstream works without it.

## Non-entities

Deliberately **not** modelled here:

- **Card / PAN / CVV.** Never accepted, returned, or stored. Card capture happens on BML's
  hosted page.
- **Card-on-file.** The retired gem modelled this as a separate entity. In BML Connect there is
  no such object — a stored card *is* a customer token (feature `002`).
