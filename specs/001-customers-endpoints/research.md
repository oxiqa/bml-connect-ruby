# Phase 0 Research: Customers Endpoints

**Feature**: `001-customers-endpoints` | **Date**: 2026-09-07

The specification has no `[NEEDS CLARIFICATION]` markers; five behavioral questions were fixed
in the 2026-09-07 clarification session, all resolved by reading `reference/Connect-API.json`
rather than by assumption. What remains are implementation-context choices, resolved below.

## R1. Transport — Faraday, not `net/http`

- **Decision**: Keep the gem's existing Faraday stack. Do not port the retired gem's stdlib
  `net/http` transport.
- **Rationale**: `BMLConnect::Client` already exposes `#http_client` and `#set_http_client`,
  which consumers may use to inject a test double; replacing the stack is a breaking change to a
  published gem for no functional gain. Faraday is already a declared dependency, so keeping it
  adds nothing (Constitution V).
- **Alternatives considered**: `net/http` to match the retired gem (rejected — breaking, no
  benefit); adding a second transport behind an adapter (rejected — indirection with no need).

## R2. Response envelope handling and the raw-response break

- **Decision**: The new resources return **value objects** and **raise** on non-2xx, rather than
  returning a `Faraday::Response` the way `Transactions` does today.
- **Rationale**: The existing `transactions` methods return the raw response and callers check
  `resp.status` — see the six call sites in `msgowl/website`. That is a poor surface (it pushes
  HTTP semantics onto every caller) but it is the published behavior of a released gem. Rather
  than change it, new resources adopt the better surface and `transactions` is left untouched.
- **Consequence, recorded deliberately**: the gem will have two response conventions until a
  future major version reconciles them. This is a real wart. It is accepted because silently
  changing `transactions`' return type would break `msgowl/website` at six call sites.
- **Alternatives considered**: Match `transactions` and return raw responses (rejected — spreads
  a bad surface and makes error mapping impossible); change `transactions` too (rejected — a
  breaking change out of scope for this feature; queued for `v1.0.0`).

## R3. Partial update serialization

- **Decision**: Build the `PATCH` body from **only the keys the caller supplied**. Never
  serialize an unset attribute as `null`.
- **Rationale**: The `PATCH` request schema marks no field required, so BML treats the body as a
  merge. Sending `{"billingCity": "X", "taxId": null}` for a caller who only set `billingCity`
  would plausibly erase `taxId`. Since the library cannot distinguish "set to null" from "not
  supplied" in a plain hash, it sends only what it was given and rejects an empty `changes` hash
  outright rather than issuing a no-op request.
- **Alternatives considered**: Read-modify-write full replace (rejected — two round trips, and a
  lost-update race); a sentinel value for explicit null (rejected — YAGNI until a caller needs
  it).

## R4. Pagination — deliberately not implemented

- **Decision**: `list` takes no page parameters in this feature.
- **Rationale**: `Connect-API.json` documents **no** query parameters for `GET
  /public-customers`. `Transactions#list` passes `page`, but that is v1 behavior on a different
  path and proves nothing about this one. Under Constitution III, shipping a parameter whose name
  we guessed is exactly the failure mode that produced the retired gem.
- **Follow-up**: Confirm against UAT with a company holding more than one page of customers, then
  add parameters in a follow-up change with the contract table updated.
- **Alternatives considered**: Assume `page` by symmetry with transactions (rejected — assumption
  by analogy is what this migration exists to correct).

## R5. `count` is typed `string`

- **Decision**: Coerce to Integer; fall back to `items.size` if coercion fails.
- **Rationale**: The document types the list envelope's `count` as `string`. Whether BML sends
  `"42"` or `42` in practice is unobserved. A tolerant coercion behaves correctly either way and
  cannot raise on a surprising value.
- **Alternatives considered**: Expose the raw string (rejected — pushes the oddity onto callers);
  assume integer and call `.to_i` blindly (rejected — silently yields 0 for a non-numeric).

## R6. Soft delete naming

- **Decision**: Name the operation `archive`, not `delete` or `destroy`.
- **Rationale**: BML's own summary is "Archive Customer" and the entity carries `deleted:
  boolean`, so the record persists. Naming it `delete` would imply an erase the platform does not
  perform — an implicit behavior the constitution forbids (Principle V, explicit over implicit).
- **Alternatives considered**: `delete` for Ruby-idiom familiarity (rejected — accuracy beats
  familiarity for a destructive-sounding operation).

## R7. PAN screening on input

- **Decision**: Screen every string value in create/update payloads, and the optional `actor`,
  against a PAN pattern; raise `ValidationError` locally on a match.
- **Rationale**: Customer records have no legitimate card field. A caller pasting a card number
  into `taxId` or a note would otherwise transmit and persist a PAN into a system not scoped for
  it. Screening locally keeps it out of the request, the logs, and the audit trail
  (Constitution I). Ported directly from the retired gem's `Masking::PAN_PATTERN`, which was
  sound.
- **Alternatives considered**: Screen only known-risky fields (rejected — the risk is precisely
  in the field nobody anticipated); screen on output only (rejected — too late; the PAN has
  already crossed the wire).

## R8. Error mapping without an error schema

- **Decision**: Map by HTTP status code, per the table in `contracts/bml-remote.md`.
- **Rationale**: The document declares response codes per operation but no error body schema.
  Status-code mapping is the only contract-supported approach. Error message extraction attempts
  `message` then `error` from the body, falling back to a generic string.
- **Caveat worth encoding in a test**: on UAT, an unmatched route returns `403
  {"message":"Forbidden"}` — byte-identical to a garbage path. A `403` therefore cannot be read
  as proof that a route exists. The conformance test (R9) is what guards this, not the error
  mapper.

## R9. Spec-conformance testing

- **Decision**: Add `spec/contract/openapi_conformance_spec.rb`, which parses
  `reference/Connect-API.json` and asserts that every path template the resource can emit is a
  key in `paths`, and that the auth header the client sends matches `securitySchemes`.
- **Rationale**: This is the concrete mechanism behind Constitution II's new gate. The retired
  gem had 259 green examples certifying four endpoints that did not exist, because every stub
  was hand-written to match the code. A test that reads BML's document instead of the code
  cannot be satisfied by an invented path.
- **Alternatives considered**: Rely on the UAT suite (rejected — it is credential-gated and
  skips by default, so it cannot be the primary guard); manual review (rejected — the retired
  gem passed manual review).

## R10. Stub URL construction

- **Decision**: Every WebMock stub interpolates `client.base_url`; no test hardcodes a host.
- **Rationale**: The retired gem's 28 failures were entirely caused by specs hardcoding
  `https://api.sandbox.bml.mv` while the client's constant moved to the real BML host. Deriving
  the stub URL from the client makes that class of drift impossible.
