# BMLConnect

Ruby gem for the Bank of Maldives Connect API

Use this gem to interact with your Bank of Maldives Connect API:
- 💳 __Transactions__
- 👤 __Customers__

**Planned** — specified against BML's published contract, not yet implemented. See
[Roadmap](#roadmap):
- 🔐 __Stored card tokens__
- 🔁 __Charging a stored card__


## Installation

Add this line to your application's Gemfile:

```ruby
gem 'bml_connect'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install bml_connect

## Usage

First get your API key and App ID from Merchant Portal for [`production`](https://dashboard.merchants.bankofmaldives.com.mv) or [`sandbox`](https://dashboard.uat.merchants.bankofmaldives.com.mv).

For production client:
```ruby
require 'bml_connect`

client = BMLConnect::Client.new(api_key: '<your-api-key>', app_id: '<your-app-id>')
```
For sandbox client:
```ruby
require 'bml_connect`

client = BMLConnect::Client.new(api_key: '<your-api-key>', app_id: '<your-app-id>', mode: 'sandbox')
```
In Ruby on Rails, to configure globally, add an intilializer `bml_connect.rb`:
```ruby
module BMLConnect
  class Client
    BML_API_KEY = ENV['BML_MPG_KEY']
    BML_APP_ID = ENV['BML_MPG_APP_ID']
    BML_MODE = ENV['BML_MPG_MODE']
  end
end
````
```ruby
client = BMLConnect::Client.new
```
### API Operations

> **Deprecation.** `transactions.create` posts to the legacy, undocumented-but-live
> `POST /public/transactions` (signed). It still works and its return type is unchanged, but it is
> **deprecated** in favour of `create_v2`, which targets BML's documented
> `POST /public/v2/transactions`. The first call in a process logs a one-time deprecation warning.

```ruby
# DEPRECATED v1 create — still works, returns a Faraday::Response
resp = client.transactions.create({
  amount: 10000,
  currency: 'MVR',
  redirectUrl: '<your-redirect-uri>',
  localId: 'local-1',
  customerReference: 'INV-0001'
})
resp = client.transactions.get(id)          # => Faraday::Response
resp = client.transactions.list({ page: 2 }) # => Faraday::Response
```

The v1 responses are [`Faraday::Response`](https://github.com/lostisland/faraday/blob/main/lib/faraday/response.rb) objects, `json`-encoded with symbolized names.

#### v2 surface (value objects)

The v2 methods target the documented endpoints, return whitelisted `TransactionRecord` value
objects, and **raise** on failure. `amount` MUST be a **positive Integer in minor units**
(`10_000` = MVR 100.00); a Float or String is rejected locally, never coerced.

```ruby
txn = client.transactions.create_v2(
  amount:      10_000,          # required — positive Integer, minor units
  currency:    "MVR",           # required
  redirectUrl: "https://merchant.example.mv/return",
  localId:     "INV-0001",
  customerId:  "cus_123"        # variant 3 (or supply an inline `customer:` — variant 4)
)
txn.id
txn.state                       # passed through verbatim (e.g. "CONFIRMED")
txn.payment_url                 # hosted page to send the cardholder to (never logged/audited)

client.transactions.retrieve("txn_…")                       # => TransactionRecord (`get` still returns raw)
client.transactions.update("txn_…", customerReference: "…") # partial merge: customerReference/localData/pnr
client.transactions.capture("txn_…", amount: 10_000)        # amount obeys the same rule as create
client.transactions.cancel("txn_…")
```

Store a card while taking payment by adding `tokenizationDetails`; the token appears under the
customer (via `client.tokens.list`) only **after** the cardholder completes the payment:

```ruby
client.transactions.create_v2(
  amount: 10_000, currency: "MVR", customerId: "cus_123",
  redirectUrl: "https://merchant.example.mv/return",
  tokenizationDetails: {
    tokenize:           true,
    paymentType:        "RECURRING",   # or "UNSCHEDULED"
    recurringFrequency: "MONTHLY",     # required when RECURRING
    expiryDate:         "2027-01-01"   # required when RECURRING; yyyy-mm-dd, future
  }
)
```

Create and capture are **never auto-retried** (no documented idempotency key); retrieve, list,
update and cancel retry with backoff. Which v2 response field carries the hosted payment URL is
still being verified against UAT — until then, `payment_url` raises `UnverifiedFieldError` rather
than returning `nil`, so `create_v2` should not be adopted in production yet.

### Customers

The customers resource wraps BML's `/public-customers` endpoints. Unlike `transactions` (which
returns a raw `Faraday::Response`), it returns whitelisted value objects and **raises** on
failure. Reach it through the same configured client:

```ruby
customer = client.customers.create(name: "Aisha Ali", email: "aisha@example.mv")
customer.id         # => BML-assigned id, the handle for tokens and charges
customer.companyId  # => platform-set

client.customers.retrieve(customer.id)                       # => Customer
client.customers.list.each { |c| puts c.email }              # Enumerable {count, items} envelope
client.customers.update(customer.id, billingCity: "Male")    # partial merge: only supplied keys sent
client.customers.archive(customer.id)                        # => true (soft delete; record keeps deleted: true)
```

Notes:

- **Required on create:** `name` and `email`. Optional documented fields (`billingEmail`,
  `billingAddress1`, `billingCity`, `billingCountry`, `billingPostCode`, `taxId`, …) pass through
  unchanged. `email`/`billingEmail` get a lightweight shape check (must contain an `@` and a
  domain); BML remains the authority beyond that.
- **Update is a partial merge** (`PATCH`): only the keys you pass are sent — an unset field is
  never serialized as `null`, so it cannot erase stored data.
- **No card data.** Every caller-supplied string is screened for a card-number pattern and
  rejected locally before any request; responses are whitelisted so a stray card field can never
  reach an object, a log line, or the audit trail.
- **Auditing.** `create`, `update` and `archive` emit a masked, structured audit line through the
  client's logger (who / what / when / outcome). Pass an optional `actor:` to attribute the call;
  reads are not audited. Inject your own logger via `Client.new(options: { logger: my_logger })`.
- **Errors** are a typed hierarchy under `BMLConnect::Error`: `ValidationError` (carries `#field`),
  `NotFoundError`, `AuthenticationError`, `ConflictError`, `RateLimitError` (carries
  `#retry_after`), and `AvailabilityError` (timeouts / 5xx after bounded retries).

### Stored cards (tokens)

The tokens resource wraps BML's `/public-customers/{customerId}/tokens` endpoints. It is
**read-and-delete only** — list, retrieve, delete — because BML publishes no endpoint that
creates a token. A stored card comes into existence only as a side effect of a tokenizing
transaction (feature `003`), completed by the cardholder on BML's hosted page; see
[How tokenization actually works](#how-tokenization-actually-works). Every path is nested under a
`customerId`.

```ruby
# List a customer's saved cards
client.tokens.list("cus_123").each do |t|
  puts "#{t.brand} #{t.paddedCardNumber} exp #{t.tokenExpiryMonth}/#{t.tokenExpiryYear}"
end

client.tokens.retrieve("cus_123", "tok_456")                    # => Token
client.tokens.delete("cus_123", "tok_456", actor: "ops:jane")   # => true (soft delete)
```

Notes:

- **No create, no detokenize.** There is deliberately no `client.tokens.create`/`tokenize`/
  `detokenize` — the absence is enforced by a test. If you are looking for one, tokens are created
  via feature `003`, not here.
- **No card data.** No operation accepts a PAN, CVV, expiry, or capture handle. A token is
  represented only by BML's own fields (`token`, `brand`, `paddedCardNumber`, `tokenExpiryMonth`,
  `tokenExpiryYear`, …); the gem invents no `last_four`/`scheme` alias and exposes no full card
  number. Responses are whitelisted, so a stray card field can never reach an object, log, or audit
  record.
- **Empty vs. broken.** An empty token list is an empty `TokenList`, never an error, and an
  authentication failure is never swallowed into one.
- **Auditing.** Only `delete` is audited (reads are not); it emits a single masked audit line —
  once, even if the delete is retried. Pass an optional `actor:` (screened for card data) to
  attribute it.
- **Retries.** Transient failures (`429`, `408`, timeouts, `5xx`) are retried on all three
  operations — delete included, since soft-delete is idempotent — with bounded backoff, then raised
  as `RateLimitError`/`AvailabilityError`. Tune via `Client.new(options: { max_retries: 2,
  retry_backoff: 0.5 })`; set `max_retries: 0` to disable. A `429`'s `Retry-After` is surfaced on
  `RateLimitError#retry_after`.

### Charging a stored card

Once a customer has a stored card (a token), you can take a payment from it with no cardholder
present — a subscription renewal, an account top-up, an ad-hoc charge. It is a **two-call flow**,
and the gem keeps it that way on purpose: BML has no single endpoint that creates a transaction
and charges it, so this gem offers none either (a hidden combined call would obscure a money
movement). The **amount lives on the transaction**, not on the charge.

```ruby
# 1 ── create the transaction to be charged (the amount lives HERE)
renewal = client.transactions.create_v2(
  amount: 10_000, currency: "MVR",       # MVR 100.00, in minor units
  customerId: "cus_123", localId: "SUB-2026-10"
)

# 2 ── charge the stored card against it
charged = client.customers.charge(
  customer_id:    "cus_123",
  transaction_id: renewal.id,
  token_id:       "tok_789",             # the stored card's Token#id
  actor:          "billing:cron"          # optional, for the audit "who"
)

charged.state    # resolved synchronously — no cardholder redirect
```

Notes:

- **Returned vs. raised.** A **returned** `TransactionRecord` means BML answered — inspect
  `charged.state` for the business outcome (a decline is a returned record, not an exception). A
  **raised** error means BML did not answer. The gem never converts one into the other, so a
  declined card and a network outage are always distinguishable.
- **Never auto-retried.** The charge schema carries no idempotency key, so a retry could take
  payment twice. Exactly one HTTP attempt is made. On a timeout, an `AvailabilityError` is raised
  whose message **names the `transaction_id`** — reconcile by retrieving that transaction
  (`client.transactions.retrieve(id)`) rather than re-charging blindly.
- **No `amount` on the charge.** To bill a different amount, create a different transaction.
- **Audited, failures included.** Every charge emits a masked audit line — success, decline,
  validation failure, and availability failure alike — carrying the transaction and token ids and
  never any card data.
- **⚠️ Release-blocked.** It is not yet confirmed against a live environment whether `token_id`
  expects `Token#id` or `Token#token`. `Token#id` is the current inference; do not rely on this in
  production until it is verified (see `specs/004-token-charge/`).

## Roadmap

Tokenization support is moving into this gem. It was previously being built as a separate
`bml_tokenization` gem, which turned out to have been specified against an assumed API contract
that does not match BML's published one — see [MIGRATION.md](MIGRATION.md) for the full account.

Work is now spec-driven against BML's own OpenAPI document, vendored at
[`reference/Connect-API.json`](reference/Connect-API.json). Where this library and that document
disagree, the document wins.

| Feature | Endpoints | Status |
|---|---|---|
| [`001-customers-endpoints`](specs/001-customers-endpoints/) | `/public-customers` | Implemented (pending live UAT verification) |
| [`002-stored-card-tokens`](specs/002-stored-card-tokens/) | `/public-customers/{id}/tokens` | Implemented (pending live UAT verification) |
| [`003-transactions-v2`](specs/003-transactions-v2/) | `/public/v2/transactions` | Specified |
| [`004-token-charge`](specs/004-token-charge/) | `/public-customers/charge` | Implemented, release-blocked (pending live UAT: `tokenId` identity) |

Each feature directory carries a `spec.md`, `plan.md`, `research.md`, `data-model.md`, `tasks.md`
and two contracts — one for the BML HTTP surface, one for the Ruby surface this gem exposes.

### How tokenization actually works

Worth stating up front, because it is not what most payment APIs do: **there is no endpoint that
creates a token.** A stored card comes into existence as a side effect of a transaction that
carries `tokenizationDetails`, completed by the cardholder on BML's hosted page. Later charges
are a two-step flow — create a transaction, then charge it against the stored token.

```
create customer  ─►  create transaction with tokenizationDetails  ─►  cardholder pays
                                                                          │
                     charge stored token  ◄──  token now listed  ◄────────┘
```

### Backward compatibility

The transactions methods documented above are **not changing**. `create`, `get` and `list` keep
their current endpoints, signatures and `Faraday::Response` return type. New capabilities arrive
under new method names.

`transactions.create` will be marked **deprecated** in favour of a `create_v2` targeting BML's
documented `/public/v2/transactions`, but it will continue to work — it is live and carries
production traffic today.

## Contributing to the specs

This repository uses [Spec Kit](https://github.com/github/spec-kit). The active feature is
tracked in `.specify/feature.json`:

```bash
./speckit-feature            # show the active feature and the status of each
./speckit-feature 002        # switch the active feature
```

The project constitution is at [`.specify/memory/constitution.md`](.specify/memory/constitution.md).
Two rules matter most for anyone adding a remote call:

1. **A stubbed test is not evidence that an endpoint exists.** Every path must be traceable to
   `reference/Connect-API.json`, and stub URLs must derive from the client's base URL rather than
   being hardcoded.
2. **Anything not in the published document is marked `[UNVERIFIED]`** and must be confirmed
   against UAT before it is relied on.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/oxiqa/bml-connect-ruby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/oxiqa/bml-connect-ruby/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the BMLConnect project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/oxiqa/bml-connect-ruby/blob/main/CODE_OF_CONDUCT.md).
