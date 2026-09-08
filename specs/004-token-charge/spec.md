# Feature Specification: Token Charge

**Feature Branch**: `004-token-charge`

**Created**: 2026-09-07

**Status**: Draft — **BLOCKED on an unresolved identifier question, see Dependencies**

**Input**: New. The retired `bml_tokenization` specs had **no equivalent** — they modelled a
stored-card charge as a `card_reference` parameter on transaction create, a shape that does not
exist. See [MIGRATION.md](../../MIGRATION.md).

## Clarifications

### Session 2026-09-07

- Q: How does a merchant charge a stored card? → A: `POST /public-customers/charge` with
  `customerId`, `transactionId` and `tokenId`, all three required. **A transaction must already
  exist** — the charge is applied to it, not created by it.
- Q: So charging is a two-step flow? → A: Yes. Create a transaction (feature `003`), then charge
  it against a stored token. The retired spec's single-call "create with a card_reference and it
  charges server-side" does not exist and MUST NOT be simulated by the library.
- Q: Is the charge synchronous? → A: Yes. The `200` response is a full transaction object with a
  `state`, so the outcome is known on return — unlike the redirect flow, where the cardholder
  completes out of band.
- Q: Does `tokenId` mean `Token#id` or `Token#token`? → A: **Unresolved.** Both fields exist on a
  token. The path parameter for retrieve and delete is `tokenId`, which makes `Token#id` the
  strong inference, but the document never states it. This blocks the feature — see Dependencies.
- Q: Should the library offer a one-call convenience that creates a transaction and charges it?
  → A: **No.** Constitution V forbids presenting one call where the platform requires two,
  especially for a money-moving operation. A caller must see both steps.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Charge a stored card (Priority: P1)

A merchant needs to take a payment from a card the customer saved earlier — a subscription
renewal, an account top-up, an ad-hoc charge under a stored agreement — without the customer
being present to re-enter card details.

**Why this priority**: This is the entire commercial purpose of storing a card. Features `001`,
`002` and `003` exist to make this call possible.

**Independent Test**: With a customer holding a stored token, create a transaction and charge it
against that token; confirm the returned transaction reports a resolved state and no payment URL
is needed.

**Acceptance Scenarios**:

1. **Given** a customer with a stored token and a created transaction, **When** the merchant
   charges the token, **Then** a transaction record is returned with a resolved `state` and the
   payment is applied without any cardholder interaction.
2. **Given** a charge call missing `customerId`, `transactionId`, or `tokenId`, **When**
   submitted, **Then** the library rejects it locally naming the missing field and makes **no**
   remote call.
3. **Given** a token that has been deleted, **When** a charge is attempted against it, **Then**
   the charge is rejected and an error is raised describing why.
4. **Given** a token belonging to a different customer, **When** a charge pairs it with the wrong
   `customerId`, **Then** the charge is rejected.
5. **Given** a client configured for sandbox, **When** a charge is made, **Then** it applies only
   in UAT.

---

### User Story 2 - Understand a failed charge (Priority: P1)

A merchant running scheduled billing needs to distinguish a declined card from a network outage,
because one calls for dunning and the other for a retry.

**Why this priority**: A charge that fails ambiguously is worse than one that fails clearly —
retrying a decline annoys customers and can incur fees, while treating an outage as a decline
loses revenue. Equal in priority to the charge itself.

**Acceptance Scenarios**:

1. **Given** a card the issuer declines, **When** the merchant charges it, **Then** the outcome
   is distinguishable from a transport failure, and the returned transaction reports the declined
   state.
2. **Given** BML is unreachable, **When** a charge is attempted, **Then** an availability error
   is raised, **no** automatic retry is performed, and the caller is left able to reconcile.
3. **Given** a charge that times out after the request was sent, **When** the caller handles it,
   **Then** the library MUST NOT have retried, and the documented recovery is to retrieve the
   transaction by id to determine whether it was applied.

---

### Edge Cases

- Misconfigured client: MUST raise an authentication/configuration error.
- **Timeout mid-charge**: the single most dangerous case in this library. The library MUST NOT
  retry. It MUST raise an availability error whose message names the `transactionId` so the
  caller can reconcile by retrieving it.
- Charging a transaction that has already been charged: **[UNVERIFIED]** — BML may reject it or
  double-charge. Until observed, callers MUST NOT assume protection.
- Charging a transaction created for a different amount than intended: the charge carries no
  amount of its own, so the transaction's amount governs. The library MUST make this obvious.
- A caller passing a PAN in any field: rejected locally before any remote call.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose a charge operation for stored tokens via
  `POST /public-customers/charge`.
- **FR-002**: The library MUST require `customerId`, `transactionId` and `tokenId`, validating
  all three are present and non-blank before any remote call.
- **FR-003**: The library MUST NOT expose any operation that creates a transaction and charges it
  in a single call. The two steps MUST remain visible to the caller.
- **FR-004**: The library MUST NOT automatically retry a charge under any circumstance. No
  idempotency key is documented; a retry risks a second charge.
- **FR-005**: On a transport failure or timeout, the error raised MUST name the `transactionId`
  so the caller can reconcile.
- **FR-006**: The library MUST return the full transaction record BML sends, exposing its
  `state`.
- **FR-007**: The library MUST distinguish a declined charge (a returned transaction in a failed
  state) from a transport failure (a raised availability error).
- **FR-008**: The library MUST NOT accept, transmit, log, or persist a PAN, CVV, or any Sensitive
  Authentication Data.
- **FR-009**: The library MUST authenticate using the raw `Authorization` API key — no `Bearer`,
  no `X-App-Id`.
- **FR-010**: Every charge MUST emit an audit record capturing who, what, when and outcome,
  including the `transactionId` and `tokenId`, and MUST NOT contain card data.
- **FR-011**: Audit records MUST be emitted for **failed** charges as well as successful ones —
  a declined or errored charge is precisely what an audit trail needs to show.
- **FR-012**: The library MUST perform charges against the environment selected on the client.
- **FR-013**: The library MUST document, in the method's own documentation, which token
  identifier `tokenId` expects, once resolved.
- **FR-014**: Every operation MUST be independently testable against UAT.

### Key Entities *(include if feature involves data)*

- **Charge Request (input only)**: `customerId`, `transactionId`, `tokenId` — all required. It
  carries no amount; the transaction's amount governs.
- **Transaction** (from feature `003`): the `200` response is a full transaction record. This
  feature adds no new response entity.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A merchant holding a customer, a token and a transaction can charge the stored card
  on the first attempt using only documented required inputs.
- **SC-002**: 100% of charge requests, responses, logs and audit records contain no PAN and no
  CVV.
- **SC-003**: The charge operation is demonstrable end-to-end against UAT, and the observed
  response recorded in `contracts/bml-remote.md`.
- **SC-004**: **No charge request is ever automatically retried**, verified by a test that
  simulates a timeout and asserts exactly one HTTP attempt.
- **SC-005**: A declined charge and a transport failure produce observably different outcomes in
  100% of cases.
- **SC-006**: Every failed charge produces an audit record, verified for decline, validation
  failure, and availability failure.
- **SC-007**: The library exposes no method that creates and charges in one call, verified by a
  test asserting the resource's public method list.
- **SC-008**: The meaning of `tokenId` is confirmed against UAT and documented before release.

## Assumptions

- A customer (feature `001`), a stored token (feature `002`) and a transaction (feature `003`)
  all exist before a charge.
- The transaction supplies the amount; the charge does not.
- BML applies the charge synchronously and returns the resulting transaction state.
- Merchant-initiated charges rely on the agreement established when the card was tokenized —
  `tokenAgreementId` on the token, from `tokenizationDetails` at create time. Charging outside
  the terms of that agreement is a scheme-rules matter between the merchant and BML, not
  something this library can validate.

## Dependencies

- Feature `001-customers-endpoints` — `customerId`.
- Feature `002-stored-card-tokens` — `tokenId`.
- Feature `003-transactions-v2` — `transactionId`, and the transaction record returned.
- Access to BML UAT, plus a customer with a genuinely stored card (which requires completing a
  hosted payment as a cardholder).

### ⛔ Blocking dependency

**This feature MUST NOT ship until it is confirmed whether `tokenId` is `Token#id` or
`Token#token`.** Both fields exist on every token. The document does not say which the charge
body expects, and the inference from path-parameter naming is not proof. Charging the wrong
identifier is a money-movement defect. Resolution is scheduled as feature `002` tasks T011/T016
and gated here as T001.
