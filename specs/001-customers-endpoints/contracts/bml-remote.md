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
parameters until observed. Note also `count` is typed `string`, not integer.

---

## Retrieve — `GET /public-customers/{customerId}`

Operation id `get-public-customers-customerid`, summary "Get A Customer Detail". Response `200`
carries the same shape as the create response.

Unknown id → **[UNVERIFIED]**; expected `404` → `NotFoundError`. Only `200` is documented.

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

| Operation | In `Connect-API.json` | Observed on UAT |
|---|---|---|
| `POST /public-customers` | yes | ☐ pending credentials |
| `GET /public-customers` | yes | ☐ pending credentials |
| `GET /public-customers/{id}` | yes | ☐ pending credentials |
| `PATCH /public-customers/{id}` | yes | ☐ pending credentials |
| `DELETE /public-customers/{id}` | yes | ☐ pending credentials |

The API key in the website's development credentials is rejected by UAT (`PP-C-004`) even on the
known-working `/public/transactions` path, so no operation has been observed live yet. A working
UAT key is a prerequisite for closing this table — see `quickstart.md`.
