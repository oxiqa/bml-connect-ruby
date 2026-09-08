# Contract: Remote BML HTTP — Token Charge

**Feature**: `004-token-charge` | **Counterparty**: Bank of Maldives Connect API v2.0

**Source of truth**: `reference/Connect-API.json`. Anything not in it is **[UNVERIFIED]**.

## Common

Servers, auth and transport as in
[`001`](../../001-customers-endpoints/contracts/bml-remote.md#common) — raw `Authorization` API
key, no `Bearer`, no `X-App-Id`, JSON over TLS.

**No automatic retry, ever.** This endpoint moves money and no idempotency key is documented for
it. A retried charge could take payment twice.

---

## Charge — `POST /public-customers/charge`

Operation id `post-public-charge`, summary "Charge Stored Token".

Note the path: it sits under `/public-customers` — the customers family — **not** under
`/public/transactions`, even though it returns a transaction.

### Request — all three fields required

```json
{
  "customerId":    "cus_123",
  "transactionId": "txn_456",
  "tokenId":       "tok_789"
}
```

That is the entire schema. In particular:

- **No `amount`.** The transaction named by `transactionId` supplies it. A caller wanting to
  charge a different amount must create a different transaction.
- **No `currency`.** Same reason.
- **No card data of any kind.**

### ⚠️ `tokenId` — unresolved and blocking

A token object carries **both** an `id` and a `token`. The document does not say which one
`tokenId` refers to.

The inference is `Token#id`, because the path parameter for
`GET/DELETE /public-customers/{customerId}/tokens/{tokenId}` is also called `tokenId` and there
resolves to the token's `id`. Consistent naming makes this likely — **but likely is not
documented**, and charging the wrong identifier is a money-movement defect.

**This is the single most important open question in the migration.** Resolution: charge a known
token on UAT with `Token#id`; if rejected, retry once with `Token#token`; record the answer here
and in `data-model.md`. Feature `002` tasks T011/T016 carry the same item.

### Response `200` — a full transaction record

```json
{
  "id": "…", "created": "…", "updated": "…",
  "amount": 10000, "merchantId": "…", "currency": "MVR", "payCurrency": "…",
  "provider": "…", "providerHistory": [], "providerDisplayName": "…",
  "state": "…", "accountingState": "…",
  "qr": { "url": "…" },
  "securityWord": "…", "canRefundIfConfirmed": true,
  "externalImport": false, "externalId": "…", "localId": "…",
  "paymentToken": "…",
  "history": [ { "state": "…", "updatedDate": "…", "trigger": "…" } ],
  "appVersion": "…", "apiVersion": "…",
  "deviceId": "…", "originalDeviceId": "…",
  "redirectUrl": "…", "costStructure": {}
}
```

Identical in shape to the `POST /public/v2/transactions` response, so it maps to the same
`BMLConnect::Models::TransactionRecord` (feature `003`).

**[UNVERIFIED]** — `state` values on a charge response. No enum is declared anywhere in the
document. Whether a declined charge returns `200` with a failed `state` or a non-2xx status
**changes how callers branch** and must be observed. The library passes `state` through verbatim
either way.

**Note**: the response carries `qr.url` and `redirectUrl` like the redirect flow, though a
merchant-initiated charge needs no cardholder redirect. Probably vestigial fields on a shared
schema. Callers MUST NOT redirect on a charge response.

---

## Error mapping

Per the shared table in `001`, with one hard exception: **`AvailabilityError` is raised after
exactly one attempt.** No retry, no backoff, no second request. The error message MUST name the
`transactionId` so the caller can reconcile by retrieving it
(`GET /public/transactions/{transactionId}`).

### The decline / outage distinction

| Outcome | Shape | Caller should |
|---|---|---|
| Charge applied | `200`, transaction in a success state | settle |
| Card declined | **[UNVERIFIED]** — `200` with a failed state, or 4xx | dun the customer; do not retry blindly |
| Rate limited | `429` | back off and retry later |
| BML unreachable / timeout | raised `AvailabilityError`, one attempt | **retrieve the transaction to find out whether it was applied**, then decide |

Collapsing the last two rows is the failure mode to avoid: retrying a decline annoys customers
and can incur scheme fees, while treating an outage as a decline loses revenue (FR-007, SC-005).

---

## Verification status

| Operation | In `Connect-API.json` | Observed on UAT |
|---|---|---|
| `POST /public-customers/charge` | yes | ☐ pending credentials |

Open `[UNVERIFIED]` items:

1. **Whether `tokenId` is `Token#id` or `Token#token`** — ⛔ blocks release.
2. `state` values on a charge response, and whether a decline is `200`-with-failed-state or
   non-2xx.
3. Whether charging an already-charged transaction is rejected or double-charges.
4. Whether a deleted token is rejected with a distinguishable error.
5. Whether a token/customer mismatch is rejected.

Items 3, 4 and 5 are all cases where an unexpected success would be worse than a failure, so each
gets an explicit UAT test rather than an assumption.
