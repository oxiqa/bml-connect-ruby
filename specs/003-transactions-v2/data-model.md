# Data Model: Transactions V2

**Feature**: `003-transactions-v2` | **Derived from**: `reference/Connect-API.json`

## Entity: Transaction (response record)

Implemented as `BMLConnect::Models::TransactionRecord` — not `Transaction`, which is already
taken by the v1 **request** builder (`lib/bml_connect/models/transaction.rb`). The collision is
pre-existing; renaming the old class would break `transactions.create`.

### Attributes

| Attribute | Type | Origin | Notes |
|---|---|---|---|
| `id` | string | platform | The handle for retrieve, update, capture, cancel, and charge (feature `004`) |
| `state` | string | platform | **Passed through verbatim.** No enum documented; production branches on `CONFIRMED` / `CANCELLED` / `FAILED` |
| `accountingState` | string | platform | |
| `amount` | integer | caller | Minor units |
| `currency` | string | caller | |
| `payCurrency` | string | platform | FX variant only |
| `merchantId` | string | platform | Persisted by the website |
| `provider` | string | platform | Persisted by the website |
| `providerHistory` | array | platform | |
| `providerDisplayName` | string | platform | |
| `qr` | object | platform | `{ url }` |
| `securityWord` | string | platform | |
| `canRefundIfConfirmed` | boolean | platform | |
| `externalImport` | boolean | platform | |
| `externalId` | string | platform | |
| `localId` | string | caller | The integrator's own reference — **the reconciliation key** |
| `customerReference` | string | caller | |
| `paymentToken` | string | platform | |
| `history` | array | platform | `[{state, updatedDate, trigger}]` |
| `redirectUrl` | string | both | Sent as a request field; echoed back |
| `costStructure` | object | platform | |
| `appVersion` / `apiVersion` | string | platform | |
| `created` / `updated` | string | platform | |
| `paddedCardNumber` | string | platform | Masked summary; persisted by the website |
| `customerId` | string | caller/platform | Set by the platform on the inline-customer variant |

### The payment URL problem

The v1 response carries `url` and the website reads `resp.body[:url]`. **`url` is not in the v2
response schema.** Present instead: `redirectUrl` (also a request field, so probably an echo) and
`qr.url`.

`#payment_url` therefore reads the first present of `url`, `redirectUrl`, `qr.url` — and
**raises `UnverifiedFieldError` when none is present**. Returning nil would send a cardholder
nowhere and surface as a blank page rather than an error. This is `[UNVERIFIED]` item #1 and
blocks production use of v2 create.

### Whitelisting and the payment-URL exception

Attributes are whitelisted; unknown keys are dropped. `#to_h` and `#inspect` additionally
**omit** the payment URL — it is a completion secret. Anyone holding it can complete the payment,
so it must never reach a log line or an audit record (FR-015), even though it is legitimately
readable via `#payment_url`.

## Entity: Tokenization Details (input only)

Never returned; only sent. Its presence is what causes a token to be created.

| Field | Type | Required | Values |
|---|---|---|---|
| `tokenize` | boolean | ✔ | `true` = cardholder-initiated, `false` = merchant-initiated |
| `paymentType` | string | ✔ | `RECURRING` \| `UNSCHEDULED` |
| `recurringFrequency` | string | when `RECURRING` | `DAILY`, `WEEKLY`, `BIWEEKLY`, `FORTNIGHTLY`, `MONTHLY`, `QUARTERLY`, `YEARLY`, `AD_HOC` |
| `expiryDate` | string | when `RECURRING` | `yyyy-mm-dd`, future |

The allowed values come from BML's **prose descriptions**, not from a JSON `enum` — the document
declares no enums for these. Validation therefore mirrors documented prose, and an unrecognized
value is rejected with a message quoting the documented set.

## Amount representation

| Layer | Representation |
|---|---|
| Caller → library | Positive **Integer**, minor units (`10_000` = MVR 100.00) |
| Library → BML | The same integer; v2 schema types `amount` as `number` |
| Existing website (v1) | `("%.02f" % 100.0).gsub(".", "")` → `"10000"` (a String) |

`create_v2` **rejects** a Float or a String rather than coercing. `100.0` is ambiguous — MVR 100
or MVR 1.00? — and guessing wrong on a money field is unacceptable. The legacy `create` is
untouched and still accepts what it always did.

## Validation (local, pre-remote)

Ordered: variant selection → presence → type → conditional tokenization rules → PAN screen.

| Rule | Error field |
|---|---|
| `amount` present, Integer, positive | `:amount` |
| `currency` present | `:currency` |
| Not both `customerId` and `customer` | `:customerId` |
| Inline `customer` has `name` + `email` | `:customer` |
| `order` or `fxQuoteId` present → unsupported variant | `:order` / `:fxQuoteId` |
| `tokenize` present when `tokenizationDetails` given | `:tokenize` |
| `paymentType` in the documented set | `:paymentType` |
| `recurringFrequency` present + valid when `RECURRING` | `:recurringFrequency` |
| `expiryDate` present, `yyyy-mm-dd`, future when `RECURRING` | `:expiryDate` |
| No value matches a PAN pattern | varies |

## Lifecycle

```
   create_v2 (tokenizationDetails.tokenize = true)
        │
        ▼
   ┌──────────┐   cardholder completes on BML hosted page   ┌───────────┐
   │ created  │───────────────────────────────────────────► │ CONFIRMED │──► token stored (002)
   │          │                                             └───────────┘
   │          │──► CANCELLED  (cancel, or cardholder abandons)
   │          │──► FAILED
   └──────────┘
        │ capture (pre-authorization only)
        ▼
   ┌──────────┐
   │ captured │
   └──────────┘
```

**A token exists only after the cardholder completes the payment.** Creating a tokenizing
transaction is not sufficient — the library MUST NOT report a stored card until feature `002`
confirms it.

## Relationships

```
Customer (001) ──1:N──► Transaction (003)
                            │ tokenizationDetails.tokenize
                            ▼
                        Token (002) ──charged by──► charge (004)
                                                       │
                                        requires a transactionId ──┘
```

Feature `004`'s charge requires **both** a `tokenId` and a `transactionId`, so a transaction is
created first and then charged against the stored token. Two steps, not one.

## Retry policy — deliberately asymmetric

| Operation | Auto-retry |
|---|---|
| `create_v2`, legacy `create` | **Never** (FR-016) |
| `retrieve`, `get`, `list`, `cancel` | Yes — bounded, backoff, `Retry-After` on 429 |
| `capture` | **Never** — it moves money |
| `update` | Yes |

No server-side idempotency key is documented for create. The retired gem retried create on the
strength of an idempotency guarantee it invented; that is exactly the assumption this migration
exists to remove.
