# Feature Specification: Stored Card Tokens

**Feature Branch**: `002-stored-card-tokens`

**Created**: 2026-09-07

**Status**: Draft

**Input**: Merged and realigned from `bml_tokenization/specs/002-card-on-file-endpoints` and
`bml_tokenization/specs/004-tokenization-endpoints` against `reference/Connect-API.json`. See
[MIGRATION.md](../../MIGRATION.md).

## Why two retired features became one

The retired gem modelled "card on file" and "tokenization" as separate resources with separate
lifecycles — a token was issued at `POST /tokens`, then *associated* with a customer as a
card-on-file record. **BML has no such split.** There is one object: a token belonging to a
customer, reachable only at `/public-customers/{customerId}/tokens`. A stored card *is* a token.
Keeping two features would mean two specs describing one resource.

## Clarifications

### Session 2026-09-08

- Q: On a `429` rate-limit or a transient availability error (timeout / `5xx`), should the library
  auto-retry or surface immediately? → A: **Retry all three operations** (list, retrieve, delete)
  with bounded exponential backoff, relying on the delete's soft-delete idempotency. When retries
  are exhausted, surface the original distinguishable error (rate-limit vs availability).
- Q: How does a caller supply the audit "actor reference" for a delete? → A: As a **per-call
  keyword argument** on the delete operation, scoped to that one call; when omitted the audit
  "who" is the configured App ID alone. The argument MUST NOT accept cardholder data.

### Session 2026-09-07

- Q: How is a token created? → A: **Not by this feature.** There is no create or tokenize
  endpoint anywhere in `Connect-API.json`. A token is a side effect of a transaction that carries
  `tokenizationDetails.tokenize = true` — feature `003`. This feature covers only reading and
  deleting tokens that already exist. This is the single largest correction from the retired
  specs, which specified a `POST /tokens` endpoint that does not exist.
- Q: Does the retired `card_handle` input survive? → A: No. There is no hosted-capture handle in
  BML Connect. The cardholder enters card details on BML's hosted payment page during a
  transaction; the library never sees a handle, a PAN, or a CVV at any point.
- Q: Are tokens addressable without a customer? → A: No. Every token path is nested under
  `/public-customers/{customerId}`, so a `customerId` is required for every operation. A bare
  token id is not sufficient.
- Q: Is token deletion terminal? → A: `DELETE` returns `204` and the token schema carries
  `deleted: boolean`, so it is a soft delete like customer archive. No un-delete is documented.
- Q: What is the masked card summary? → A: `paddedCardNumber` (BML's own field name), plus
  `brand`, `tokenExpiryMonth`, and `tokenExpiryYear`. The library MUST NOT invent a `last_four`
  or `scheme` field; it mirrors BML's names.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - List a customer's stored cards (Priority: P1)

An integrator needs to show a customer which cards they have saved, so the customer can pick one
for a repeat payment or remove one they no longer use.

**Why this priority**: This is the primary reason the resource exists. Without it an integrator
holding a `customerId` has no way to discover the `tokenId` that every charge (feature `004`)
requires. It is the minimum viable slice.

**Independent Test**: Complete a tokenizing transaction for a customer, then list that customer's
tokens and confirm the new token appears with a masked summary and no full card number.

**Acceptance Scenarios**:

1. **Given** a customer with at least one stored card, **When** the integrator lists their
   tokens, **Then** each entry is returned with `id`, `brand`, `provider`, `token`, `tokenType`
   and a masked `paddedCardNumber`, and **no** full card number or security code appears
   anywhere.
2. **Given** a customer with no stored cards, **When** the integrator lists their tokens,
   **Then** an empty collection is returned — not an error.
3. **Given** a customer id that matches no customer, **When** tokens are listed, **Then** a
   not-found error is raised, distinguishable from an empty result.
4. **Given** a client configured for sandbox, **When** tokens are listed, **Then** only UAT
   tokens are visible; a token stored in production is never returned.

---

### User Story 2 - Retrieve one stored card (Priority: P2)

An integrator holds a `tokenId` and needs its current details — to confirm it is still usable, or
to display the card the customer is about to be charged on.

**Why this priority**: Useful for confirmation before a charge and for display, but a caller who
has just listed tokens already holds the same data, so it ranks below listing.

**Independent Test**: List a customer's tokens, retrieve one by id, and confirm the record
matches the list entry.

**Acceptance Scenarios**:

1. **Given** an existing customer id and token id, **When** the integrator retrieves the token,
   **Then** the current record is returned with its masked summary and `deleted` flag.
2. **Given** a token id that matches no token for that customer, **When** retrieved, **Then** a
   not-found error is raised.
3. **Given** a token id belonging to a *different* customer, **When** retrieved under the wrong
   customer id, **Then** it is not returned. Tokens are scoped to their customer.

---

### User Story 3 - Delete a stored card (Priority: P2)

A customer asks for a saved card to be removed, or the merchant must remove one on suspected
compromise or expiry.

**Why this priority**: Required for customer control and data minimisation, and a compliance
expectation, but not part of the store-and-charge loop.

**Independent Test**: Store a card, delete the token, and confirm it no longer appears in the
customer's token list and can no longer be charged.

**Acceptance Scenarios**:

1. **Given** an existing token, **When** the integrator deletes it, **Then** the operation
   succeeds with no response body and the token no longer appears as active for that customer.
2. **Given** a token id that matches no token, **When** deletion is attempted, **Then** an error
   is raised and no other token is affected.
3. **Given** a deleted token, **When** a charge is attempted against it (feature `004`), **Then**
   the charge is rejected.

---

### Edge Cases

- Misconfigured client: MUST raise an authentication/configuration error rather than returning an
  empty token list. An empty list and an auth failure MUST NOT be confusable — this matters
  because "customer has no saved cards" and "our key is broken" would otherwise look identical.
- Remote outage or timeout: the library MUST retry with bounded exponential backoff and, once
  retries are exhausted, MUST raise a distinguishable availability error and MUST NOT return a
  partial collection.
- Rate limiting (`429`): the library MUST retry with bounded exponential backoff and, once retries
  are exhausted, MUST raise a distinguishable rate-limit error separate from an availability error.
- A caller attempting to obtain the full card number from a token: the library MUST expose no
  such operation. There is no detokenization endpoint in the contract and none will be added.
- A token whose card has expired at the issuer: the library reports `tokenExpiryMonth` /
  `tokenExpiryYear` as returned and MUST NOT compute or assert usability itself — BML decides at
  charge time.
- Deleting a token that a scheduled recurring agreement still references: BML's behavior is
  **[UNVERIFIED]**; the library MUST NOT assume a cascade.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose stored-card tokens as a resource reachable through the
  configured `BMLConnect::Client` (`client.tokens`), addressed by `customerId`.
- **FR-002**: The library MUST allow listing a customer's tokens via
  `GET /public-customers/{customerId}/tokens`.
- **FR-003**: The library MUST allow retrieving a single token via
  `GET /public-customers/{customerId}/tokens/{tokenId}`.
- **FR-004**: The library MUST allow deleting a token via
  `DELETE /public-customers/{customerId}/tokens/{tokenId}`, treating `204` as success.
- **FR-005**: The library MUST NOT expose any operation that creates or issues a token. Token
  creation happens only through a transaction carrying `tokenizationDetails` (feature `003`).
  Any method suggesting otherwise MUST NOT exist.
- **FR-006**: The library MUST NOT accept a card number, security code, expiry, or any
  hosted-capture handle as input to any operation in this feature.
- **FR-007**: The library MUST represent a stored card only by BML's own fields — `token`,
  `brand`, `paddedCardNumber`, `tokenExpiryMonth`, `tokenExpiryYear` — and MUST NEVER return,
  log, or persist a full card number or security code.
- **FR-008**: The library MUST provide no detokenization operation of any kind.
- **FR-009**: Response objects MUST whitelist attributes, dropping any unknown key BML returns,
  so an unexpected sensitive field cannot reach a caller, a log, or an audit record.
- **FR-010**: The library MUST validate that `customerId` (and `tokenId` where applicable) are
  present and non-blank before contacting BML, raising an error naming the field with no remote
  call.
- **FR-011**: The library MUST perform every operation against the environment selected on the
  client and MUST NOT cross environments.
- **FR-012**: The library MUST authenticate using the client's raw `Authorization` API key per
  `Connect-API.json` `securitySchemes` — no `Bearer` prefix, no `X-App-Id`.
- **FR-013**: The library MUST surface remote failures as distinguishable errors — validation,
  not-found, authentication, rate-limit, availability.
- **FR-013a**: On a `429` rate-limit or a transient availability failure (timeout / `5xx`), the
  library MUST retry the operation — including `delete`, which is safe to repeat because deletion
  is idempotent (soft delete) — using bounded exponential backoff. Retry counts and backoff bounds
  MUST be configurable on the client. Once retries are exhausted, the library MUST raise the
  original distinguishable error (rate-limit vs availability). Non-transient errors (validation,
  not-found, authentication) MUST NOT be retried.
- **FR-014**: Token deletion MUST emit an audit record capturing who, what, when, and outcome.
  Reads (list, retrieve) are not audited.
- **FR-015**: The audit "who" MUST default to the configured App ID plus an optional actor
  reference, which MUST NOT contain cardholder data. The actor reference MUST be supplied as a
  per-call keyword argument on the delete operation, scoped to that single call; when omitted the
  "who" is the configured App ID alone.
- **FR-016**: An empty token collection MUST be returned as an empty collection, never as an
  error, and MUST be distinguishable from an authentication failure.
- **FR-017**: Every operation MUST be independently testable against UAT without production
  credentials.

### Key Entities *(include if feature involves data)*

- **Token**: A stored card belonging to a customer. Required by BML's schema: `id`, `brand`,
  `provider`, `token`, `tokenType`. Optional: `deleted`, `tokenProvider`, `tokenAgreementId`,
  `tokenAgreementType`, `tokenExpiryMonth`, `tokenExpiryYear`, `paddedCardNumber`, `customerId`,
  `companyId`, `created`, `updated`. The `token` value is what feature `004` charges against —
  though the charge endpoint takes `tokenId`, not `token`; see `data-model.md`.
- **Token Collection**: The set of a customer's tokens, scoped to one `customerId`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An integrator holding a `customerId` can list stored cards and obtain a usable
  `tokenId` on the first attempt, with no undocumented steps.
- **SC-002**: 100% of token responses, log lines, and audit records contain no full card number
  and no security code, verified by inspection across all three operations.
- **SC-003**: All three operations are demonstrable end-to-end against UAT, and observed
  responses are recorded in `contracts/bml-remote.md`.
- **SC-004**: A token stored in sandbox is never visible in production and vice versa, confirmed
  by environment-isolation testing.
- **SC-005**: After deletion, 100% of subsequent charge attempts against that token are rejected.
- **SC-006**: The library exposes zero methods that create a token or return a full card number,
  verified by a test asserting the resource's public method list.
- **SC-007**: An empty token list and an authentication failure produce observably different
  outcomes in 100% of cases.
- **SC-008**: Every request path is traceable to a path in `reference/Connect-API.json`, verified
  by the conformance test.

## Assumptions

- A customer exists (feature `001`) before any token operation; `customerId` is required.
- Tokens are created only through feature `003`'s tokenizing transaction flow. This feature is
  read-and-delete only, by contract, not by choice.
- Card capture happens entirely on BML's hosted payment page. This library is never in scope for
  raw cardholder data.
- BML is the source of truth for token validity. The library reports fields as returned and makes
  no usability judgement of its own.
- Token list pagination is not described in the document; the library returns the collection as
  BML sends it until UAT observation says otherwise.

## Dependencies

- Feature `001-customers-endpoints` — every path is nested under a `customerId`.
- Feature `003-transactions-v2` — the only way a token comes into existence.
- Consumed by feature `004-token-charge`, which charges a `tokenId`.
- Access to BML UAT for independent testing.
- `reference/Connect-API.json` as the contract of record.
