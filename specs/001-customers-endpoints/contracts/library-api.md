# Contract: Library API — Customers

**Feature**: `001-customers-endpoints` | **Consumer**: integrators using the `bml_connect` gem.

This is the **public surface** this feature adds. It follows the resource pattern already
established by `BMLConnect::Transactions`, reached through a configured client.

## Reaching the resource

```ruby
client = BMLConnect::Client.new            # or with explicit api_key:/app_id:/mode:
client.customers                           # => BMLConnect::Customers
```

`Client#customers` is memoized and bound to the client's mode and credentials.

## Operations

### `create(details, actor: nil)`

```ruby
customer = client.customers.create(
  name:  "Aisha Ali",                      # required
  email: "aisha@example.mv",               # required
  billingCity: "Male"                      # optional; any documented field
)
customer.id        # => "…"  BML-assigned
customer.companyId # => "…"
```

- Validates `name` and `email` are present and non-blank **before** any remote call; raises
  `BMLConnect::ValidationError` naming the field otherwise.
- Rejects any value matching a PAN pattern, in any field, with `ValidationError`.
- Returns `BMLConnect::Models::Customer`.
- Emits an audit record (`action: :create`).

### `retrieve(customer_id, actor: nil)`

```ruby
customer = client.customers.retrieve("cus_…")
```

Raises `NotFoundError` for an unknown id. Not audited (read).

### `list(actor: nil)`

```ruby
page = client.customers.list
page.count             # => Integer (coerced; BML sends a string)
page.items             # => [BMLConnect::Models::Customer, …]
page.empty?            # => Boolean
page.each { |c| … }    # Enumerable
```

Returns `BMLConnect::Models::CustomerList`. An empty result is an empty list, never an error.
Not audited (read).

> No page parameters are exposed. `Connect-API.json` documents none for this path; adding them
> requires UAT confirmation first (Constitution III).

### `update(customer_id, changes, actor: nil)`

```ruby
customer = client.customers.update("cus_…", billingCity: "Hulhumale")
```

- **Partial merge.** Only the keys supplied are sent. Unsupplied fields are omitted from the
  request body entirely — never serialized as `null`.
- Raises `ValidationError` if `changes` is empty, rather than issuing a no-op request.
- Raises `NotFoundError` for an unknown id.
- Emits an audit record (`action: :update`).

### `archive(customer_id, actor: nil)`

```ruby
client.customers.archive("cus_…")   # => true
```

- Named `archive`, not `delete`, because BML soft-deletes (`deleted: boolean`).
- Returns `true` on `204`. Emits an audit record (`action: :archive`).

## Value objects

### `BMLConnect::Models::Customer`

Read-only. Attributes are **whitelisted** — any other key BML returns is dropped, so an
unexpected sensitive field cannot leak onto the object:

```
id  name  email  companyId  currency  customerGroupId  deleted
billingEmail  billingAddress1  billingAddress2  billingCity
billingCountry  billingPostCode  invoicePrefix  taxInformation  taxId
created  updated
```

`#to_h`, `#==`, `#inspect` are limited to those attributes. `#deleted?` is a convenience
predicate.

### `BMLConnect::Models::CustomerList`

`count`, `items`, `empty?`, `size`, and `Enumerable`.

## Errors

All inherit `BMLConnect::Error`:

| Error | Raised when |
|---|---|
| `ValidationError` | local validation failed, or BML returned 400/422. Carries `#field`. |
| `AuthenticationError` | 401/403 |
| `NotFoundError` | 404 |
| `ConflictError` | 409. Carries `#body`. |
| `RateLimitError` | 429. Carries `#retry_after`. |
| `AvailabilityError` | timeout, connection failure, 408, or 5xx after retries |

`ValidationError` raised locally never reaches the network.

## Audit records

State-changing operations (`create`, `update`, `archive`) emit a record to the client's
configured `audit_sink` (any object responding to `#call` or `#<<`):

```ruby
{ action: :create, who: { app_id: "…", actor: "ops:jane" },
  subject: { customer_id: "…" }, outcome: :success, at: Time }
```

Contains no card data. The `actor:` keyword is optional and rejected if it matches a PAN
pattern.

## Backward compatibility

Purely additive. `client.transactions` and every existing method keep their current behavior and
signatures. No existing consumer needs to change.
