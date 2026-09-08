# Phase 0 Research: Stored Card Tokens

**Feature**: `002-stored-card-tokens` | **Date**: 2026-09-07

## R1. Merging two retired features into one

- **Decision**: `002-card-on-file-endpoints` and `004-tokenization-endpoints` collapse into this
  single feature.
- **Rationale**: They described one object. The retired model had `POST /tokens` issue a token,
  then a separate card-on-file record *associate* that token with a customer — two resources,
  two lifecycles, two specs. BML has one: a token nested under a customer at
  `/public-customers/{customerId}/tokens`. Maintaining two specs for one resource guarantees they
  drift.
- **Alternatives considered**: Keep both directories and cross-reference (rejected — duplicated
  requirements with no second entity to justify them).

## R2. No create endpoint — designing around an absence

- **Decision**: This resource exposes no create/tokenize/store method, and a unit test asserts
  its public method list is exactly `list`, `retrieve`, `delete`.
- **Rationale**: `Connect-API.json` has no token-issuing operation. Tokens arise from
  `POST /public/v2/transactions` with `tokenizationDetails.tokenize = true`, completed by the
  cardholder on BML's hosted page. Integrators *will* look for `client.tokens.create` and its
  absence needs to be deliberate and documented rather than an apparent oversight — hence the
  explicit table in `contracts/library-api.md` and the enforcing test.
- **Why a test and not just a comment**: the retired gem's `POST /tokens` looked entirely
  plausible and survived review. A test that fails when someone adds a fourth public method is
  the cheapest guard against the same mistake recurring (Constitution V).
- **Alternatives considered**: A `create` that raises `NotImplementedError` with a pointer to
  feature `003` (rejected — a method that exists but always raises is worse documentation than a
  method that does not exist); a convenience that creates a tokenizing transaction under the hood
  (rejected outright — Constitution V forbids presenting one call where the platform requires a
  different flow, and it would hide a money-moving operation behind a method named `create`).

## R3. `id` vs `token` — which is the charge handle?

- **Decision**: Treat `Token#id` as the charge handle; expose `token` as an opaque value.
- **Rationale**: The charge body takes `tokenId`, and the retrieve/delete path parameter is
  `tokenId`. Consistent naming makes `id` the strong inference.
- **Risk, stated plainly**: this is an **inference, not documentation**. The document never says
  `tokenId` is `Token#id`. Charging the wrong identifier is a money-movement bug, so this is
  flagged as the highest-priority `[UNVERIFIED]` item across the whole migration and blocks
  feature `004` from shipping.
- **Alternatives considered**: Accept either and try both (rejected — retrying a failed charge
  with a different identifier risks a double charge); expose only `token` (rejected — contradicts
  the path parameter naming).

## R4. Unknown list response envelope

- **Decision**: Parse defensively — accept either a bare JSON array or a `{count, items}`
  envelope.
- **Rationale**: In the document, the list operation's token-array schema is attached to its
  **`requestBody`**, not to a response. A `GET` with a request body describing tokens is almost
  certainly an authoring error in BML's export, which leaves the genuine response shape unstated.
  `/public-customers` uses a `{count, items}` envelope, so either is plausible. Handling both is
  a few lines and removes a guess.
- **Alternatives considered**: Assume a bare array (rejected — a 50/50 guess on a shape we can
  cheaply tolerate); block the feature until UAT confirms (rejected — the rest is implementable
  now, and the defensive parse is correct either way).

## R5. Cross-customer scoping is a security test, not a nice-to-have

- **Decision**: A mandatory UAT test attempts to retrieve a valid `tokenId` under a *different*
  customer's id and asserts it is not returned.
- **Rationale**: Every token path is nested under `customerId`, which implies scoping — but
  implies is not guarantees. If BML resolves `tokenId` globally and ignores the customer segment,
  an integrator iterating ids could enumerate other customers' stored cards. That is a
  cardholder-data exposure, so it is verified rather than assumed (Constitution I).
- **Alternatives considered**: Trust the path nesting (rejected — the whole migration exists
  because a plausible assumption went unchecked).

## R6. Empty list must not mask an auth failure

- **Decision**: Never rescue an authentication error into an empty collection.
- **Rationale**: "This customer has no saved cards" and "our API key is broken" would otherwise
  be indistinguishable to a caller, and the first is a perfectly normal state. An integrator
  would silently show a working checkout with no saved cards instead of alerting. Explicit over
  implicit (Constitution V).

## R7. Mirroring BML's field names

- **Decision**: Expose `paddedCardNumber`, `tokenExpiryMonth`, `tokenExpiryYear`, `brand`
  verbatim. No `last_four`, `scheme`, or `masked_number` aliases.
- **Rationale**: Renaming forces every reader to hold a translation table, and a derived
  `last_four` would require parsing a masked string whose format is unobserved. The retired gem's
  invented `first_name`/`last_name` split is the cautionary case (FR-007, Constitution III).
- **Alternatives considered**: snake_case aliases for Ruby idiom (rejected for now — a mapping
  layer is worth adding only if integrators ask, and it would be additive later).

## R8. No pagination

- **Decision**: Send no query parameters on list.
- **Rationale**: None are documented. Same reasoning as feature `001` R4.
