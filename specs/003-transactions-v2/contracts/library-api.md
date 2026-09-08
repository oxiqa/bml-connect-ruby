# Contract: Library API — Transactions V2

**Feature**: `003-transactions-v2` | **Consumer**: integrators using the `bml_connect` gem.

This feature extends an **existing, released** resource. Backward compatibility is a hard
requirement (FR-010).

## Unchanged — existing surface

These keep their exact current behavior, endpoint, and return type. Six production call sites in
`msgowl/website` depend on them.

```ruby
client.transactions.create(params)   # => Faraday::Response  (legacy v1, signed) — DEPRECATED
client.transactions.get(id)          # => Faraday::Response
client.transactions.list(params)     # => Faraday::Response
```

`create` is **deprecated but functional**. It still posts to the undocumented-but-live
`public/transactions` with the SHA1 signature. Calling it emits a one-time deprecation warning
naming `create_v2`. It MUST NOT be removed in this feature.

## New — v2 surface

New methods return **value objects** and **raise** on failure, matching features `001`, `002` and
`004`. See `001/research.md` R2 for why the two conventions coexist.

### `create_v2(details, actor: nil)`

```ruby
txn = client.transactions.create_v2(
  amount:            10_000,          # required — positive Integer, minor units
  currency:          "MVR",           # required
  redirectUrl:       "https://merchant.example.mv/return",
  localId:           "INV/112.33",
  customerReference: "Basket 392",
  customerId:        "cus_123",       # variant 3
  webhook:           "https://merchant.example.mv/hooks/bml"
)

txn.id
txn.state
txn.payment_url      # see the caveat below
```

Local validation before any remote call:

| Rule | Error |
|---|---|
| `amount` present, Integer, positive | `ValidationError(field: :amount)` |
| `currency` present | `ValidationError(field: :currency)` |
| `amount` is a Float or String | `ValidationError(field: :amount)` — never coerced |
| Either `customerId` or `customer` (not both) | `ValidationError` |
| Inline `customer` has `name` and `email` | `ValidationError` |
| No value matches a PAN pattern | `ValidationError` |

**Not retried on failure** (FR-016). A timeout raises `AvailabilityError` after exactly one
attempt; reconcile by `localId`.

> **`payment_url` caveat.** Which response field carries the hosted payment link on v2 is
> `[UNVERIFIED]`. `Transaction#payment_url` reads the first present of `url`, `redirectUrl`,
> `qr.url` and **raises `BMLConnect::UnverifiedFieldError` if none is present**, rather than
> returning nil. Silently returning nil would send a cardholder nowhere.

### `create_v2` with tokenization

```ruby
txn = client.transactions.create_v2(
  amount: 10_000, currency: "MVR",
  customerId: "cus_123",
  redirectUrl: "https://merchant.example.mv/return",
  tokenizationDetails: {
    tokenize:           true,
    paymentType:        "RECURRING",     # or "UNSCHEDULED"
    recurringFrequency: "MONTHLY",       # required when RECURRING
    expiryDate:         "2027-01-01"     # required when RECURRING; must be future
  }
)
```

Conditional validation, all local:

| Rule | Error |
|---|---|
| `tokenize` present when `tokenizationDetails` given | `ValidationError(field: :tokenize)` |
| `paymentType` present, one of `RECURRING` / `UNSCHEDULED` | `ValidationError(field: :paymentType)` |
| `recurringFrequency` present when `RECURRING`, from the documented set | `ValidationError(field: :recurringFrequency)` |
| `expiryDate` present when `RECURRING` | `ValidationError(field: :expiryDate)` |
| `expiryDate` is `yyyy-mm-dd` and in the future | `ValidationError(field: :expiryDate)` |

The token appears under the customer only **after the cardholder completes the payment**. Read it
with `client.tokens.list(customer_id)` (feature `002`).

### `retrieve(id, actor: nil)`

```ruby
txn = client.transactions.retrieve("txn_…")
txn.state    # passed through verbatim — "CONFIRMED", "CANCELLED", "FAILED", …
```

Value-object counterpart to the existing `get`. Both remain available; `get` is not deprecated,
since raw-response access is legitimately useful.

**`state` is never normalized.** Production code branches on BML's own values and remapping them
would break it.

### `update(id, changes, actor: nil)`

```ruby
client.transactions.update("txn_…", customerReference: "Basket 393")
```

Partial merge over `customerReference`, `localData`, `pnr`. Empty `changes` raises.

### `capture(id, amount:, actor: nil)` and `cancel(id, actor: nil)`

```ruby
client.transactions.capture("txn_…", amount: 10_000)   # => Transaction
client.transactions.cancel("txn_…")                    # => Transaction
```

Both emit audit records. `capture` validates `amount` as a positive Integer.

## Out of scope

Create variants 1, 2 (shop orders) and 5 (foreign exchange) are **not implemented**. Variants 1–2
need the shops/products surface; variant 5 needs an FX quote flow documented nowhere in the file.
`create_v2` raises `ValidationError` naming the unsupported shape if given `order` or `fxQuoteId`,
rather than sending a body BML will reject.

## Value object

### `BMLConnect::Models::Transaction`

Whitelisted:

```
id  created  updated  amount  currency  payCurrency  merchantId
provider  providerHistory  state  accountingState  qr  securityWord
canRefundIfConfirmed  externalImport  externalId  localId  paymentToken
history  appVersion  apiVersion  redirectUrl  costStructure
providerDisplayName  paddedCardNumber  customerId
```

Plus `#payment_url` (see caveat) and `#tokenized?`.

`#to_h` and `#inspect` **omit the payment URL** — it is a completion secret and must not reach
logs (FR-015).

> Do not confuse this with the existing `BMLConnect::Models::Transaction` used as a *request*
> builder by the v1 `create`. That class is untouched. The new response object lives at
> `BMLConnect::Models::TransactionRecord` to avoid a collision. This naming is unfortunate and is
> queued for reconciliation in `v1.0.0`.

## Audit records

`create_v2`, `capture`, `cancel` and `update` emit records. `retrieve`, `get` and `list` do not.
**No audit record ever contains the hosted payment URL** (FR-015).
