# Quickstart: Stored Card Tokens

**Feature**: `002-stored-card-tokens`

## Using the resource

```ruby
client = BMLConnect::Client.new(mode: "sandbox")

# List a customer's saved cards
client.tokens.list("cus_123").each do |t|
  puts "#{t.brand} #{t.paddedCardNumber} exp #{t.tokenExpiryMonth}/#{t.tokenExpiryYear}"
end

# Retrieve one
token = client.tokens.retrieve("cus_123", "tok_456")

# Remove one
client.tokens.delete("cus_123", "tok_456", actor: "ops:jane")
```

## How a token gets created

**Not here.** This resource cannot create one. A token appears after a cardholder completes a
transaction that asked for tokenization — feature `003`:

```ruby
resp = client.transactions.create_v2(
  amount: 10000, currency: "MVR",
  customerId: "cus_123",
  redirectUrl: "https://example.mv/return",
  tokenizationDetails: { tokenize: true, paymentType: "UNSCHEDULED" }
)
# cardholder completes at resp.body[:url] on BML's hosted page
# afterwards the token appears in client.tokens.list("cus_123")
```

If you are looking for `client.tokens.create`, it does not exist and its absence is deliberate —
see `contracts/library-api.md`.

## Error handling

```ruby
begin
  tokens = client.tokens.list("cus_123")
  puts "no saved cards" if tokens.empty?
rescue BMLConnect::NotFoundError
  warn "no such customer"
rescue BMLConnect::AuthenticationError
  warn "credentials rejected — this is NOT an empty card list"
end
```

An empty list and an auth failure are deliberately different outcomes (research R6). Never
rescue the latter into the former.

## Running the tests

```bash
bundle exec rspec spec/unit spec/contract     # deterministic
bundle exec rspec                             # adds UAT (skips without creds)
```

## Verifying against UAT

```bash
export BML_API_KEY=<uat key>
export BML_APP_ID=<uat app id>
export BML_ENV=sandbox
export BML_CUSTOMER_ID=<a customer with at least one stored card>

bundle exec rspec spec/integration/tokens_uat_spec.rb --format documentation
```

`BML_CUSTOMER_ID` must reference a customer who has completed a tokenizing transaction; there is
no way to create a token from the test suite alone.

> The same credential blocker as feature `001` applies — the key in `msgowl/website`'s
> development credentials is rejected by UAT with `PP-C-004`. A newly issued UAT key is required.

## The seven open questions

`contracts/bml-remote.md` carries seven `[UNVERIFIED]` items. Resolve them during the UAT run and
update the contract. Two matter more than the rest:

1. **`tokenId` = `Token#id` or `Token#token`?** Feature `004` charges money against this. It
   MUST NOT ship until this is confirmed. Verify by charging a known token and checking the
   resulting transaction.
2. **Cross-customer access.** Retrieve a valid `tokenId` under a *different* `customerId`. It
   must fail. If it succeeds, stop and report to BML — that would be a cardholder-data exposure.
