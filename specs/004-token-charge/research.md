# Phase 0 Research: Token Charge

**Feature**: `004-token-charge` | **Date**: 2026-09-07

## R1. The charge is two calls, and stays two calls

- **Decision**: The library exposes `tokens.charge(customer_id:, transaction_id:, token_id:)`
  and **no** combined create-and-charge convenience.
- **Rationale**: `POST /public-customers/charge` requires an existing `transactionId`. A caller
  must therefore create a transaction first. A helper hiding both behind one call would (a)
  obscure a money-moving side effect behind a name that does not mention it, and (b) leave a
  partial-failure window invisible — if creation succeeds and the charge times out, the caller
  needs to know a transaction exists in order to reconcile. Constitution V's clause "if BML
  requires two calls, this library MUST NOT present one that silently performs both" was added
  during the migration precisely for this case.
- **Alternatives considered**: A `charge_new(amount:, …)` convenience (rejected as above); a
  block-form API that yields the created transaction (rejected — ceremony without removing the
  hazard).

## R2. Never retry a charge

- **Decision**: Zero automatic retries. One attempt, then raise.
- **Rationale**: Retry on a charging call is safe only with a server-side idempotency key, and
  the charge schema has exactly three fields — `customerId`, `transactionId`, `tokenId` — none of
  which is documented as an idempotency key. A retried charge could take payment twice.
- **Is `transactionId` a de-facto idempotency key?** Plausibly — charging the same transaction
  twice may well be rejected — but that is `[UNVERIFIED]` item #3, and building retry on an
  unconfirmed guess is the exact failure this migration exists to correct. Even once confirmed,
  retry should be the caller's decision on a money movement.
- **Alternatives considered**: Retry only on connection-refused (rejected — a refusal after the
  request was written is indistinguishable from one before); retry with reconciliation built in
  (rejected — the library cannot know the caller's tolerance for a double charge).

## R3. Timeout recovery is reconciliation, not retry

- **Decision**: `AvailabilityError` from `charge` always names the `transaction_id` in its
  message, and the documented recovery is `client.transactions.retrieve(transaction_id)`.
- **Rationale**: A timeout is the one outcome where the result is genuinely unknown — the request
  may have been applied. The only safe next action is to ask BML what happened. Putting the id in
  the message means a caller reading a log at 3am has what they need. This is what "errors MUST
  be surfaced with actionable context" (Constitution IV) means concretely.

## R4. Decline and outage must never collapse

- **Decision**: A returned `TransactionRecord` is a business outcome; a raised error is a
  transport or validation outcome. Never convert between them.
- **Rationale**: A merchant running scheduled billing acts differently on each. Retrying a
  decline annoys the customer and can incur scheme fees; treating an outage as a decline loses
  revenue and may wrongly cancel a subscription. Any library that reduces both to `nil` or
  `false` forces the caller to guess.
- **Open**: whether BML signals a decline as `200`-with-failed-state or as a non-2xx status is
  `[UNVERIFIED]` item #2. The library handles both: a `200` maps to a record, a 4xx maps to an
  error, and the taxonomy in `data-model.md` holds either way.

## R5. `tokenId` — the blocking unknown

- **Decision**: Assume `Token#id`; **block release** until confirmed.
- **Rationale**: A token has both `id` and `token`. The retrieve/delete path parameter is
  `tokenId` and resolves to `id`, so consistent naming makes `id` the strong inference. But the
  document never says so, and the cost of being wrong is charging against the wrong identifier.
  In the best case it errors; in the worst it charges something unintended.
- **Resolution procedure** (see `data-model.md`): charge a known token with `id`; if rejected,
  create a **new** transaction and retry with `token`. Never reuse the first transaction, since
  charging an already-charged transaction is itself unverified (item #3) — reusing it would
  confound two unknowns in one test.
- **Alternatives considered**: Accept either and let BML decide (rejected — a failed first
  attempt followed by a second with a different value is indistinguishable from a retry, which
  R2 forbids); ship with a caveat in the docs (rejected — a money-movement ambiguity is not a
  documentation problem).

## R6. Audit failed charges, not just successful ones

- **Decision**: Emit an audit record for declines, validation failures and availability failures,
  as well as successes.
- **Rationale**: An audit trail that records only successes is close to useless for a charging
  operation. "Why was this customer charged?" and "why wasn't this customer charged?" are equally
  important questions, and a failed charge on a stored card is exactly the event a dispute or a
  reconciliation investigation turns on. The record is emitted before the error is re-raised, so
  a raise never loses it.
- **Alternatives considered**: Audit successes only, matching the other features (rejected — the
  other features do not move money; this asymmetry is deliberate and worth the inconsistency).

## R7. No `amount` on the charge

- **Decision**: `charge` accepts no `amount` keyword, and a unit test enforces that.
- **Rationale**: The charge schema has no amount field; the transaction supplies it. Accepting an
  `amount` the library then discarded — or worse, used to mutate the transaction first — would
  create a caller expectation the platform cannot honour. To charge a different amount, create a
  different transaction.

## R8. Where the method lives

- **Decision**: `client.tokens.charge`, not `client.transactions.charge`.
- **Rationale**: The endpoint sits under `/public-customers`, and the operation's subject is the
  stored token — it is the only thing in the request that is not merely an addressing id. The
  return type being a transaction does not make it a transaction operation.
- **Alternatives considered**: `client.transactions.charge` (rejected — matches the return type
  rather than the subject and the path); a standalone `client.charges` resource (rejected — one
  method does not warrant a resource, and BML has no charges collection).
