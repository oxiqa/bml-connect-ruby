# Contract: Remote BML HTTP — Customers

**Feature**: `001-customers-endpoints` | **Counterparty**: Bank of Maldives Connect API v2.0

**Source of truth**: `reference/Connect-API.json`. Every path, method, and field below is quoted
from that document. Anything not in it is marked **[UNVERIFIED]** and MUST NOT be relied on until
observed against UAT (Constitution III).

## Common

**Servers** (from `servers[]`):

| Mode | URL |
|---|---|
| `production` | `https://api.merchants.bankofmaldives.com.mv` |
| `sandbox` | `https://api.uat.merchants.bankofmaldives.com.mv` |

**Auth** (from `components.securitySchemes.Authorization`):

```yaml
type: apiKey
in: header
name: Authorization
```

The header value is the **raw API key**. No `Bearer` prefix. No `X-App-Id` header — the strings
`Bearer`, `X-App-Id` and `appId` do not occur anywhere in the document.

> The retired `bml_tokenization` sent `Authorization: Bearer <key>` plus `X-App-Id`. That is
> wrong on both counts. `BMLConnect::Client#initialize_http_client` already sends the raw key.

**Note the path prefix.** Customer paths are `/public-customers…`, with a hyphen — *not*
`/public/customers`. This is inconsistent with the `/public/…` transaction paths, and it is not
a typo in this document; it is what BML publishes.

**Transport**: JSON over TLS. Timeout plus bounded retry (≤2, exponential backoff) on connection
errors, timeouts and 5xx; `429` honours `Retry-After`. Non-transient failures are never retried.

---

## Create — `POST /public-customers`

Operation id `post-public-customers`, summary "Create New Customer".

**Request** — required: `name`, `email` (both `minLength: 1`):

```json
{
  "name": "Aisha Ali",
  "email": "aisha@example.mv",
  "billingEmail": "billing@example.mv",
  "billingAddress1": "Ameenee Magu",
  "billingAddress2": "Flat 3B",
  "billingCity": "Male",
  "billingCountry": "MV",
  "billingPostCode": "20026",
  "customerGroup": "retail",
  "invoicePrefix": "INV",
  "taxInformation": "GST",
  "taxId": "1234567890"
}
```

**Response `201`** — platform-assigned fields marked ▸:

```json
{
  "id": "…",              ▸
  "name": "Aisha Ali",
  "email": "aisha@example.mv",
  "companyId": "…",       ▸ required in schema
  "currency": "MVR",      ▸ required in schema
  "customerGroupId": "…", ▸
  "deleted": false,       ▸
  "created": "…",         ▸
  "updated": "…",         ▸
  "billingEmail": "…", "billingAddress1": "…", "billingAddress2": "…",
  "billingCity": "…", "billingCountry": "…", "billingPostCode": "…",
  "invoicePrefix": "…", "taxInformation": "…", "taxId": "…"
}
```

Mapping: response → `BMLConnect::Models::Customer`, whitelisted to the attributes above.

---

## List — `GET /public-customers`

Operation id `get-public-customer`, summary "Get List Of Customers".

**Response `200`** — an envelope:

```json
{
  "count": "…",
  "items": [
    { "id": "…", "name": "…", "email": "…", "billingEmail": "…",
      "billingAddress1": "…", "billingAddress2": "…",
      "billingCity": "…", "billingCountry": "…" }
  ]
}
```

`name` and `email` are required on each item; `id` is not marked required in the item schema.

**[UNVERIFIED]** — no pagination parameters are described. `Transactions#list` currently passes
`page`, but nothing in this document confirms `/public-customers` accepts it. Do not send page
parameters until observed. Note: `count` is typed `string` in the document but was **observed as
an Integer** on UAT (2026-09-08); the library's coercion tolerates both.

---

## Retrieve — `GET /public-customers/{customerId}`

Operation id `get-public-customers-customerid`, summary "Get A Customer Detail". Response `200`
carries the same shape as the create response.

Unknown id → **observed `404`** with `{"message":"Customer not found","code":"PP-CU-001"}` →
`NotFoundError` (2026-09-08). Only `200` is documented, but `404` is now confirmed live.

---

## Update — `PATCH /public-customers/{customerId}`

Summary "Update Customer Detail". **`PATCH`, not `PUT`** — and the request schema marks **no
field required**, so this is a partial merge.

**Request** — any subset of:

```
name, email, billingEmail, billingAddress1, billingAddress2, billingCity,
billingCountry, billingPostCode, currency, paymentDue (number),
invoicePrefix, taxInformation, taxId
```

Note `currency` and `paymentDue` are updatable here but are **not** accepted on create.

The library MUST send only keys the caller supplied. Serializing unset fields as `null` risks
erasing stored values.

**Response `200`**: the updated customer.

---

## Archive — `DELETE /public-customers/{customerId}`

Summary "Archive Customer". Documented responses: `204` (success, no body) and `400`.

This is a soft delete — the customer schema carries `deleted: boolean`. The library MUST name
the operation `archive` and MUST NOT present it as a permanent erase.

**[UNVERIFIED]**: the effect on the customer's stored tokens. Do not assume a cascade.

---

## Error mapping

The document declares response codes per operation but no error body schema. Mapping is by
status code, consistent with the existing client:

| HTTP | Library error |
|---|---|
| 400, 422 | `ValidationError` |
| 401, 403 | `AuthenticationError` |
| 404 | `NotFoundError` |
| 409 | `ConflictError` |
| 429 | `RateLimitError` (honour `Retry-After`) |
| 408, 5xx | `AvailabilityError` |

Observed UAT error bodies, for reference:

- BML application layer: `{"statusCode":401,"message":"Unauthorized","code":"PP-C-004"}`
- Gateway, unmatched route: `{"message":"Forbidden"}` — **identical to a path that does not
  exist**, so a `403` here is a routing smell, not necessarily an auth failure.

## Verification status

**Observed live against BML UAT on 2026-09-08** (merchant "TOKEN MERCHANT 3",
company `68c103c4addb83741e30d6a5`), via `spec/integration/customers_uat_spec.rb`.

| Operation | In `Connect-API.json` | Observed on UAT |
|---|---|---|
| `POST /public-customers` | yes | ✅ `201`, returns the created record with a usable `id` |
| `GET /public-customers` | yes | ✅ `200`, `{count, items}` envelope |
| `GET /public-customers/{id}` | yes | ✅ `200` (known id); `404` `PP-CU-001` (unknown id) |
| `PATCH /public-customers/{id}` | yes | ✅ `200`, partial merge confirmed (single field changed, others intact) |
| `DELETE /public-customers/{id}` | yes | ✅ `204`, record then reports `deleted: true` |

The earlier blocker (a development key rejected with `PP-C-004`) is resolved: a provisioned UAT
key now authenticates on `/public/me` and every customer path. All five operations were exercised
end-to-end and passed.

### Live findings — document vs. actual response (resolves `[UNVERIFIED]` markers)

- **`count` is an Integer**, not the `string` the document types it (observed `9`). The library's
  tolerant coercion already handles either form; no change required.
- **Customer responses carry both `_id` and `id`**, equal in value. The library reads `id` (per
  the document) and it is populated. Extra Mongo/ledger fields (`_id`, `__v`, `balanceDue`,
  `customerPayments`, `baseBalanceDue`, `lastTransactionId`, `idempotencyKey`, `source`) are
  present but dropped by the model's whitelist — the intended security behavior.
- **Timestamps are `createdAt`/`updatedAt`**, not the documented `created`/`updated`. The model
  was extended to whitelist the live names (the documented names remain, in case BML aligns).
- **Unknown-id 404 body** is `{"message":"Customer not found","code":"PP-CU-001"}` → mapped to
  `NotFoundError`, message extracted from `message`.

### Still `[UNVERIFIED]`

- **List pagination parameters** — not exercised. The list works with no page parameters; whether
  `/public-customers` accepts any (and their names) remains unobserved. Do not send them until
  confirmed.
- **Archive → stored-token cascade** — depends on feature `002` (tokens). Cannot be observed until
  a customer with tokens can be created; do not assume a cascade.
