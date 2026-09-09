# Contract: Remote BML HTTP — Transactions V2

**Feature**: `003-transactions-v2` | **Counterparty**: Bank of Maldives Connect API v2.0

**Source of truth**: `reference/Connect-API.json`. Anything not in it is marked **[UNVERIFIED]**.

## Common

Servers, auth and transport as in
[`001`](../../001-customers-endpoints/contracts/bml-remote.md#common) — raw `Authorization` API
key, no `Bearer`, no `X-App-Id`, JSON over TLS.

**Retry differs here.** Transaction **creation is never retried automatically** (FR-016): no
server-side idempotency key is documented for this endpoint, so a retried create could produce a
second charge. Retrieve, list and cancel retry normally.

---

## Create — `POST /public/v2/transactions`

Operation id `post-public-v2-transactions`, summary "Create Transaction (V2)".

The request schema is a **`oneOf` with five variants**:

| # | Required | Shape |
|---|---|---|
| 1 | `order` | Shop order with an inline `customer` object |
| 2 | `order` | Shop order with an existing `customerId` |
| 3 | `amount`, `currency` | Direct amount with an existing `customerId` |
| 4 | `amount`, `currency` | Direct amount with an inline `customer` object |
| 5 | `amount`, `currency`, `provider`, `payAmount`, `payCurrency`, `fxQuoteId` | Foreign-exchange |

**This library implements variants 3 and 4.** Variants 1 and 2 require the shops/products surface
which is out of scope; variant 5 requires an FX quote flow that is not documented elsewhere in
the file. Both are recorded as out of scope rather than silently unimplemented.

### Variant 3 request (the primary shape)

```json
{
  "amount": 10000,
  "currency": "MVR",
  "redirectUrl": "https://merchant.example.mv/return",
  "webhook": "https://merchant.example.mv/hooks/bml",
  "localId": "INV/112.33",
  "customerReference": "Basket 392",
  "customerId": "cus_123",
  "expires": "…",
  "tokenizationDetails": {
    "tokenize": true,
    "paymentType": "UNSCHEDULED"
  }
}
```

Variant 4 replaces `customerId` with an inline `customer` object requiring `name` and `email` —
the same shape feature `001` creates, and BML returns a customer id on the transaction.

### `tokenizationDetails` — the tokenization trigger

Quoted from the schema, including BML's own descriptions:

| Field | Required | Description (verbatim from the document) |
|---|---|---|
| `tokenize` | ✔ | "Boolean flag to set true if need to initiate card holder initiated transaction and false if merchant initiated" |
| `paymentType` | ✔ | "Can be \"RECURRING\" or \"UNSCHEDULED\" -- recurring for recurring payments where recurring frequency and expiry date are mandatory in that case, and unscheduled is for ad-hoc payments" |
| `recurringFrequency` | when `RECURRING` | "DAILY, WEEKLY, BIWEEKLY, FORTNIGHTLY, MONTHLY, QUARTERLY, YEARLY, AD_HOC" |
| `expiryDate` | when `RECURRING` | "format \"yyyy-mm-dd\" should be a future date, when the recurring payments would expire" |

These conditional rules are enforced **locally**, before any remote call (FR-003, FR-004).

Note `recurringFrequency`'s allowed values are given in prose, not as a JSON `enum` — the document
declares no enums for them. The library validates against the listed set and MUST surface an
unexpected-but-listed value rather than silently dropping it.

### Response `201`

```json
{
  "id": "…", "created": "…", "updated": "…",
  "amount": 10000, "currency": "MVR", "payCurrency": "…",
  "merchantId": "…", "provider": "…", "providerHistory": [],
  "state": "…", "accountingState": "…",
  "qr": { "url": "…" },
  "securityWord": "…", "canRefundIfConfirmed": true,
  "externalImport": false, "externalId": "…", "localId": "…",
  "paymentToken": "…",
  "history": [ { "state": "…", "updatedDate": "…", "trigger": "…" } ],
  "appVersion": "…", "apiVersion": "…",
  "deviceId": "…", "originalDeviceId": "…",
  "redirectUrl": "…", "costStructure": {}, "providerDisplayName": "…"
}
```

**[UNVERIFIED]** — the hosted payment URL field name on a v2 response. The v1 response the
website consumes carries `url` (`resp.body[:url]`), but `url` does **not** appear in the v2
response schema; `qr.url` and `redirectUrl` do. Since `redirectUrl` is also a request field, it
is likely an echo rather than the payment link. **This must be observed before v2 create can be
used in production** — without the right field the cardholder cannot be sent anywhere.

**[UNVERIFIED]** — `state` values. The document declares **no enum**. Production code branches on
`CONFIRMED`, `CANCELLED` and `FAILED`, observed from the v1 API. The library passes `state`
through unchanged and does **not** normalize it.

---

## The legacy v1 create — `POST /public/transactions`

**Not in `Connect-API.json`.** The document contains `/public/transactions/{transactionId}` for
retrieve and update, but no collection-level `POST`.

It is nonetheless **live**: UAT answers it with an application-level
`{"statusCode":401,"message":"Unauthorized","code":"PP-C-004"}`, which is the BML application
rejecting a credential — distinct from the gateway's `{"message":"Forbidden"}` returned for a
route that does not exist.

Status: **live, undocumented, deprecated.** `BMLConnect::Transactions#create` keeps calling it
unchanged (FR-010, FR-011). This is the one deliberate exception to Constitution III's
"every path traceable to the document" rule, recorded here rather than hidden.

### Request signing

The gem computes `Digest::SHA1.base64digest("amount=…&currency=…&apiKey=…")` and sends it as
`signature`, along with `apiVersion`, `appVersion` and `signMethod`.

**The string `signature` appears zero times in `Connect-API.json`.** (`signMethod` and
`apiVersion` do appear, three times each.)

Decision: keep signing on v1, where it demonstrably works; send **no** signature on v2 until
observation settles it (FR-012). **[UNVERIFIED]** — whether v2 requires, ignores, or rejects a
signature.

---

## Retrieve — `GET /public/transactions/{transactionId}`

Summary "Get Transaction". Response `200`. Shared by v1- and v2-created transactions.

This is what `BMLConnect::Transactions#get` already calls. Unchanged.

---

## Update — `PATCH /public/transactions/{transactionId}`

Summary "Update Transaction". Takes a `Content-Type` **header parameter** explicitly, unusually.

Request — any of: `customerReference`, `localData`, `pnr`. None required. Partial merge; send only
supplied keys. Response `200`.

---

## Capture — `POST /public/transactions/{transactionId}/capture`

Summary "Capture Pre-Authorized Transaction". Request requires **`id`** and **`amount`**.

Note `id` is required in the body *and* the transaction id is in the path. **[UNVERIFIED]**
whether the body `id` is the transaction id repeated or something else. Documented response:
`2XX` (a range, not a specific code).

The library validates `amount` locally before sending, under the same positive-Integer/minor-units
rule as create (FR-008) — a Float, String, zero, or negative is rejected with no remote call.

---

## Cancel — `POST /public/transactions/{transactionId}/cancel`

Summary "Cancel a Transaction". No request body documented. Response `200`.

---

## Error mapping

Per the shared table in `001`. Create is **not** retried on `5xx` or timeout (FR-016); the error
propagates on the first attempt so the caller can reconcile by `localId` rather than risk a
second charge.

## Verification status

| Operation | In `Connect-API.json` | Observed on UAT |
|---|---|---|
| `POST /public/v2/transactions` | yes | ☐ pending credentials |
| `POST /public/transactions` (v1) | **no — undocumented** | ✔ live (PP-C-004 auth error, not a 403) |
| `GET /public/transactions/{id}` | yes | ☐ pending credentials |
| `PATCH /public/transactions/{id}` | yes | ☐ pending credentials |
| `POST …/{id}/capture` | yes | ☐ pending credentials |
| `POST …/{id}/cancel` | yes | ☐ pending credentials |

Open `[UNVERIFIED]` items:

1. **The payment-URL field on a v2 response** — blocks production use of v2 create.
2. Whether v2 accepts, ignores, or rejects a `signature`.
3. `state` values returned by v2.
4. The body `id` on capture.
5. Whether `tokenizationDetails` works without a `customerId`.
6. Whether a v2-created transaction is retrievable at the same v1 retrieve path (assumed yes).
