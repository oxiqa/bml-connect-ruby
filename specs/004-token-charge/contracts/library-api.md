# Contract: Library API — Token Charge

**Feature**: `004-token-charge` | **Consumer**: integrators using the `bml_connect` gem.

## Reaching the resource

The charge lives on the tokens resource, since it charges a token:

```ruby
client.tokens.charge(...)
```

## The two-step flow

BML requires a transaction to exist before it can be charged. The library makes both steps
visible and **does not** offer a combined call (FR-003, Constitution V).

```ruby
# 1. create the transaction that will be charged
txn = client.transactions.create_v2(
  amount:     10_000,             # the amount lives HERE
  currency:   "MVR",
  customerId: "cus_123",
  localId:    "SUB-2026-09"
)

# 2. charge the stored card against it
charged = client.tokens.charge(
  customer_id:    "cus_123",
  transaction_id: txn.id,
  token_id:       "tok_789"
)

charged.state      # resolved synchronously — no cardholder redirect
```

There is deliberately no `client.tokens.charge_new(amount:, …)`. A single method hiding a
transaction creation behind a name like "charge" would obscure a money-moving side effect, and a
partial failure between the two steps would be invisible.

## `charge(customer_id:, transaction_id:, token_id:, actor: nil)`

All three keywords are **required** and validated locally before any request:

| Rule | Error |
|---|---|
| `customer_id` present and non-blank | `ValidationError(field: :customer_id)` |
| `transaction_id` present and non-blank | `ValidationError(field: :transaction_id)` |
| `token_id` present and non-blank | `ValidationError(field: :token_id)` |
| `actor` does not match a PAN pattern | `ValidationError(field: :actor)` |

Returns `BMLConnect::Models::TransactionRecord` (feature `003`).

> **Which token identifier?** Pass `Token#id` — the same value used in
> `client.tokens.retrieve(customer_id, token_id)`. This is currently an **inference**, not
> documented behavior; see `contracts/bml-remote.md`. The method's own RDoc MUST state the
> confirmed answer once UAT settles it (FR-013).

### No retry — and what to do instead

```ruby
begin
  charged = client.tokens.charge(customer_id: "cus_123",
                                 transaction_id: txn.id, token_id: "tok_789")
rescue BMLConnect::AvailabilityError => e
  # EXACTLY ONE attempt was made. The charge may or may not have been applied.
  # e.message names the transaction id. Reconcile before doing anything else:
  actual = client.transactions.retrieve(txn.id)
  # decide from actual.state — do NOT simply call charge again
end
```

`AvailabilityError` from this method always names the `transaction_id` (FR-005), because the only
safe recovery is to look the transaction up.

### Decline vs. outage

```ruby
charged = client.tokens.charge(...)      # returned => BML answered
case charged.state
when "CONFIRMED" then settle!
else                  dun_customer!      # a decline: do not blindly retry
end
```

A **returned** record means BML answered, whatever the state — that is a business outcome. A
**raised** `AvailabilityError` means BML did not answer — that is a transport outcome. The
library never converts one into the other (FR-007).

## Audit

Every charge emits an audit record — **including failures** (FR-011):

```ruby
{ action: :charge,
  who:     { app_id: "…", actor: "billing:cron" },
  subject: { customer_id: "…", transaction_id: "…", token_id: "…" },
  outcome: :success | :declined | :error,
  at:      Time }
```

No card data, no payment URL. A failed charge is exactly what an audit trail needs to record, so
the sink receives it before the error is re-raised.

## Operations that deliberately do not exist

| Not provided | Why |
|---|---|
| `charge_new(amount:, …)` | Would hide a transaction creation inside a charge (FR-003) |
| `charge` with an `amount:` | The charge schema carries no amount; the transaction governs |
| Automatic retry | No idempotency key is documented; a retry risks a double charge (FR-004) |

A unit test asserts no charge-related method accepts an `amount` keyword (SC-007).
