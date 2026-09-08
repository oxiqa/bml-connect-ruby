# Quickstart: Transactions V2

**Feature**: `003-transactions-v2`

## Nothing you have breaks

The existing methods are untouched:

```ruby
resp = client.transactions.create(amount: "10000", currency: "MVR", redirectUrl: "…",
                                  localId: "…", customerReference: "…")
resp.status         # => 200
resp.body[:id]
resp.body[:url]
```

Still posts to the legacy v1 endpoint, still signed, still returns a `Faraday::Response`. It now
emits a one-time deprecation warning pointing at `create_v2`.

## Taking a payment on the documented endpoint

```ruby
txn = client.transactions.create_v2(
  amount:            10_000,        # Integer, minor units — MVR 100.00
  currency:          "MVR",
  redirectUrl:       "https://merchant.example.mv/return",
  localId:           "INV/112.33",
  customerReference: "Basket 392"
)

txn.id
txn.state
redirect_to txn.payment_url        # see the caveat below
```

## Storing a card while taking payment

```ruby
customer = client.customers.create(name: "Aisha Ali", email: "aisha@example.mv")

txn = client.transactions.create_v2(
  amount: 10_000, currency: "MVR",
  customerId:  customer.id,
  redirectUrl: "https://merchant.example.mv/return",
  tokenizationDetails: {
    tokenize:    true,
    paymentType: "UNSCHEDULED"        # ad-hoc future charges
  }
)
# → cardholder completes at txn.payment_url

# afterwards:
client.tokens.list(customer.id)       # the stored card is now here
```

For a subscription, use `RECURRING` and supply both extra fields:

```ruby
tokenizationDetails: {
  tokenize:           true,
  paymentType:        "RECURRING",
  recurringFrequency: "MONTHLY",      # DAILY WEEKLY BIWEEKLY FORTNIGHTLY MONTHLY QUARTERLY YEARLY AD_HOC
  expiryDate:         "2027-01-01"    # yyyy-mm-dd, must be in the future
}
```

Omit either and the library raises `ValidationError` locally, before any network call.

**The card is stored only after the cardholder completes the payment.** `create_v2` returning
successfully does not mean a card was saved — confirm with `client.tokens.list`.

## Amount units

`create_v2` requires a **positive Integer in minor units**. `10_000` is MVR 100.00.

```ruby
client.transactions.create_v2(amount: 100.0, currency: "MVR")   # ValidationError — never coerced
client.transactions.create_v2(amount: "10000", currency: "MVR") # ValidationError — Integer only
```

This is stricter than the legacy `create`, deliberately: `100.0` could mean MVR 100.00 or MVR
1.00, and the library will not guess on a money field.

## Retry behavior differs by operation

```ruby
begin
  client.transactions.create_v2(amount: 10_000, currency: "MVR", redirectUrl: "…", localId: "INV-1")
rescue BMLConnect::AvailabilityError
  # exactly ONE attempt was made. Do NOT blindly retry — the transaction may exist.
  # Reconcile by localId first.
end
```

Create and capture are never retried automatically; there is no documented idempotency key.
Retrieve, list, update and cancel retry with backoff.

## Other operations

```ruby
txn = client.transactions.retrieve("txn_…")     # value object; `get` still returns raw
client.transactions.update("txn_…", customerReference: "Basket 393")
client.transactions.capture("txn_…", amount: 10_000)
client.transactions.cancel("txn_…")
```

## Running the tests

```bash
bundle exec rspec spec/unit spec/contract
bundle exec rspec spec/contract/transactions_v1_compat_spec.rb   # pins existing behavior
bundle exec rspec                                                # adds UAT
```

The compatibility suite is the one to watch. If it fails, a released method changed and
`msgowl/website` is about to break.

## Verifying against UAT

```bash
export BML_API_KEY=<uat key>
export BML_APP_ID=<uat app id>
export BML_ENV=sandbox
export BML_CUSTOMER_ID=<a customer id from feature 001>

bundle exec rspec spec/integration/transactions_v2_uat_spec.rb --format documentation
```

### The blocker to resolve first

**Which response field carries the hosted payment URL on v2?** The v1 response uses `url`; the v2
schema does not list it. `#payment_url` raises `UnverifiedFieldError` rather than returning nil,
so you will find out immediately.

Create one v2 transaction against UAT and dump the raw response:

```ruby
resp = client.transactions.send(:raw_create_v2, amount: 100, currency: "MVR",
                                redirectUrl: "https://example.mv/r", localId: "probe-1")
puts JSON.pretty_generate(resp.body)
```

Record the field name in `contracts/bml-remote.md` and resolve `[UNVERIFIED]` #1. **v2 create
must not be used in production until this is settled** — without the right field there is nowhere
to send the cardholder.

### Verifying tokenization end-to-end (SC-002)

This one needs a human. Create a tokenizing transaction, open `payment_url` in a browser,
complete it with a UAT test card from the merchant dashboard, then check
`client.tokens.list(customer_id)`. No automated test can do this unattended; record the result in
the contract's verification table.
