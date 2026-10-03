# Feature Specification: Transaction Status Webhook Handler

**Feature Branch**: `005-webhook-handler`

**Created**: 2026-09-21

**Status**: Draft — **one narrow observation outstanding, see Dependencies**

**Input**: User description: "Add webhook handler for transaction status changes"

## Context & Source-of-Truth Finding *(read first)*

`reference/Connect-API.json` (Connect API v2.0) documents how a merchant **registers** to receive
notifications, and nothing about the notification itself:

| Documented | Not documented |
|------------|----------------|
| `POST /public/webhooks` — create a company-wide hook from a `hookUrl` | The callback's HTTP method |
| `DELETE /public/webhooks` — delete a hook by the same `hookUrl` | The callback's payload shape |
| `Webhook` schema — `id`, `companyId`, `hookUrl`, `created`, `updated` | Any signature, secret, or authentication on the callback |
| `webhook` (a URL) as an optional field on `POST /public/v2/transactions` | Which events fire, and the set of transaction `state` values |
| — | Retry, ordering, and at-least-once delivery behavior |

The `Transaction.state` field is typed only as a non-empty string; the document enumerates no
states anywhere. The only states observable in it are `INITIATED` and `QR_CODE_GENERATED`, both
from a single example.

Under Constitution Principle III, **the entire inbound surface is `[UNVERIFIED]`**. The trust model
chosen below (verify-by-fetch, FR-006) is what makes the feature buildable anyway: because the
payload is never trusted, the library needs only **one** field from it to do its job — the
transaction identifier — and takes every consequential fact from a fresh authoritative retrieve.
A second field, a claimed status, is read where present, but only to compare against the
authoritative one (FR-010); nothing is ever reported from it. That reduces the blocking unknown
from "the whole payload contract" to "which field carries the transaction id". See
[Dependencies](#dependencies).

## Clarifications

### Session 2026-09-21

- Q: How should a merchant's application invoke the handler? → A: **Framework-agnostic.** The
  library accepts the raw body and headers and returns a structured result. It adds no web-framework
  dependency and does not own routing; the caller wires it into whatever endpoint they already have.
- Q: How does the library establish that a status-change payload is genuine, given that BML
  documents no signature, secret, or authentication on the callback? → A: **Mandatory
  verify-by-fetch.** The inbound payload is treated as an untrusted *hint* that something changed.
  The library re-retrieves the transaction from BML and reports only what that authoritative
  response says. There is no mode in which a payload's own claims are reported as fact.
- Q: Is webhook registration (`POST`/`DELETE /public/webhooks`) in scope? → A: **No.** This feature
  handles inbound notifications only. Registration remains the merchant portal's job, or the
  per-transaction `webhook` field already shipped in feature `003`. See [Out of Scope](#out-of-scope).
- Q: If the payload is never trusted, why parse it at all? → A: To learn *which* transaction to
  retrieve, and to avoid making the caller do that parsing. The payload answers "look at this
  one"; BML's retrieve answers "and here is what is true about it".

### Session 2026-09-21 (clarify)

- Q: How should the library figure out which field of the untrusted payload holds the transaction
  identifier? → A: **A built-in candidate list, overridable by the caller.** The library ships a
  short, documented list of candidate field names and accepts a caller-supplied extractor that
  replaces it outright. Neither yielding an identifier is a loud error, never a guess. This is what
  moves the outstanding UAT observation off the release path: a caller who knows the real field can
  always say so.
- Q: If the verifying retrieve reports an older status than the notification claimed — BML's read
  path lagging the event that fired the callback — what should the library do? → A: **One delayed
  re-check.** When the payload carries a claimed status that disagrees with the authoritative one,
  the library waits a short bounded interval and retrieves once more, then reports whatever that
  second retrieve says — even if it still disagrees. At most one re-check per notification. The
  delay is configurable with a documented default and may be set to zero to disable the re-check
  entirely, because the re-check spends time inside the caller's request.
- Q: How should the library stop a public notification endpoint from being used to generate
  unlimited outbound calls to BML? → A: **A hard per-notification cap, plus an optional shared
  secret.** At most two retrieves per handled notification and no retry of the verifying retrieve.
  Separately, the caller MAY configure a shared secret that must match before any retrieve is spent.
  The secret gates **spend, not trust**: a matching secret never causes the payload to be believed,
  and verify-by-fetch still applies in full.
- Q: What should the library tell the host application to return to BML as the HTTP response? →
  A: **An advisory status on every result and error.** The library is the only party that knows
  which failures are transient and which are permanent, so it carries a suggested HTTP status the
  caller MAY return as-is or ignore. It is advice, not control: the library never writes a response
  and adds no web-framework dependency.
- Q: Should the structured result hand the caller the raw untrusted payload back? → A: **No — named
  diagnostics only.** The result exposes the transaction identifier, the payload's claimed status,
  and whether it disagreed with the authoritative one, all masked. The raw body is never exposed on
  the result, because a payload-shaped object invites a caller to read a status from it and defeat
  verify-by-fetch. The raw body remains available where it belongs: in the masked audit record.

### Session 2026-09-27 (clarify)

- Q: When a shared secret is configured (FR-009a), how does the secret value reach the library,
  given that BML controls the callback's headers and the merchant only controls the URL it
  registered? → A: **The caller presents the value; the library only compares it.** The handling
  operation accepts an optional presented-secret value that the caller extracted from wherever it
  actually arrived — a query parameter of the registered URL, a path segment, or a header. The
  library never guesses a location and never needs the request URL. It owns the constant-time
  comparison, the rejection before any retrieve is spent, and the audit record.

- Q: Which inbound body formats must the handler accept before it may reject a delivery as the
  wrong media type (FR-003)? → A: **JSON and form-encoded, chosen by declared `Content-Type`, with a
  documented fallback attempt.** The two formats a callback realistically arrives as are both
  accepted, selected by the declared type; when the type is absent or unrecognized the library
  attempts each in a documented order before rejecting. Both formats are `[UNVERIFIED]` until a real
  delivery is observed. This is two named formats, not open-ended sniffing.

- Q: What should the default re-check delay be, the one FR-010b requires be documented? → A:
  **3 seconds.** Long enough to clear a brief read-path lag, and settable to zero to disable the
  re-check. Because the delay is spent inside the caller's request, the quickstart MUST state the
  figure plainly so an endpoint under a tighter deadline than 3 seconds knows to set it to zero.

- Q: Should the handler enforce a maximum inbound body size, rejecting an oversized body before it
  is parsed? → A: **No — the host application's job, documented explicitly.** The library imposes no
  size or nesting limit and parses whatever body it is handed. Bounding request size belongs with the
  party that owns the socket, consistent with hosting the endpoint being the merchant's
  responsibility. This is an accepted tradeoff, not an oversight, and the quickstart MUST say so
  rather than leave a caller to discover it.

- Q: What does a caller-supplied identifier extractor receive, and what must it return
  (FR-002/FR-002b)? → A: **The parsed body and the delivery's headers; it returns an identifier or
  nothing.** Headers are included because an undocumented callback may well carry the identifier
  there, and a body-only extractor would leave exactly that merchant blocked — defeating the escape
  hatch this spec relies on. Returning nothing means "not found" and produces the same loud
  validation error as an exhausted candidate list (FR-002); it never yields a guess.

### Session 2026-09-27 (post-analysis)

- Q: When card-like data arrives inside a notification payload, should the library refuse the
  delivery or scrub the data and carry on handling it? (FR-011) → A: **Scrub and carry on.** Inbound
  values are masked everywhere they could surface, and card-like data does **not** by itself reject
  the delivery. This deliberately diverges from how the library treats caller-supplied input, where a
  PAN raises: `Masking.looks_like_pan?` fires on any 13–19 digit Luhn-valid run, so a coincidental
  merchant reference would otherwise discard a genuine payment confirmation permanently. Nothing is
  transmitted, logged, or persisted either way.

- Q: When the spec says handling the same notification twice must produce "equivalent results"
  (FR-014, SC-006), equivalent in what sense? → A: **Identical given an unchanged authoritative
  record.** Two handlings of the same delivery MUST produce equal results when BML's record has not
  changed in between, and the library MUST carry no state from one handling to the next. When the
  record *has* changed, the second handling MUST report the new status — that is the feature working,
  not a violation, and the literal "always identical" reading would require a cache that FR-013 and
  the no-datastore assumption forbid.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - React to a transaction reaching a final state (Priority: P1)

A merchant taking payments through the hosted payment page cannot learn the outcome from the
create call — the cardholder completes payment out of band. Today the only way to find out is to
poll. This merchant wants their application to be notified when a transaction's status changes,
so that an order is fulfilled the moment payment confirms and abandoned the moment it fails.

**Why this priority**: This is the entire purpose of the feature. Polling is the current
workaround, and it is slow, wasteful, and racy.

**Independent Test**: Hand the library a representative notification body and headers, and confirm
it returns an authoritative transaction record the application can act on, without the application
writing any parsing code of its own.

**Acceptance Scenarios**:

1. **Given** a registered notification URL and a transaction that reaches a paid status, **When**
   the application hands the delivery to the library, **Then** the library returns the transaction
   identifier and the authoritative current status, and the application acts on it without parsing
   raw input.
2. **Given** a notification body that is malformed, empty, or in a format outside the accepted set,
   **When** it is handled, **Then** the library raises a descriptive validation error, makes **no**
   remote call, and returns nothing that could be mistaken for an event.
3. **Given** a genuine notification delivered as form-encoded rather than JSON, **When** it is
   handled, **Then** the identifier is extracted and the delivery is handled identically to its JSON
   equivalent.
4. **Given** a notification from which no transaction identifier can be extracted, **When** it is
   handled, **Then** the library raises rather than guessing an identifier or returning a partial
   result.
5. **Given** BML reports a status this library has never seen, **When** the result is returned,
   **Then** that status is passed through verbatim rather than coerced, dropped, or mapped to a
   guess.
6. **Given** the same notification is delivered twice while BML's record is unchanged, **When** both
   are handled, **Then** the two results are equal, the handler performs no money-moving or
   state-changing side effect, and no state carries from the first handling into the second.
7. **Given** a notification whose claimed status disagrees with the first authoritative retrieve,
   **When** it is handled, **Then** the library re-checks exactly once after a short delay and
   reports the second retrieve's status.
8. **Given** any outcome at all, **When** the result is returned, **Then** it carries an advisory
   HTTP status the application can return to BML, and the application is free to ignore it.

---

### User Story 2 - Refuse to act on an unauthenticated payload (Priority: P1)

A merchant's notification URL is, by necessity, a publicly reachable endpoint. Anyone who
discovers it can post to it. This merchant needs assurance that a forged "payment confirmed"
notification cannot cause goods to ship.

**Why this priority**: Equal to User Story 1 and inseparable from it. A notification handler that
trusts its input is a fraud vector, not a feature. Constitution Principle I requires the most
protective default.

**Independent Test**: Hand the library a well-formed forgery claiming a transaction is paid, while
BML reports that transaction as unpaid, and confirm the library reports unpaid.

**Acceptance Scenarios**:

1. **Given** a forged payload claiming a transaction is paid, **When** BML's authoritative record
   says otherwise, **Then** the library reports BML's status and never the payload's claim.
2. **Given** any notification at all, **When** it is handled, **Then** the status the caller acts
   on originates from a fresh authoritative retrieve, verified by a test asserting the retrieve
   occurred.
3. **Given** BML is unreachable at the moment a notification arrives, **When** the retrieve fails,
   **Then** an availability error is raised and the library does **not** fall back to reporting the
   payload's claims.
4. **Given** a forged payload naming a transaction that does not exist, **When** it is handled,
   **Then** the retrieve fails and the error distinguishes "no such transaction" from a transport
   failure.
5. **Given** a payload containing anything resembling card data, **When** it is handled, **Then**
   that data is never written to a log, an audit record, or an error message, **and** the delivery is
   still handled normally rather than rejected (FR-011a).
6. **Given** a shared secret is configured, **When** the caller presents no secret value or a
   wrong one, **Then** the delivery is rejected before any retrieve is spent.
7. **Given** a shared secret is configured and matches, **When** the notification is handled,
   **Then** the verifying retrieve still occurs and the reported status is identical to what the
   same notification would produce with no secret configured.
8. **Given** any handled notification, **When** the caller inspects the result, **Then** no raw
   inbound body and no payload-shaped object is reachable from it.

---

### User Story 3 - Diagnose a notification that did not arrive or was not accepted (Priority: P2)

An operator investigating an order stuck in "awaiting payment" needs to tell apart three cases:
BML never sent a notification, it sent one the endpoint rejected, or it sent one that was accepted
but produced no action.

**Why this priority**: Valuable operationally, and the audit trail is a constitutional requirement
(Principle IV), but it only matters once handling exists.

**Independent Test**: Handle an accepted notification and a rejected one, and confirm each leaves a
distinguishable, card-data-free record.

**Acceptance Scenarios**:

1. **Given** any notification the library handles, **When** it completes, **Then** an audit record
   is emitted capturing what arrived, when, and the outcome, containing no card data and no secret.
2. **Given** a rejected notification, **When** the rejection is recorded, **Then** its reason is
   distinguishable from an accepted delivery and from a transport failure.
3. **Given** a payload whose claimed status disagrees with BML's authoritative status, **When** it
   is handled, **Then** the disagreement is recorded — it is the signature of a forgery attempt or
   a stale replay, and an operator needs to see it.
4. **Given** a transaction whose notification never arrived, **When** the operator reconciles by
   retrieving the transaction directly, **Then** the authoritative status is obtainable without
   this feature.

---

### Edge Cases

- **Forged payload** — the defining threat, and the reason for verify-by-fetch. The payload's
  claims are never reported as fact, so a forgery can at worst cause a wasted retrieve.
- **Replayed payload** — an attacker re-sends a genuine old notification. Because the status always
  comes from a fresh retrieve, a replay returns *current* truth rather than stale truth, which
  substantially defuses it. The library still owns no datastore and cannot deduplicate deliveries
  on the caller's behalf; it surfaces the transaction identifier so the caller can.
- **Out-of-order delivery** — largely neutralized for the same reason: two deliveries handled in
  either order both report the current authoritative status. Note that an out-of-order delivery
  legitimately disagrees with the authoritative status, so it will trigger the re-check (FR-010) and
  pay its delay without any benefit. This is an accepted cost of the re-check.
- **Stale authoritative read** — BML's read path lags the event that fired the callback, so the
  first retrieve reports the old status. Handled by one delayed re-check (FR-010). If the lag
  exceeds the configured delay the library still reports a stale status; callers MUST treat the
  reported status as current-as-of-retrieve, not as final.
- **Re-check latency in the caller's request** — the delay is spent synchronously, and defaults to 3
  seconds (FR-010b). An endpoint whose response deadline is at or below that MUST set the delay to
  zero rather than risk the notification sender timing out and redelivering, which would convert a
  latency problem into a replay problem. Note this cost lands on every disagreeing delivery,
  including every replay, which disagree legitimately and gain nothing from the wait.
- **Undeclared or unrecognized `Content-Type`** — the published contract states nothing about the
  callback's content type, so the library MUST NOT depend on one being declared. It attempts the
  accepted formats in a documented order (FR-003a) and rejects only when none parses, so a missing
  header degrades to a parse attempt rather than to a total failure.
- **Unknown status value** — passed through verbatim. The published contract enumerates no states,
  so any local allow-list would be an invention (Constitution V).
- **Identifier outside the body** — an undocumented callback may carry the transaction identifier in
  a header rather than the body. The built-in candidate list covers body fields only; a caller in this
  position supplies an extractor, which receives the headers as well (FR-002c).
- **Notification for an unknown transaction** — the retrieve fails with a not-found error, which
  MUST remain distinguishable from a transport failure.
- **Retrieve amplification** — a flood of forged notifications becomes a flood of retrieves. Bounded
  by the two-retrieve cap (FR-009) and, when configured, filtered by the shared secret (FR-009a)
  before any call is spent. With no secret configured, every inbound request still costs a retrieve,
  and this MUST be documented rather than left for the caller to discover.
- **Secret configured but notification URL predates it** — a delivery for which the caller can
  present no secret value is rejected without a retrieve. An operator enabling the secret MUST
  re-register or update the URL first, or legitimate notifications will be silently dropped. The
  rejection is audited so this is diagnosable.
- **Secret with nowhere to travel** — because BML chooses the callback's headers, a merchant can
  realistically carry a secret only in the URL it registered. The library takes no position on this:
  it compares whatever value the caller presents (FR-009e). A caller who configures a secret but
  never presents a value will reject every delivery, which the audit record makes visible
  immediately rather than after a missed payment.
- **Oversized or deeply nested body** — a public endpoint can be posted an arbitrarily large or
  deeply nested body, and the library parses whatever it is handed (FR-003c). The two-retrieve cap
  bounds outbound calls but bounds nothing about parsing work, and a configured secret does not help
  because the body is already in memory by the time the handler is called. The host application MUST
  bound request size at its own boundary. This is an accepted tradeoff: the library does not own the
  socket and a limit it invented would be the wrong one.
- **Slow caller** — the library returns promptly and does not block on caller work; a notification
  sender that times out will retry, which is the replay case above.
- **Card-like data in a payload** — masked everywhere it could surface, and handled normally. The
  delivery is not rejected, because the PAN screen matches any Luhn-valid 13–19 digit run and a
  merchant reference can satisfy that by coincidence; refusing would permanently discard a genuine
  notification to prevent a leak that masking has already prevented (FR-011a).
- **Misconfigured client** — raises an authentication/configuration error before any retrieve.

## Requirements *(mandatory)*

### Functional Requirements

#### Handling an inbound notification

- **FR-001**: The library MUST expose a framework-agnostic handling operation that accepts a raw
  inbound notification — its body and its headers, plus, when a shared secret is configured, the
  presented secret value the caller extracted from the delivery (FR-009a) — and returns a structured
  result. It MUST NOT
  add a web-framework dependency, own routing, or require the caller to use any particular
  application framework.
- **FR-002**: The library MUST extract the transaction identifier from the inbound payload using a
  built-in list of candidate field names, and MUST allow the caller to supply their own extractor
  that overrides that list entirely. When neither the caller's extractor nor any built-in candidate
  yields an identifier, the library MUST raise a descriptive validation error rather than guess.
- **FR-002a**: The built-in candidate list MUST be documented, MUST be short, and every entry MUST
  be justified in `contracts/bml-remote.md` and marked `[UNVERIFIED]` until a real delivery confirms
  it. The library MUST NOT silently broaden the list to whatever happens to parse.
- **FR-002b**: When a caller-supplied extractor is present, the library MUST use it and MUST NOT
  fall back to the built-in candidates, so that a caller who knows the true field is never
  overridden by the library's guess.
- **FR-002c**: A caller-supplied extractor MUST receive both the parsed body and the delivery's
  headers, so a caller whose identifier arrives in a header rather than the body is not blocked. It
  MUST return either a transaction identifier or nothing; returning nothing MUST produce the same
  descriptive validation error as an exhausted built-in candidate list (FR-002), with no remote call
  and no guessed identifier. The extractor MUST NOT be handed the raw body, keeping the untrusted
  bytes on the audit path (FR-004b) rather than in caller-supplied code.
- **FR-003**: The library MUST reject a body that is malformed, empty, or in a format outside the
  accepted set (FR-003a) with a descriptive validation error, and MUST make **no** remote call in
  that case.
- **FR-003a**: The library MUST accept two body formats — JSON and form-encoded — and MUST select
  between them by the delivery's declared `Content-Type`. When the declared type is absent or
  unrecognized, the library MUST attempt the accepted formats in a documented order and reject only
  when none parses. It MUST NOT accept a format outside this documented set, and MUST NOT treat "it
  happened to parse" as evidence the format is correct.
- **FR-003b**: Both accepted formats MUST be recorded in `contracts/bml-remote.md` and marked
  `[UNVERIFIED]` until a real delivery confirms which one BML actually sends (FR-018). The library
  MUST NOT declare either format verified on the strength of a stubbed test alone.
- **FR-003c**: The library MUST NOT impose a maximum body size or a structural nesting limit, and
  MUST document that it does not: it parses whatever body the host application hands it, so bounding
  request size and rejecting oversized deliveries at the socket is the host application's
  responsibility (consistent with FR-009c). The quickstart MUST state this plainly, because a caller
  who assumes the library bounds its own parsing work would be wrong.
- **FR-004**: The returned result MUST expose the transaction identifier and the authoritative
  transaction record, including its status and the time of the change.
- **FR-004a**: The result MUST NOT expose the raw inbound body, nor any object shaped like the
  payload. Payload-derived information MUST be limited to individually named, masked fields — the
  claimed status and whether it disagreed — so no caller can read a status off an untrusted
  structure and mistake it for the authoritative one.
- **FR-004b**: The raw body MUST remain available for diagnosis through the masked audit record
  (FR-015), which is where forensic detail belongs, rather than on the result.
- **FR-005**: The library MUST pass any status value through verbatim. It MUST NOT coerce, map, or
  reject a status merely because it is unrecognized, and MUST NOT ship an enumeration of states
  that the published contract does not define.

#### Establishing trust in a notification

- **FR-006**: The library MUST establish authenticity by **re-retrieving the transaction from BML**
  and reporting only what that authoritative response says. The inbound payload is an untrusted
  hint that something changed; its own claims MUST NEVER be reported to the caller as fact.
- **FR-007**: The library MUST NOT offer any mode, option, or flag that skips the verifying
  retrieve and reports the payload's claims instead.
- **FR-008**: When the verifying retrieve fails, the library MUST raise. It MUST NOT degrade to
  reporting the payload's claims, and MUST distinguish an unreachable BML (availability) from a
  transaction that does not exist (not found) from a rejected credential (authentication).
- **FR-009**: A single handled notification MUST cause **at most two** retrieves — the verifying
  retrieve and, where FR-010 applies, one re-check. The verifying retrieve MUST NOT be auto-retried
  on transport failure; a failure raises (FR-008) rather than consuming further attempts. No inbound
  request, however malformed or forged, may exceed this cap.
- **FR-009a**: The library MUST support an optional caller-configured shared secret. When one is
  configured, the handling operation MUST accept a **presented secret value supplied by the caller**
  — extracted from wherever it actually arrived in the delivery — and MUST compare it against the
  configured secret **before** performing any retrieve. A delivery presenting no value, or a
  non-matching one, MUST be rejected without spending a remote call.
- **FR-009e**: The library MUST NOT infer where the secret travels. It MUST NOT require the request
  URL, MUST NOT read the secret from a header, query parameter, or path segment of its own choosing,
  and MUST NOT ship a default location — the published contract documents no inbound authentication,
  so any such location would be an invention. Extraction is the caller's, comparison is the
  library's.
- **FR-009b**: The shared secret gates **spend, not trust**. A matching secret MUST NOT cause the
  payload's claims to be believed, MUST NOT skip the verifying retrieve, and MUST NOT weaken any
  part of FR-006 through FR-008. A library configured with a secret and one configured without it
  MUST report identical statuses for the same genuine notification.
- **FR-009c**: When no secret is configured, the library MUST operate exactly as FR-009 describes
  and MUST document that every inbound request then costs a real retrieve, so the host application
  is responsible for protecting its own endpoint.
- **FR-009d**: Secret comparison MUST be resistant to timing analysis (FR-012), and a rejected
  delivery MUST be audited (FR-015) and distinguishable from a malformed one (FR-016).
- **FR-010**: If the payload carries a claimed status that disagrees with the authoritative status,
  the library MUST wait a short bounded interval and perform **exactly one** further retrieve, then
  report whatever that second retrieve says. It MUST report only an authoritative status, never the
  payload's claim, and MUST record the disagreement whether or not the re-check resolves it.
- **FR-010a**: The re-check MUST occur at most once per handled notification. A notification MUST
  NOT be able to cause a third retrieve, a re-check loop, or an unbounded wait, regardless of what
  the payload claims.
- **FR-010b**: The re-check delay MUST be configurable, MUST default to **3 seconds**, and MUST be
  settable to zero to disable the re-check entirely. The library MUST document the default figure
  explicitly, and MUST document that the delay is spent inside the caller's request — so an endpoint
  whose own response deadline is at or below 3 seconds knows it must set the delay to zero.
- **FR-010c**: The re-check MUST fire only when the payload carries a claimed status that can be
  compared against the authoritative one. When the payload carries no comparable status — which the
  published contract does not guarantee it does — the library MUST report the first retrieve and
  MUST NOT re-check speculatively.
- **FR-010d**: When the re-check still disagrees with the payload, that outcome MUST be reported and
  audited as a disagreement rather than escalated to an error. A persistent disagreement is the
  expected shape of a replayed or forged delivery, not a failure.
- **FR-011**: The library MUST NEVER transmit, log, or persist a PAN, CVV, or any Sensitive
  Authentication Data arriving in a notification. Inbound values MUST be screened and masked, using
  the library's existing masking helpers, before reaching any log line, audit record, error message,
  or result.
- **FR-011a**: Card-like data in a payload MUST NOT by itself cause the delivery to be rejected. The
  library MUST mask it and continue handling. This **deliberately diverges** from the library's
  treatment of caller-supplied input, where a PAN raises: the PAN screen matches any 13–19 digit
  Luhn-valid run, so on an inbound payload it can fire on a coincidental merchant reference or order
  number. Rejecting there would advise a permanent status (FR-016c) and discard a genuine payment
  confirmation for good. Masking already satisfies FR-011 in full, so refusal would buy nothing and
  cost availability. This divergence MUST be documented at the screening site so it is not "fixed"
  later.
- **FR-012**: Any secret introduced by this feature — including the optional shared secret of
  FR-009a — MUST be supplied through configuration or the environment, MUST NEVER be hardcoded, and MUST NEVER appear in a log, audit record, or error
  message. Any comparison of a secret MUST be resistant to timing analysis.

#### Idempotence and delivery semantics

- **FR-013**: Handling a notification MUST be free of side effects other than the verifying
  retrieve, the optional re-check (FR-010), logging, and auditing. It MUST NOT move money, change
  transaction state, or mutate stored data.
- **FR-014**: Handling the same notification twice MUST produce equal results **given an unchanged
  authoritative record**, and the library MUST carry no state from one handling to the next. When the
  authoritative record has changed between two deliveries, the second handling MUST report the new
  status — reporting current truth is the feature working, not a breach of this requirement. The
  library MUST NOT cache a previous result to manufacture identical output.
- **FR-014a**: The library MUST document that it does **not** deduplicate across deliveries, and that
  replay and ordering protection remain the caller's responsibility. The transaction identifier is
  surfaced on the result (FR-004) precisely so the caller can implement them.

#### Cross-cutting

- **FR-015**: Every notification handled — accepted or rejected — MUST emit an audit record
  capturing what arrived, when, and the outcome, sufficient to reconstruct the delivery without
  exposing protected data.
- **FR-016**: A rejected notification, an accepted one, a not-found transaction, and a transport
  failure MUST be observably distinguishable from one another.
- **FR-016a**: Every result and every error this feature produces MUST carry an advisory HTTP status
  code indicating what the host application should return to BML. The advice MUST distinguish
  **permanent** outcomes — where redelivery cannot help — from **transient** ones, where redelivery
  is the desired behavior.
- **FR-016b**: The advisory status MUST be advice only. The library MUST NOT write, send, or
  otherwise control an HTTP response, MUST NOT require the caller to honor it, and MUST NOT acquire
  a web-framework dependency in order to express it (FR-001).
- **FR-016c**: A failure to reach BML MUST advise a transient status so the event is redelivered
  rather than silently lost. A malformed body, a failed secret check, or an unextractable identifier
  MUST advise a permanent status so forged or broken deliveries are not redelivered indefinitely.
- **FR-016d**: A not-found transaction MUST advise a **permanent** status. It is far more likely to
  be a forged identifier than a real transaction BML has lost, and advising redelivery would let a
  forger sustain traffic indefinitely. This choice MUST be documented, since it trades away recovery
  in the rare genuine race.
- **FR-016e**: The full mapping of outcome to advisory status MUST be documented in the feature's
  quickstart, so a caller who ignores the advice can still reproduce it.
- **FR-017**: The library MUST authenticate the verifying retrieve using the raw `Authorization`
  API key — no `Bearer`, no `X-App-Id` — matching every other resource in this library, and MUST
  operate against whichever environment is selected on the client with no code change.
- **FR-018**: Every path, method, and field this feature sends to BML MUST be traceable to
  `reference/Connect-API.json`. Every inbound field the library reads MUST be recorded in
  `contracts/bml-remote.md` and marked `[UNVERIFIED]` until observed against UAT.
- **FR-019**: Every behavior in this feature MUST be independently testable, and the identifier
  extraction path MUST be demonstrated against a genuine UAT delivery before the feature is
  declared complete.

### Key Entities *(include if feature involves data)*

- **Inbound Notification (input only)**: the raw delivery — a body, headers, and, where a secret is
  configured, the caller-presented secret value (FR-009a). Untrusted in whole,
  and never returned to the caller. The library reads from it only the transaction identifier
  (FR-002) and, where present, a claimed status used solely for the disagreement comparison
  (FR-010). The presented secret value is used only for the comparison of FR-009a and MUST NEVER
  appear on the result, in a log, or in an audit record (FR-012). Its full field set is
  `[UNVERIFIED]` pending UAT observation.
- **Status Change Result**: what handling returns. Carries the transaction identifier, the
  authoritative transaction record retrieved from BML, the payload's claimed status, whether that
  claim disagreed with the authoritative one, whether a re-check was performed, and the advisory
  HTTP status (FR-016a). Every payload-derived field is masked and individually named; the result
  MUST NOT expose the raw body or any payload-shaped object.
- **Transaction** (from feature `003`): the authoritative record, obtained by retrieve. This
  feature adds no new transaction entity and does not redefine `state`.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A merchant learns of a transaction's final status from a delivered notification
  rather than by polling, and can act on it without writing parsing code of their own.
- **SC-002**: A forged payload claiming payment succeeded never causes the library to report
  success — verified by a test where the payload claims paid and BML reports unpaid.
- **SC-003**: Every handled notification results in an authoritative retrieve, verified by a test
  asserting no result is ever produced without one.
- **SC-004**: No configuration, option, or code path exists that reports a payload's claimed status
  as fact — verified by a test asserting the handler's public surface offers no such option.
- **SC-005**: 100% of results, logs, audit records, and error messages contain no PAN, no CVV, and
  no secret — verified across accepted, rejected, and card-data-bearing payloads.
- **SC-005a**: A payload carrying a Luhn-valid card-like number is handled normally — one retrieve,
  an authoritative status returned — while that number appears in no log line, audit record, error
  message, or result, verified by a single test asserting both halves.
- **SC-006**: Handling the same notification twice against an unchanged authoritative record produces
  equal results and zero side effects beyond the retrieves, verified by a test that stubs a stable
  retrieve, handles one delivery twice, and asserts both result equality and the expected per-call
  retrieve count.
- **SC-006a**: When the authoritative record changes between two deliveries, the second handling
  reports the **new** status, verified by a test asserting the library does not cache the first
  result.
- **SC-007**: An unrecognized status value reaches the caller unchanged in 100% of cases, verified
  with a status that appears nowhere in this repository.
- **SC-008**: An accepted notification, a malformed one, a not-found transaction, and a transport
  failure are distinguishable in 100% of cases.
- **SC-008a**: A payload whose claimed status disagrees with the first retrieve triggers exactly one
  further retrieve and no more, verified by a test asserting the total retrieve count is two.
- **SC-008b**: With the re-check delay set to zero, a disagreeing payload produces exactly one
  retrieve and no added latency, verified by a test asserting the count is one.
- **SC-008c**: A payload carrying no comparable status never triggers a re-check, verified by a test
  asserting exactly one retrieve.
- **SC-008d**: No inbound request, however malformed or forged, causes more than two retrieves —
  verified by a test that asserts the cap across the malformed, forged, disagreeing, and
  transport-failure cases.
- **SC-008e**: With a shared secret configured, a delivery presenting a wrong or absent secret value
  causes **zero** retrieves, verified by a test asserting no remote call occurred.
- **SC-008f**: The same genuine notification produces an identical reported status whether or not a
  shared secret is configured, verified by a test running both configurations.
- **SC-008g**: Every outcome — accepted, malformed, secret-rejected, unextractable, not-found, and
  unreachable — carries an advisory HTTP status, verified by a test enumerating all of them.
- **SC-008h**: An unreachable BML advises a transient status and a forged or malformed delivery
  advises a permanent one, verified by a test asserting the two are never confused.
- **SC-008i**: The result exposes no raw body and no payload-shaped object, verified by a test that
  asserts the result's public surface offers no route to an unmasked inbound field.
- **SC-008j**: The library reads no secret from any header, query parameter, or path segment of its
  own choosing, verified by a test in which the correct secret is present in the delivery's headers
  but is not presented by the caller, and the delivery is still rejected.
- **SC-008k**: A genuine notification is handled identically whether delivered as JSON or as
  form-encoded, verified by a test running the same delivery in both formats and asserting identical
  reported status and retrieve count.
- **SC-008l**: A body in neither accepted format is rejected with **zero** retrieves, and a delivery
  with an absent or unrecognized `Content-Type` whose body is in an accepted format is still handled,
  both verified by test.
- **SC-008m**: The re-check delay defaults to 3 seconds, verified by a test asserting the configured
  default, and that figure appears in the quickstart alongside the instruction to set it to zero
  under a tighter response deadline.
- **SC-008n**: The quickstart states that the library enforces no inbound body size or nesting
  limit and that bounding request size is the host application's responsibility, verified by review
  of the quickstart alongside FR-003c.
- **SC-009**: Every handled notification produces an audit record, verified for the accepted,
  malformed, status-disagreement, not-found, and unreachable-BML cases.
- **SC-010**: The library ships no enumeration of transaction states, verified by a test asserting
  no state allow-list governs handling.
- **SC-011**: A genuine UAT delivery is observed, the field carrying the transaction identifier is
  confirmed against the built-in candidate list, and the raw delivery is recorded in
  `contracts/bml-remote.md` — with every candidate still unconfirmed left marked `[UNVERIFIED]`.
- **SC-011a**: A caller supplying their own extractor can handle a notification successfully even
  when every built-in candidate is wrong, verified by a test using a payload whose identifier sits
  under a field name the library does not know.
- **SC-011b**: A caller-supplied extractor can resolve an identifier carried in a header rather than
  the body, verified by a test whose payload body contains no identifier at all.
- **SC-011c**: An extractor returning nothing produces the same validation error and **zero**
  retrieves as an exhausted built-in candidate list, verified by a test asserting both the error and
  the absence of any remote call.
- **SC-012**: Integrating the handler into a host application requires no dependency beyond the
  gem itself, demonstrated by a worked example in the feature's quickstart.

## Assumptions

- A merchant's notification endpoint is publicly reachable and transport-secured; securing the
  hosting of that endpoint is the merchant's responsibility, not this library's.
- How a shared secret travels to that endpoint is the merchant's choice and the merchant's
  extraction job. BML controls the callback's headers, so in practice the secret rides in the
  registered URL; the library deliberately takes no position (FR-009e).
- The merchant has already registered a notification URL — through the merchant portal, or via the
  per-transaction `webhook` field shipped in feature `003`. This feature does not register one.
- The library owns no datastore. Deduplication, ordering, and persistence of received events are
  the caller's responsibility; the library's job is to surface enough for the caller to do them.
- The host application bounds inbound request size at its own boundary. The library parses whatever
  body it is handed (FR-003c); it does not own the socket and cannot enforce a limit before the body
  already exists in memory.
- Notifications are assumed at-least-once and possibly out of order, because nothing in the
  published contract promises otherwise. Assuming exactly-once would be an invention.
- The cost of one authoritative retrieve per notification is acceptable, and is the deliberate
  price of never trusting an unauthenticated payload. This is a security decision, not an
  oversight.
- The existing retrieve operation (feature `003`) is correct and available; this feature is a
  consumer of it, not a reimplementation.
- The library's existing audit path — a single structured, masked log line through the client's
  logger — is reused unchanged; this feature adds no separate audit sink.
- The existing v1 SHA1 request signature (`amount`, `currency`, `apiKey`) is an **outbound** signing
  scheme for transaction creation. It is not evidence of any inbound signing scheme and MUST NOT be
  repurposed as one.
- Handling is synchronous, and the re-check delay (FR-010) is spent inside the caller's request —
  up to 3 seconds by default. Queuing a received result for slower downstream work is the caller's
  concern.
- BML's read path may briefly lag the event that fires a notification. Nothing in the published
  contract states this either way, so the re-check (FR-010) is a defensive measure against a
  plausible-but-unconfirmed behavior, not a documented one. The 3-second default is likewise a
  judgment, not an observed figure. If UAT observation shows the retrieve is always immediately
  consistent, the default should be reconsidered — the re-check would then be pure cost on replayed
  deliveries.

## Dependencies

- Feature `003-transactions-v2` — the retrieve operation is the load-bearing dependency of this
  entire feature: it is what makes the trust model work, and what the caller falls back to when a
  notification never arrives.
- The client's existing configuration, error hierarchy, retry policy, audit path, and masking
  helpers.
- Access to BML UAT, plus a publicly reachable endpoint that UAT can actually deliver to — a
  materially harder test setup than any previous feature here, because it requires **inbound**
  network reachability rather than only outbound calls.

### ⚠️ Outstanding observation

**One narrow fact should be observed against UAT: which field of the inbound payload carries the
transaction identifier.** The published contract documents the callback nowhere, so this cannot be
derived from `reference/Connect-API.json`.

Two decisions keep this off the critical path. Verify-by-fetch means nothing in the payload is
trusted, so a wrong guess about any *other* field is inconsequential, and a wrong guess about the
identifier fails loudly at extraction or at the retrieve rather than silently reporting a false
status. The caller-supplied extractor (FR-002) means a merchant who has observed their own
deliveries is never blocked by the library's built-in candidates being wrong.

What remains is a documentation and confidence task, not a correctness gate: register a real UAT
endpoint, drive a transaction to a status change, record the raw observed delivery in
`contracts/bml-remote.md`, and confirm or correct the built-in candidate list. Every built-in
candidate stays `[UNVERIFIED]` until that happens.

## Out of Scope

- **Webhook registration.** `POST` and `DELETE /public/webhooks` are documented and implementable,
  but are explicitly deferred (clarification 2026-09-21). Merchants register through the portal or
  the per-transaction `webhook` field. A later feature may add them.
- Enumerating or validating transaction states. The published contract defines none.
- Retrying, queuing, or persisting received events.
- Deduplicating deliveries across process restarts.
- Hosting, routing, or authenticating the merchant's HTTP endpoint — the library is handed a body
  and headers and returns a result; everything around that is the host application's.
- Changing the per-transaction `webhook` field already accepted by transaction create in feature
  `003`.
- Any notification type other than transaction status changes.
