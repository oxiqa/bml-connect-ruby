# Quickstart: Token Charge

**Feature**: `004-token-charge`

> ⛔ **Not releasable yet.** It is unconfirmed whether the `tokenId` field expects `Token#id` or
> `Token#token`. See `contracts/bml-remote.md`. Build and merge; do not adopt in production
> until resolved.

## The full flow, from nothing to a charged stored card

```ruby
client = BMLConnect::Client.new(mode: "sandbox")

# 1 ── the customer                                        (feature 001)
customer = client.customers.create(name: "Aisha Ali", email: "aisha@example.mv")

# 2 ── store a card by taking a payment with tokenization  (feature 003)
first = client.transactions.create_v2(
  amount: 10_000, currency: "MVR",
  customerId:  customer.id,
  redirectUrl: "https://merchant.example.mv/return",
  tokenizationDetails: { tokenize: true, paymentType: "UNSCHEDULED" }
)
# → cardholder completes at first.payment_url, in a browser

# 3 ── the card is now stored                              (feature 002)
token = client.tokens.list(customer.id).first

# 4 ── later: charge it, with no cardholder present        (this feature)
renewal = client.transactions.create_v2(
  amount: 10_000, currency: "MVR",
  customerId: customer.id, localId: "SUB-2026-10"
)

charged = client.customers.charge(
  customer_id:    customer.id,
  transaction_id: renewal.id,
  token_id:       token.id
)

charged.state    # resolved synchronously — no redirect
```

Steps 1–3 happen once. Step 4 repeats for every renewal.

## Two calls, on purpose

Every charge needs a transaction to charge. The library will not do both for you:

```ruby
client.customers.charge_new(amount: 10_000, ...)   # NoMethodError — deliberately absent
```

Hiding a transaction creation inside a method called `charge` would obscure a money movement and
make a partial failure invisible. Create the transaction, then charge it.

The **amount lives on the transaction**, not on the charge. To bill a different amount, create a
different transaction.

## Handling the three outcomes

```ruby
begin
  charged = client.customers.charge(customer_id: customer.id,
                                 transaction_id: renewal.id,
                                 token_id: token.id)

  if charged.state == "CONFIRMED"
    settle!(renewal)
  else
    dun!(customer)          # declined — do NOT blindly retry
  end

rescue BMLConnect::AvailabilityError => e
  # ONE attempt was made. The charge may or may not have been applied.
  # e.message names the transaction id. Reconcile — never re-charge blind:
  actual = client.transactions.retrieve(renewal.id)
  reconcile!(actual)

rescue BMLConnect::NotFoundError
  warn "unknown customer, transaction, or token"
end
```

The rule: **returned means BML answered** (a business outcome, including a decline). **Raised
means BML did not answer** (a transport outcome). The library never converts one to the other.

## No retries — ever

`charge` makes exactly one HTTP attempt. There is no idempotency key on this endpoint, so an
automatic retry could take payment twice. If you build your own retry, reconcile first by
retrieving the transaction.

## Running the tests

```bash
bundle exec rspec spec/unit/customers_charge_spec.rb spec/contract/customers_charge_remote_spec.rb
```

## Verifying against UAT

Needs a customer with a genuinely stored card, which needs a human to complete a hosted payment:

```bash
export BML_API_KEY=<uat key>
export BML_APP_ID=<uat app id>
export BML_ENV=sandbox
export BML_CUSTOMER_ID=<customer with a stored card>
export BML_TOKEN_ID=<their token id>

bundle exec rspec spec/integration/customers_charge_uat_spec.rb --format documentation
```

### Resolving the blocker

1. List the customer's tokens; note **both** `token.id` and `token.token`.
2. Create a small transaction (say MVR 1.00 → `amount: 100`).
3. Charge with `token_id: token.id`. If it succeeds — answer found, record it.
4. If rejected, create a **brand-new** transaction and charge with `token_id: token.token`.
   **Never reuse the first transaction** — charging an already-charged transaction is itself an
   open question, and reusing it would confound two unknowns.
5. Record the answer in `contracts/bml-remote.md`, `data-model.md`, and the method's RDoc.

Then work through open items 2–5 in the same session: decline signalling, double-charge
behavior, deleted-token rejection, and customer/token mismatch rejection. For each, an
unexpected **success** is the dangerous result — note it loudly rather than moving on.
