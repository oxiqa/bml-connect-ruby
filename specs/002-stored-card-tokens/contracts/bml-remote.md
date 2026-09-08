# Contract: Remote BML HTTP — Stored Card Tokens

**Feature**: `002-stored-card-tokens` | **Counterparty**: Bank of Maldives Connect API v2.0

**Source of truth**: `reference/Connect-API.json`. Anything not in it is marked **[UNVERIFIED]**.

## Common

Servers, auth, and transport are as documented in
[`001-customers-endpoints/contracts/bml-remote.md`](../../001-customers-endpoints/contracts/bml-remote.md#common):
raw `Authorization` API key, no `Bearer`, no `X-App-Id`, JSON over TLS, bounded retry.

**All token paths are nested under a customer.** There is no top-level `/tokens` path. A token
cannot be addressed without its `customerId`.

---

## There is no create endpoint

`Connect-API.json` contains **no** operation that issues a token. The complete set of token paths
is:

```
GET    /public-customers/{customerId}/tokens
GET    /public-customers/{customerId}/tokens/{tokenId}
DELETE /public-customers/{customerId}/tokens/{tokenId}
```

Read and delete. Nothing else.

A token comes into existence as a **side effect of a transaction**: `POST /public/v2/transactions`
with `tokenizationDetails.tokenize = true`, completed by the cardholder on BML's hosted page
(feature `003`). The library MUST NOT expose a `create`, `tokenize`, `store`, or `save` method on
this resource.

> The retired `bml_tokenization` specified `POST /tokens` taking a single-use `card_handle`.
> Neither the path nor the concept exists. UAT returns `403 {"message":"Forbidden"}` for
> `/tokens` — byte-identical to a deliberately garbage path.

---

## List — `GET /public-customers/{customerId}/tokens`

Operation id `get-public-customers-tokens`, summary "Get List Of Tokens For Customer".

**Response `200`** — an array of token objects. Fields marked ▸ are required by the schema:

```json
[
  {
    "id": "…",                    ▸
    "brand": "VISA",              ▸
    "provider": "…",              ▸
    "token": "…",                 ▸
    "tokenType": "…",             ▸
    "deleted": false,
    "tokenProvider": "…",
    "tokenAgreementId": "…",
    "tokenAgreementType": "…",
    "tokenExpiryMonth": "12",
    "tokenExpiryYear": "2027",
    "paddedCardNumber": "424242******4242",
    "customerId": "…",
    "companyId": "…",
    "created": "…",
    "updated": "…"
  }
]
```

**Contract oddity, recorded deliberately**: in the document this schema is attached to the
operation's **`requestBody`**, not its response — a `GET` with a request body describing a list of
tokens. This is near-certainly an authoring error in BML's export; the fields are unambiguously a
response shape. The library MUST send **no body** on this `GET` and MUST parse the array as the
response. **[UNVERIFIED]** — confirm the actual response envelope against UAT. In particular,
whether it is a bare array or a `{count, items}` envelope like `/public-customers` is unknown.

`paddedCardNumber` is BML's masked summary. The library MUST expose it under that name and MUST
NOT derive a `last_four` or `scheme` field from it.

**[UNVERIFIED]**: pagination parameters. None are documented. Do not send any.

---

## Retrieve — `GET /public-customers/{customerId}/tokens/{tokenId}`

Summary "Get Single Token For Customer". Documented response: `200`, carrying one token object of
the shape above.

**[UNVERIFIED]**: the not-found body and status for an unknown `tokenId`, and the behavior when a
valid `tokenId` is requested under a `customerId` that does not own it. The library assumes `404`
→ `NotFoundError` and MUST verify the cross-customer case against UAT — a token leaking across
customers would be a security defect, so this test is mandatory, not optional (see tasks T024).

---

## Delete — `DELETE /public-customers/{customerId}/tokens/{tokenId}`

Summary "Delete Token For A Customer". Documented responses: `204` (success, no body) and `400`.

Soft delete — the token schema carries `deleted: boolean`. The library returns `true` on `204`.

**[UNVERIFIED]**: whether a deleted token still appears in the list response with `deleted: true`,
or disappears from it. This changes how a caller filters, so it must be observed.

**[UNVERIFIED]**: the effect on an outstanding recurring agreement (`tokenAgreementId`). Do not
assume a cascade in either direction.

---

## Error mapping

Per the shared table in `001-customers-endpoints/contracts/bml-remote.md`.

One trap specific to this feature: an **empty token list** and an **auth failure** must never be
confusable. If BML returns `200` with an empty array for a customer with no cards, that is an
empty collection. A `401`/`403` is an error and MUST raise. The library MUST NOT rescue an
authentication failure into an empty list — a caller would read "this customer has no saved
cards" when the truth is "our credentials are broken".

## Verification status

| Operation | In `Connect-API.json` | Observed on UAT |
|---|---|---|
| `GET …/{customerId}/tokens` | yes | ☐ pending credentials |
| `GET …/{customerId}/tokens/{tokenId}` | yes | ☐ pending credentials |
| `DELETE …/{customerId}/tokens/{tokenId}` | yes | ☐ pending credentials |

Open `[UNVERIFIED]` items to resolve when a working UAT key is available:

1. List response envelope — bare array or `{count, items}`?
2. The `requestBody`-vs-response schema anomaly on list.
3. Not-found status and body for an unknown `tokenId`.
4. Cross-customer token access (**security-relevant — must be tested**).
5. Whether deleted tokens remain visible in the list.
6. Effect of deletion on a recurring `tokenAgreementId`.
7. Pagination parameters, if any.
