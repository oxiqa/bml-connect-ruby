# Data Model: Stored Card Tokens

**Feature**: `002-stored-card-tokens` | **Derived from**: `reference/Connect-API.json`

## Entity: Token

A stored card belonging to a customer. This single entity replaces the retired gem's two —
`Token` and `CardOnFile` — which described one thing.

### Attributes

| Attribute | Type | Required by schema | Notes |
|---|---|---|---|
| `id` | string | ✔ | The handle for retrieve, delete, and **charge** (feature `004`) |
| `brand` | string | ✔ | Card scheme, e.g. `VISA` |
| `provider` | string | ✔ | Payment provider that issued the token |
| `token` | string | ✔ | The token value itself |
| `tokenType` | string | ✔ | |
| `deleted` | boolean | | Soft-delete flag |
| `tokenProvider` | string | | Tokenization provider, distinct from `provider` |
| `tokenAgreementId` | string | | Present for recurring/unscheduled agreements |
| `tokenAgreementType` | string | | Corresponds to `paymentType` on the originating transaction |
| `tokenExpiryMonth` | string | | String, not integer |
| `tokenExpiryYear` | string | | String, not integer |
| `paddedCardNumber` | string | | BML's masked summary. **The only card representation** |
| `customerId` | string | | Owning customer |
| `companyId` | string | | Owning merchant |
| `created` | string | | Timestamp |
| `updated` | string | | Timestamp |

### `id` vs `token` — which one charges?

Both fields exist and both look like identifiers. `POST /public-customers/charge` takes
**`tokenId`**, and the path parameter for retrieve/delete is **`tokenId`**. The library therefore
treats `Token#id` as the charge handle and exposes `token` as an opaque passthrough value.

**[UNVERIFIED]** — that `tokenId` in the charge body is `Token#id` and not `Token#token` is an
inference from consistent parameter naming, not something the document states. It MUST be
confirmed against UAT before feature `004` ships. Charging the wrong identifier is a
money-movement bug, so this is the single most important thing to verify in the whole migration.

### Whitelisting

Attributes are whitelisted at construction; unknown keys are dropped. If BML ever returned a PAN
field on a token payload, it could not reach a caller, a log line, or an audit record
(Constitution I).

### Validation (local, pre-remote)

| Rule | Applies to | Error |
|---|---|---|
| `customer_id` present and non-blank | all | `ValidationError(field: :customer_id)` |
| `token_id` present and non-blank | retrieve, delete | `ValidationError(field: :token_id)` |
| `actor` does not match a PAN pattern | delete | `ValidationError(field: :actor)` |

There is deliberately **no** card-input validation, because no operation accepts card input.

### Lifecycle

```
   (feature 003)
   POST /public/v2/transactions
   tokenizationDetails.tokenize = true
              │
              ▼
   cardholder completes on BML hosted page
              │
              ▼
        ┌───────────┐   charge (feature 004)   ┌──────────┐
        │  active   │─────────────────────────►│ charged  │
        │ deleted=f │◄─────────────────────────│          │
        └─────┬─────┘                          └──────────┘
              │ delete (DELETE → 204)
              ▼
        ┌───────────┐
        │  deleted  │   terminal; no un-delete documented
        └───────────┘
```

**This feature owns only the bottom half.** Creation is entirely outside it — there is no arrow
into `active` that this resource can draw.

## Entity: Token Collection

The set of one customer's tokens. Exposed as `BMLConnect::Models::TokenList`.

**[UNVERIFIED]**: whether BML returns a bare array or a `{count, items}` envelope. The model
tolerates both — if the payload is a Hash carrying `items`, it reads that; if it is an Array, it
uses it directly. This is defensive because the document's list schema is attached to the
operation's `requestBody` rather than its response, which makes the response shape genuinely
unknown until observed.

## Relationships

```
Customer (001)
   └── Token (002)  1:N   /public-customers/{customerId}/tokens
         │
         ├── created by  Transaction + tokenizationDetails  (003)
         └── charged by  POST /public-customers/charge      (004)
```

A token is never addressable without its customer.

## Non-entities

- **CardOnFile** — deleted. It and `Token` were the same object.
- **Card Handle** — deleted. No hosted-capture handle exists in BML Connect.
- **PAN / CVV** — never present, in any form, at any point.
