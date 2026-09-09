# Data Model: Token Charge

**Feature**: `004-token-charge` | **Derived from**: `reference/Connect-API.json`

This feature introduces **one input structure and no new response entity**. The charge response
is a transaction record, already modelled by feature `003`.

## Entity: Charge Request (input only)

| Field | Type | Required | Source |
|---|---|---|---|
| `customerId` | string | ✔ | `Customer#id` (feature `001`) |
| `transactionId` | string | ✔ | `TransactionRecord#id` (feature `003`) |
| `tokenId` | string | ✔ | `Token#id` — **see below** (feature `002`) |

That is the complete schema. Never serialized back to the caller; it exists only as a request
body.

### What is deliberately absent

| Absent | Consequence |
|---|---|
| `amount` | The transaction's amount governs. To charge a different amount, create a different transaction. |
| `currency` | Same. |
| Any card field | The card is referenced only by token. |
| An idempotency key | **This is why the charge is never auto-retried.** |

The absence of an idempotency key is the single most consequential fact in this data model. It is
what makes retry unsafe and what forces reconciliation-by-retrieval as the documented recovery
path.

### ⚠️ `tokenId` — the unresolved identifier

A token carries both:

```ruby
token.id      # => "tok_789"   ← the path parameter for retrieve/delete
token.token   # => "…"         ← the token value itself
```

`tokenId` is inferred to be `token.id`, because the retrieve and delete path parameter is
likewise named `tokenId` and resolves to `id` there. The document never states it.

**Until confirmed, this feature does not ship.** Resolution procedure:

1. Store a card via a tokenizing transaction (feature `003`).
2. List the customer's tokens; keep both `id` and `token`.
3. Create a small transaction and charge with `tokenId: token.id`.
4. If rejected, create a **new** transaction and charge with `tokenId: token.token`. Never reuse
   the first transaction — an already-charged transaction is itself an unverified case.
5. Record the answer in `contracts/bml-remote.md`, here, and in the method's RDoc.

## Validation (local, pre-remote)

| Rule | Error field |
|---|---|
| `customer_id` present and non-blank | `:customer_id` |
| `transaction_id` present and non-blank | `:transaction_id` |
| `token_id` present and non-blank | `:token_id` |
| `actor` does not match a PAN pattern | `:actor` |

All three ids are opaque strings; the library validates presence only and does not infer format.

## Response

`BMLConnect::Models::TransactionRecord` — defined by feature `003`, reused verbatim. The charge
response schema is identical to the v2 create response schema.

`state` is passed through unchanged. `qr.url` and `redirectUrl` may be present but are vestigial
here: a merchant-initiated charge involves no cardholder redirect, and callers MUST NOT redirect
on a charge response.

## Outcome taxonomy

The distinction callers depend on (FR-007):

```
client.customers.charge(...)
        │
        ├── returns a TransactionRecord ────► BML answered. A BUSINESS outcome.
        │        ├── state = success  ──────► settle
        │        └── state = failed   ──────► declined; dun. Do NOT blindly retry
        │
        └── raises ─────────────────────────► a TRANSPORT or VALIDATION outcome
                 ├── ValidationError    ────► local; no request was made
                 ├── AuthenticationError ───► credentials
                 ├── NotFoundError      ────► unknown customer/transaction/token
                 ├── RateLimitError     ────► back off, retry later
                 └── AvailabilityError  ────► ONE attempt made; outcome UNKNOWN.
                                              Retrieve the transaction to find out.
```

The library never converts a raise into a return or vice versa. `AvailabilityError` is the only
state in the system where the outcome is genuinely unknown, which is why its message names the
`transactionId`.

## Relationships

```
Customer (001) ──┐
                 ├──► Charge Request ──► TransactionRecord (003)
Token (002) ─────┤
                 │
Transaction (003)┘
```

The charge is the convergence point of the other three features: it consumes an id from each.

## Lifecycle position

```
001 create customer
      ↓
003 create tokenizing transaction ──► cardholder completes on hosted page
      ↓
002 token now stored
      ↓
003 create a new transaction (the one to be charged)
      ↓
004 CHARGE  ← this feature
      ↓
    settled, or declined, or unknown-pending-reconciliation
```
