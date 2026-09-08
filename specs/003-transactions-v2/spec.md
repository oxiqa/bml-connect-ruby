# Feature Specification: Transactions V2

**Feature Branch**: `003-transactions-v2`

**Created**: 2026-09-07

**Status**: Draft

**Input**: Realigned from `bml_tokenization/specs/003-transaction-endpoints` against
`reference/Connect-API.json`. Unlike features `001`, `002` and `004`, this feature modifies an
**existing, released, in-production** resource. See [MIGRATION.md](../../MIGRATION.md).

## Clarifications

### Session 2026-09-07

- Q: Does the existing `POST public/transactions` create endpoint still work? → A: Yes — UAT
  answers it with an application-level `PP-C-004` auth error rather than a gateway 403, so the
  route exists. But it is **not in `Connect-API.json`**; only `/public/v2/transactions` is
  documented for creation. It is treated as a live-but-undocumented legacy path, kept working and
  marked deprecated, not removed.
- Q: Is the SHA1 `signature` the gem sends still required? → A: Unknown. The string `signature`
  appears **zero** times in the published document. The library keeps sending it on the legacy v1
  path (where it demonstrably works today) and does **not** send it on v2 until UAT observation
  settles whether v2 accepts or rejects it.
- Q: How does a caller ask for a card to be stored? → A: `tokenizationDetails` on the v2 create
  body: `{tokenize, paymentType, recurringFrequency, expiryDate}`, where `tokenize` and
  `paymentType` are required whenever the object is present.
- Q: What are `amount` units? → A: The existing website integration sends a string with the
  decimal point stripped — `"%.02f" % 100.0` → `"10000"` for MVR 100.00 — so minor units. The v2
  schema types `amount` as `number`. The library MUST accept an Integer in minor units and MUST
  NOT silently reinterpret the caller's value.
- Q: Which create variant does the current website flow use? → A: Variant 3 —
  `{amount, currency, redirectUrl, localId, customerReference}` — plus the optional `customerId`
  and `tokenizationDetails`. The existing payload is already a valid v2 variant-3 body.
- Q: Does `transactions.create` change its return type? → A: **No.** It returns a
  `Faraday::Response` today and six production call sites depend on that. Backward compatibility
  wins; the new value-object surface is exposed under new method names.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a transaction on the documented v2 endpoint (Priority: P1)

An integrator wants to take a payment using the endpoint BML actually publishes, rather than the
undocumented v1 path the gem has always used, so that their integration rests on a contract BML
supports.

**Why this priority**: Every other capability in this feature and in feature `004` builds on v2
create. It is also the migration's core purpose — moving the gem onto the published contract.

**Independent Test**: Create a transaction against UAT via `/public/v2/transactions` with amount,
currency and a redirect URL, and confirm a payment URL is returned.

**Acceptance Scenarios**:

1. **Given** a configured client, **When** the integrator creates a transaction with `amount`,
   `currency`, `redirectUrl`, `localId` and `customerReference`, **Then** a transaction is
   returned carrying an `id`, a `state`, and a hosted payment URL for the cardholder.
2. **Given** a create call missing `amount` or `currency`, **When** submitted, **Then** the
   library rejects it locally naming the field and makes **no** remote call.
3. **Given** a client configured for sandbox, **When** a transaction is created, **Then** it
   exists only in UAT.
4. **Given** an existing caller using the current `transactions.create`, **When** this feature
   ships, **Then** their code continues to work unchanged, against the same v1 endpoint, with the
   same return type.

---

### User Story 2 - Store a card while taking a payment (Priority: P1)

An integrator wants a customer's card saved during checkout so later payments — a subscription
renewal, an account top-up — can be taken without the customer re-entering card details.

**Why this priority**: This is the capability the whole migration exists to enable. It is the
only way a token can come into existence (feature `002` can only read and delete them).

**Independent Test**: Create a transaction with `customerId` and
`tokenizationDetails.tokenize = true`, complete it on the hosted page, then confirm a new token
appears under that customer via feature `002`.

**Acceptance Scenarios**:

1. **Given** an existing `customerId`, **When** the integrator creates a transaction with
   `tokenizationDetails` marking `tokenize` true and a `paymentType`, **Then** the transaction is
   created and, once the cardholder completes it, a token is stored against that customer.
2. **Given** `tokenizationDetails` with `paymentType` `RECURRING`, **When** `recurringFrequency`
   or `expiryDate` is missing, **Then** the library rejects the call locally, naming the missing
   field, and makes no remote call.
3. **Given** `tokenizationDetails` present without `tokenize` or without `paymentType`, **When**
   submitted, **Then** the library rejects it locally naming the missing field.
4. **Given** a transaction created with tokenization but not completed by the cardholder,
   **Then** no token is stored, and the library reports the transaction's state rather than
   asserting success.

---

### User Story 3 - Check a transaction's outcome (Priority: P1)

An integrator whose customer has returned from the hosted payment page needs to know whether the
payment succeeded before releasing goods or crediting an account.

**Why this priority**: Without it a payment cannot be settled against the integrator's own
records. Already in use in production at four call sites.

**Acceptance Scenarios**:

1. **Given** a transaction id, **When** the integrator retrieves it, **Then** the current record
   is returned with its `state` and, where present, `merchantId`, `paddedCardNumber` and
   `provider`.
2. **Given** an id matching no transaction, **When** retrieved, **Then** a not-found error is
   raised.
3. **Given** an existing caller using `transactions.get`, **When** this feature ships, **Then**
   their code works unchanged.

---

### User Story 4 - Amend a pending transaction (Priority: P3)

An integrator needs to correct a reference on a transaction after creating it.

**Acceptance Scenarios**:

1. **Given** an existing transaction, **When** the integrator updates `customerReference`,
   `localData` or `pnr`, **Then** the change is applied and other fields are unaffected.

---

### User Story 5 - Capture or cancel (Priority: P3)

An integrator running pre-authorization needs to capture a held amount, or cancel a transaction
that will not proceed.

**Acceptance Scenarios**:

1. **Given** a pre-authorized transaction, **When** the integrator captures it with an `id` and
   `amount`, **Then** the capture is applied.
2. **Given** a transaction not in a cancellable state, **When** cancellation is attempted,
   **Then** an error is raised describing why.

---

### Edge Cases

- Misconfigured client: MUST raise an authentication/configuration error.
- Remote outage or timeout during **create**: this is a money-moving call. The library MUST
  surface a distinguishable availability error and MUST NOT silently retry a create that may
  already have been accepted — see FR-016.
- A caller passing a raw PAN or CVV in any field: rejected locally before any remote call.
- A caller passing a float amount such as `100.0` intending MVR 100.00: the library MUST NOT
  guess. It requires an Integer in minor units and rejects a Float, naming the field.
- `tokenizationDetails` supplied without a `customerId`: **[UNVERIFIED]** whether BML can store a
  token with no customer to attach it to. The library warns and forwards rather than blocking,
  pending observation.
- A transaction created against the legacy v1 path then retrieved: retrieval is on the shared
  `/public/transactions/{id}` path and works for both.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose creation on the documented `POST /public/v2/transactions`
  endpoint.
- **FR-002**: The library MUST support the v2 create variant used by existing integrations —
  `amount` and `currency` required, with optional `redirectUrl`, `webhook`, `localId`,
  `customerReference`, `customerId`, `tokenizationDetails` and `expires`.
- **FR-003**: The library MUST accept `tokenizationDetails` and MUST validate locally that
  `tokenize` and `paymentType` are present whenever it is supplied, and that
  `recurringFrequency` and `expiryDate` are present when `paymentType` is `RECURRING`.
- **FR-004**: The library MUST validate `expiryDate` is a future date in `yyyy-mm-dd` form when
  supplied.
- **FR-005**: The library MUST require `amount` to be a positive Integer in minor units and MUST
  reject a Float, a String, zero, or a negative value, naming the field, with no remote call.
- **FR-006**: The library MUST allow retrieving a transaction via
  `GET /public/transactions/{transactionId}`.
- **FR-007**: The library MUST allow amending a transaction via
  `PATCH /public/transactions/{transactionId}` with any of `customerReference`, `localData`,
  `pnr`, sending only supplied keys.
- **FR-008**: The library MUST allow capture via
  `POST /public/transactions/{transactionId}/capture` with `id` and `amount`.
- **FR-009**: The library MUST allow cancellation via
  `POST /public/transactions/{transactionId}/cancel`.
- **FR-010**: The library MUST NOT remove, rename, or change the return type or signature of the
  existing `transactions.create`, `transactions.get`, or `transactions.list`. Six production call
  sites in `msgowl/website` depend on them.
- **FR-011**: The existing v1 create MUST be marked deprecated in documentation, with a pointer
  to the v2 method, while continuing to work.
- **FR-012**: The library MUST NOT send a `signature` field on v2 requests until UAT observation
  establishes whether v2 requires, ignores, or rejects one. It MUST continue sending it on v1.
- **FR-013**: The library MUST authenticate using the raw `Authorization` API key — no `Bearer`,
  no `X-App-Id`.
- **FR-014**: The library MUST NOT accept, transmit, log, or persist a PAN, CVV, or any Sensitive
  Authentication Data. Card entry happens on BML's hosted page.
- **FR-015**: The library MUST NOT log or place in an audit record the hosted payment URL, which
  is a completion secret.
- **FR-016**: Automatic retry MUST NOT be applied to transaction creation. Retry is safe only
  with a server-side idempotency guarantee, and none is documented for this endpoint. Retrieve,
  list, and cancel MAY retry.
- **FR-017**: Create, capture, and cancel MUST emit audit records. Retrieve and list are not
  audited.
- **FR-018**: Every operation MUST be independently testable against UAT.

### Key Entities *(include if feature involves data)*

- **Transaction**: A payment. Platform-assigned: `id`, `created`, `updated`, `state`,
  `merchantId`, `provider`, `accountingState`, `paymentToken`, `history`, `qr`. Caller-supplied:
  `amount`, `currency`, `redirectUrl`, `webhook`, `localId`, `customerReference`, `customerId`,
  `expires`. Response also carries `paddedCardNumber` and `costStructure`.
- **Tokenization Details (input only)**: `tokenize` (boolean, required), `paymentType`
  (`RECURRING` or `UNSCHEDULED`, required), `recurringFrequency` (required when `RECURRING`),
  `expiryDate` (required when `RECURRING`). Instructs BML to store the card.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An integrator can create a v2 transaction and receive a hosted payment URL on the
  first attempt using only documented required inputs.
- **SC-002**: A transaction created with `tokenizationDetails.tokenize = true` and completed by a
  cardholder results in a token visible via feature `002`, demonstrated end-to-end on UAT.
- **SC-003**: 100% of requests, responses, logs, and audit records contain no PAN and no CVV, and
  no log or audit record contains a hosted payment URL.
- **SC-004**: All six operations are demonstrable against UAT and recorded in
  `contracts/bml-remote.md`.
- **SC-005**: `msgowl/website` continues to pass against this gem with **zero** code changes,
  verified before release.
- **SC-006**: Every invalid-input scenario raises an error naming the specific problem, verified
  for 100% of required fields including every `tokenizationDetails` conditional rule.
- **SC-007**: No create request is ever automatically retried, verified by a test that simulates
  a timeout and asserts exactly one HTTP attempt.
- **SC-008**: Every request path is traceable to `reference/Connect-API.json`, except the legacy
  v1 create, which is explicitly recorded as undocumented-but-live.

## Assumptions

- The legacy `POST public/transactions` remains live. If BML retires it, callers must move to the
  v2 method; this is the reason for deprecating rather than silently proxying.
- BML is the source of truth for transaction state values. The library passes `state` through
  unchanged rather than normalizing it — production code already branches on `CONFIRMED`,
  `CANCELLED` and `FAILED`.
- The hosted payment page is where card capture happens; this library is never in scope for raw
  cardholder data.
- Tokenization requires a customer to attach the token to, though the schema does not enforce it.

## Dependencies

- Feature `001-customers-endpoints` — `customerId` is needed for tokenizing transactions.
- Produces the tokens that feature `002-stored-card-tokens` reads and feature
  `004-token-charge` charges.
- `reference/Connect-API.json` as the contract of record, with the v1 create as a recorded
  exception.
- Access to BML UAT, plus the ability to complete a hosted payment as a cardholder in order to
  verify SC-002.
