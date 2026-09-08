# API Reference

## `Connect-API.json`

The authoritative BML Connect API contract, vendored into this repository.

| | |
|---|---|
| Format | OpenAPI 3.1.0 |
| Title | Connect API |
| Version | 2.0 |
| Production server | `https://api.merchants.bankofmaldives.com.mv` |
| UAT / development server | `https://api.uat.merchants.bankofmaldives.com.mv` |
| Auth scheme | `apiKey`, `in: header`, name `Authorization` |

### Why it is vendored

BML's documentation portal (`docs.merchants.bankofmaldives.com.mv`, which 301-redirects to
`bankofmaldives.stoplight.io`) is a client-rendered application. Its content cannot be fetched,
diffed, or cited from a review; the page source is a JavaScript bundle with no documentation
in it. Vendoring the exported OpenAPI document gives every spec and contract test an exact,
versioned artifact to cite, and makes a BML-side API change a reviewable diff.

Per the constitution (Principle III), where this library and this document disagree, **the
document wins**.

### Endpoint inventory

Endpoints in scope for the `specs/` features:

| Path | Methods | Feature |
|---|---|---|
| `/public-customers` | GET, POST | `001-customers-endpoints` |
| `/public-customers/{customerId}` | GET, PATCH, DELETE | `001-customers-endpoints` |
| `/public-customers/{customerId}/tokens` | GET | `002-stored-card-tokens` |
| `/public-customers/{customerId}/tokens/{tokenId}` | GET, DELETE | `002-stored-card-tokens` |
| `/public/v2/transactions` | POST | `003-transactions-v2` |
| `/public/transactions/{transactionId}` | GET, PATCH | `003-transactions-v2` |
| `/public/transactions/{transactionId}/capture` | POST | `003-transactions-v2` |
| `/public/transactions/{transactionId}/cancel` | POST | `003-transactions-v2` |
| `/public-customers/charge` | POST | `004-token-charge` |

Documented but **out of scope** for the current features — shops, products, categories, taxes,
custom fees, order fields, webhooks, `/public/me`, and the transaction `send-sms` / `send-email`
notification endpoints. They are part of the MPOS/storefront surface, not the payment and
tokenization flows this gem targets.

### Notable absences

Two things this gem's existing code does that the published spec does **not** describe:

- **`POST /public/transactions` (v1 create).** Only `/public/v2/transactions` is documented for
  creation; the v1 path appears solely as `/public/transactions/{transactionId}` for
  retrieve/update. The v1 create endpoint is still live (it answers with an application-level
  `PP-C-004` auth error rather than a gateway 403), but it is undocumented. See
  `specs/003-transactions-v2/research.md`.
- **Request signing.** The string `signature` appears **zero** times in the document. The
  current `BMLConnect::Crypt::Signature` SHA1 digest is not part of the published v2 contract.

Both are tracked as `[UNVERIFIED]` items in `specs/003-transactions-v2/contracts/bml-remote.md`.

### Updating

Replace this file wholesale from BML's Stoplight export, as a standalone commit. Then re-check
every `specs/*/contracts/bml-remote.md` against it and record the diff in `CHANGELOG.md`.
