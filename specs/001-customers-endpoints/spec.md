# Feature Specification: Customers Endpoints

**Feature Branch**: `001-customers-endpoints`

**Created**: 2026-09-07

**Status**: Draft

**Input**: Realigned from `bml_tokenization/specs/001-customer-api-endpoints` against BML's
published contract, `reference/Connect-API.json` (OpenAPI 3.1, Connect API v2.0). See
[MIGRATION.md](../../MIGRATION.md).

## Clarifications

### Session 2026-09-08

- Q: Should the library validate email *format*, or only presence/non-empty? → A: Presence plus a
  lightweight shape check. `email` (and `billingEmail` when supplied) MUST contain an `@` and a
  domain part; an obviously malformed value is rejected locally with a field-named error before
  any remote call. The library does **not** perform strict RFC validation — BML remains the
  authority on acceptance beyond this basic shape.
- Q: Which submitted fields are scanned for a PAN/CVV pattern before sending? → A: Every
  caller-supplied string value — `name`, `email`, all billing fields, `taxId`, the `actor`
  reference, and any other string the caller provides. If any value matches a PAN or CVV pattern
  the call is rejected locally before any remote request. This is the most protective default and
  leaves no unscanned field.
- Q: How is the audit record for create/update/archive emitted to the integrator? → A: As a
  structured, masked log line through the library's existing logger — the same logging path
  FR-015 already mandates. No new audit-sink configuration is introduced; auditing is observable
  in tests by inspecting the emitted log line.

### Session 2026-09-07

- Q: The retired spec required `first_name` / `last_name` / `email`. What does BML actually
  require? → A: A single `name` plus `email` — both `minLength: 1` and both in the schema's
  `required` array for `POST /public-customers`. The library MUST mirror BML's shape exactly and
  MUST NOT synthesize a `name` by joining first/last, because that would silently reformat data
  the merchant dashboard displays.
- Q: Is customer deletion a hard delete? → A: No. `DELETE /public-customers/{customerId}`
  returns `204` and the customer record carries a `deleted: boolean` flag, so it is an archive.
  The library MUST name the operation to reflect that (BML's own summary is "Archive Customer").
- Q: Is update a full replace or a partial merge? → A: Partial merge. The method is `PATCH` and
  the request schema marks **no** field required. The retired spec's full-replace semantics were
  an artifact of assuming `PUT`.
- Q: What identifies the "who" in audit records? → A: The configured App ID by default, plus an
  optional integrator-supplied actor reference per call. Carried over unchanged from the retired
  spec.
- Q: Does the list endpoint paginate? → A: The `200` response is an envelope of `items` plus a
  `count`, matching the pagination shape the existing `Transactions#list` already handles. Page
  parameters are `[UNVERIFIED]` — not described in the document — and MUST be confirmed against
  UAT before the library exposes them.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a customer (Priority: P1)

An integrator wants to register a payer as a BML customer record so that cards can later be
stored against them and charged without re-entering details. Working through the existing
configured `BMLConnect::Client`, they supply the customer's name and email and receive back a
record carrying the BML-assigned `id`.

**Why this priority**: The customer record is the anchor for every stored-card operation. A
token in BML Connect belongs to a customer; without a customer id there is nothing to attach a
card to and no way to charge one later. This is the minimum viable slice.

**Independent Test**: Create a customer against UAT with only `name` and `email`, and confirm a
record with a non-empty `id` and `companyId` is returned. Delivers value because the returned id
is immediately usable by feature `002`.

**Acceptance Scenarios**:

1. **Given** a configured client, **When** the integrator creates a customer with `name` and
   `email`, **Then** a customer record is returned containing a BML-assigned `id`, the submitted
   `name` and `email`, and the platform-set `companyId`, `currency`, and `created` timestamp.
2. **Given** a create call missing `name` or missing `email`, **When** the integrator submits it,
   **Then** the library rejects it locally, naming the missing field, and makes **no** remote call.
3. **Given** optional billing fields (`billingEmail`, `billingAddress1`, `billingCity`,
   `billingCountry`, `billingPostCode`, `taxId`), **When** supplied, **Then** they are sent
   through unchanged and reflected on the returned record.
4. **Given** a client configured for sandbox, **When** a customer is created, **Then** it exists
   only in UAT and is not visible in production.

---

### User Story 2 - Retrieve a customer (Priority: P1)

An integrator holds a customer id and needs the current record — to display it, to confirm it
still exists, or to read its billing details before charging.

**Why this priority**: Retrieval is required to confirm an id is still valid before any
stored-card operation, and is independently useful as a lookup.

**Independent Test**: Create a customer, retrieve it by id, and confirm the returned record
matches.

**Acceptance Scenarios**:

1. **Given** an existing customer id, **When** the integrator retrieves it, **Then** the current
   record is returned.
2. **Given** an id that matches no customer, **When** the integrator retrieves it, **Then** a
   not-found error is raised, distinguishable from an authentication or availability failure.
3. **Given** an archived customer, **When** it is retrieved, **Then** the record is returned with
   `deleted` set true rather than raising not-found.

---

### User Story 3 - List customers (Priority: P2)

An integrator needs to enumerate the customers registered under their company, to reconcile
against their own records or to build a picker in an admin UI.

**Why this priority**: Useful for reconciliation and administration but not on the critical path
to storing or charging a card, so it ranks below create and retrieve.

**Independent Test**: List customers and confirm an envelope containing an `items` array and a
`count` is returned, with each element exposing `id`, `name`, and `email`.

**Acceptance Scenarios**:

1. **Given** a configured client, **When** the integrator lists customers, **Then** an envelope
   with `count` and an `items` array is returned.
2. **Given** a company with no customers, **When** the integrator lists them, **Then** an empty
   `items` array is returned — not an error.

---

### User Story 4 - Update a customer (Priority: P2)

An integrator needs to correct a customer's email or billing details after creation.

**Why this priority**: Necessary for data hygiene over the life of a customer record, but not
required to complete a first payment.

**Independent Test**: Create a customer, update a single field, retrieve it, and confirm only
that field changed.

**Acceptance Scenarios**:

1. **Given** an existing customer, **When** the integrator updates only `billingCity`, **Then**
   that field changes and every other field retains its prior value.
2. **Given** an update for an id that matches no customer, **When** submitted, **Then** a
   not-found error is raised.

---

### User Story 5 - Archive a customer (Priority: P3)

An integrator needs to retire a customer record that is no longer active.

**Why this priority**: A lifecycle-completeness and data-minimisation capability, needed least
often.

**Acceptance Scenarios**:

1. **Given** an existing customer, **When** the integrator archives it, **Then** the operation
   succeeds with no response body and the record is subsequently reported as `deleted`.
2. **Given** an id that matches no customer, **When** archiving is attempted, **Then** an error
   is raised and no other customer is affected.

---

### Edge Cases

- Misconfigured client (missing or invalid API key): the operation MUST raise an
  authentication/configuration error rather than returning an empty result.
- Remote outage or timeout: the operation MUST raise a distinguishable availability error and
  MUST NOT return a partial record.
- A caller passing card data (a PAN or CVV) in any customer field: the library MUST reject the
  call locally before any remote request, scanning every caller-supplied string value (see
  FR-014). Customer records are not a place for card data.
- Archiving a customer that still has stored tokens: BML's behavior here is **[UNVERIFIED]**.
  The library MUST NOT assume a cascade in either direction until confirmed against UAT.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The library MUST expose customers as a resource reachable through the existing
  configured `BMLConnect::Client`, consistent with how `transactions` is already exposed
  (`client.customers`).
- **FR-002**: The library MUST allow creating a customer via `POST /public-customers`, requiring
  `name` and `email` and accepting the documented optional fields, and MUST return the created
  record including its BML-assigned `id`.
- **FR-003**: The library MUST NOT rename, split, join, or otherwise reshape BML's field names.
  `name` is a single field; the library MUST NOT expose `first_name`/`last_name`.
- **FR-004**: The library MUST allow retrieving a single customer via
  `GET /public-customers/{customerId}`.
- **FR-005**: The library MUST allow listing customers via `GET /public-customers`, returning the
  `{count, items}` envelope BML sends.
- **FR-006**: The library MUST allow partially updating a customer via
  `PATCH /public-customers/{customerId}`, sending only the fields the caller supplied. It MUST
  NOT send unspecified fields as null, which would erase data.
- **FR-007**: The library MUST allow archiving a customer via
  `DELETE /public-customers/{customerId}`, treating `204` as success with no body.
- **FR-008**: The library MUST validate that required inputs are present and non-empty before
  contacting BML, raising an error naming the offending field without making a remote call. For
  `email` (and `billingEmail` when supplied) the library MUST additionally apply a lightweight
  shape check — the value MUST contain an `@` and a domain part — and reject an obviously
  malformed address locally. It MUST NOT perform strict RFC email validation; BML remains the
  authority on acceptance beyond this basic shape.
- **FR-009**: The library MUST perform every operation against the environment selected on the
  client and MUST NOT cross environments.
- **FR-010**: The library MUST authenticate using the client's configured API key, sent as a raw
  `Authorization` header value per `Connect-API.json` `securitySchemes`. It MUST NOT prefix the
  key with `Bearer` and MUST NOT send an `X-App-Id` header.
- **FR-011**: The library MUST surface remote failures as distinguishable errors — validation,
  not-found, authentication, conflict, rate-limit, and availability — rather than raw HTTP codes.
- **FR-012**: Every create, update, and archive operation MUST emit an audit record capturing
  who, what, when, and outcome. The record MUST be emitted as a structured, masked log line
  through the library's existing logger (the same path as FR-015); no separate audit-sink
  configuration is introduced. Reads (retrieve, list) are not audited.
- **FR-013**: The audit "who" MUST default to the configured App ID, and each operation MUST
  accept an optional actor reference. The actor MUST NOT contain cardholder data; the library
  MUST reject an actor that matches a PAN pattern.
- **FR-014**: The library MUST NOT accept, transmit, log, or persist a PAN, CVV, or any Sensitive
  Authentication Data through the customers resource. It MUST scan **every** caller-supplied
  string value — `name`, `email`, all billing fields, `taxId`, the `actor` reference, and any
  other string provided — for a PAN or CVV pattern, and reject the call locally (naming the
  offending field) before any remote request. No caller-supplied string field is exempt.
- **FR-015**: Structured log lines MUST be masked and MUST NOT contain the API key or any
  cardholder data.
- **FR-016**: Every operation MUST be independently testable against UAT without production
  credentials.

### Key Entities *(include if feature involves data)*

- **Customer**: A payer registered under the merchant's company. Platform-assigned attributes:
  `id`, `companyId`, `currency`, `created`, `updated`, `deleted`, `customerGroupId`.
  Caller-supplied: `name` (required), `email` (required), `billingEmail`, `billingAddress1`,
  `billingAddress2`, `billingCity`, `billingCountry`, `billingPostCode`, `customerGroup`,
  `invoicePrefix`, `taxInformation`, `taxId`. Holds **no** card data; stored cards hang off the
  customer as tokens (feature `002`).
- **Customer List Envelope**: BML's list response — a `count` and an `items` array of customers.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An integrator can create a customer and receive a usable `id` on the first attempt
  using only `name` and `email`, with no undocumented steps.
- **SC-002**: 100% of customer requests and responses contain no PAN and no CVV, verified by
  inspection across all five operations.
- **SC-003**: All five operations are demonstrable end-to-end against UAT with real credentials,
  and the observed responses are recorded in `contracts/bml-remote.md`.
- **SC-004**: A customer created in sandbox is never visible in production and vice versa,
  confirmed by environment-isolation testing.
- **SC-005**: A partial update changes only the supplied fields in 100% of cases, verified by
  retrieving the record before and after.
- **SC-006**: Every invalid-input scenario raises an error naming the specific problem, verified
  for 100% of required fields.
- **SC-007**: Every request path and header the resource sends is traceable to a path in
  `reference/Connect-API.json`, verified by a contract test that reads the document itself.

## Assumptions

- `bml-connect-ruby` is a server-side client library wrapping the BML Connect API. Credentials
  live on the server; this gem is never embedded in a browser or mobile client.
- The customers resource reuses the existing `BMLConnect::Client` for base URL, mode
  (`production` / `sandbox`), and the API key. No new configuration mechanism is introduced.
- BML is the source of truth for field semantics; the library mirrors the contract and does not
  impose its own validation beyond presence of the documented required fields and a lightweight
  `@`-and-domain shape check on email values (see FR-008).
- List pagination parameters are not described in `Connect-API.json`. The library ships list
  without page parameters until UAT observation confirms their names.

## Dependencies

- A configured client with a valid API key, as already established for `transactions`.
- Access to the BML UAT environment for independent testing of each operation.
- `reference/Connect-API.json` as the contract of record.
- Consumed by feature `002-stored-card-tokens` (tokens are addressed by `customerId`) and
  feature `004-token-charge`.
