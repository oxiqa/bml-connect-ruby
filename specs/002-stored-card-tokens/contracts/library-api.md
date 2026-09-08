# Contract: Library API — Stored Card Tokens

**Feature**: `002-stored-card-tokens` | **Consumer**: integrators using the `bml_connect` gem.

## Reaching the resource

```ruby
client = BMLConnect::Client.new
client.tokens                     # => BMLConnect::Tokens
```

## Operations

### `list(customer_id)`

```ruby
tokens = client.tokens.list("cus_…")
tokens.each do |t|
  puts "#{t.brand} #{t.paddedCardNumber} exp #{t.tokenExpiryMonth}/#{t.tokenExpiryYear}"
end
tokens.empty?      # => true when the customer has no saved cards
```

Returns `BMLConnect::Models::TokenList` (`Enumerable`). An empty result is an empty list, never
an error, and never the result of swallowing an auth failure. Not audited (read).

### `retrieve(customer_id, token_id)`

```ruby
token = client.tokens.retrieve("cus_…", "tok_…")
token.id             # charge with this (feature 004)
token.deleted?       # => Boolean
```

Raises `NotFoundError` for an unknown token, or one belonging to another customer. Not audited.

### `delete(customer_id, token_id, actor: nil)`

```ruby
client.tokens.delete("cus_…", "tok_…", actor: "ops:jane")   # => true
```

Returns `true` on `204`. Emits an audit record (`action: :delete`).

## Operations that deliberately do not exist

| Not provided | Why |
|---|---|
| `create` / `tokenize` / `store` | No such endpoint. Tokens are created by a tokenizing transaction — feature `003`. |
| `detokenize` / `card_number` | No detokenization endpoint exists, and none will be added (FR-008). |
| `update` | BML documents no token update. |

A unit test asserts the resource's public instance methods are exactly `list`, `retrieve`,
`delete` — so a future contributor cannot quietly reintroduce a fictional `tokenize` (SC-006).

## Value objects

### `BMLConnect::Models::Token`

Read-only, whitelisted to BML's own field names:

```
id  brand  provider  token  tokenType  deleted
tokenProvider  tokenAgreementId  tokenAgreementType
tokenExpiryMonth  tokenExpiryYear  paddedCardNumber
customerId  companyId  created  updated
```

Convenience predicates: `#deleted?`, `#recurring?` (true when `tokenAgreementId` is present).

The library exposes no `last_four`, `scheme`, or `masked_number` alias. `paddedCardNumber` is
BML's name and is the name callers see (FR-007).

`#inspect` and `#to_h` are limited to the whitelist, so a token can be safely logged.

### `BMLConnect::Models::TokenList`

`items`, `size`, `empty?`, `Enumerable`. Also `#active` — the subset with `deleted` false.

## Errors

The shared hierarchy from feature `001`: `ValidationError`, `AuthenticationError`,
`NotFoundError`, `ConflictError`, `RateLimitError`, `AvailabilityError`.

`ValidationError` is raised locally, before any network call, for a blank `customer_id` or
`token_id`.
