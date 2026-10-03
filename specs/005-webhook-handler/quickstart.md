# Quickstart: Transaction Status Webhook Handler

**Feature**: `005-webhook-handler`

> ⚠️ **Not release-complete yet.** Which field of the inbound payload carries the transaction
> identifier has not been observed against UAT, so every built-in candidate is `[UNVERIFIED]`. Build,
> merge, and test freely — a wrong candidate fails loudly rather than reporting a false status, and
> `extract_id:` lets a merchant who knows the real field bypass the list. See
> `contracts/bml-remote.md`.

## The whole integration

Your endpoint, your route, your response. The gem is handed a body and returns a value object — it
adds **no** web-framework dependency (SC-012).

```ruby
# config/routes.rb → post "/bml/notify" => "bml#notify"

class BmlController < ApplicationController
  skip_before_action :verify_authenticity_token   # BML is not a browser

  def notify
    result = BML.client.webhooks.handle(
      body:    request.body.read,
      headers: request.env
    )

    Order.find_by!(transaction_id: result.transaction_id)
         .apply_bml_status(result.status)          # ← authoritative, from BML

    head result.advisory_http_status               # 200
  rescue BMLConnect::Error => e
    head e.advisory_http_status || 500             # 4xx = stop; 503 = please redeliver
  end
end
```

That is the entire feature. Everything below is what the five lines are protecting you from.

## The status never comes from the payload

```ruby
result.status          # authoritative — retrieved fresh from BML
result.claimed_status  # what the delivery claimed. Diagnostic only. Never act on it.
result.disagreed?      # they differed → a replay, a lag, or a forgery
```

A forged "payment confirmed" posted to your public endpoint cannot ship goods: the library retrieves
the transaction and reports what BML says. There is no flag that turns this off (FR-007, SC-004) —
`client.webhooks.handle(verify: false)` raises `ArgumentError`, because the option does not exist.

Treat `result.status` as **current-as-of-retrieve**, not final. And expect states this gem has never
heard of — the published contract enumerates none, so nothing is coerced or rejected (FR-005).

## Deciding what to return to BML

Every result and every error carries `advisory_http_status`. It is advice; the library never writes a
response (FR-016b). The full mapping (FR-016e):

| Outcome | Advisory | Meaning to the sender |
|---|---|---|
| Accepted | `200` | done |
| Malformed / empty / unparseable body | `400` | permanent — do not redeliver |
| Secret absent or wrong | `401` | permanent |
| No identifier extractable | `422` | permanent |
| Transaction does not exist | `422` | permanent |
| BML unreachable, timeout, 5xx, rate limited | `503` | **transient — please redeliver** |
| Our API key rejected | `503` | transient |

**Why a missing transaction advises `422` and not `404`**: `404` from an HTTP endpoint reads as "no
such endpoint". A sender that decides your hook URL is gone may stop delivering, so one forged
identifier would become an outage for every genuine notification after it. This trades away recovery
in the rare genuine race, deliberately (FR-016d).

**Why a rejected credential advises transient**: redelivery cannot help until an operator fixes the
key — but advising permanent would discard genuine events for the whole duration of the mistake.

## Bounding the cost of a public endpoint

At most **two** retrieves per notification, neither auto-retried (FR-009). Nothing a payload claims
can produce a third.

With **no secret configured, every inbound request costs a real retrieve.** Your endpoint is public;
protecting it is yours (FR-009c). Two things to do about it:

**1. A shared secret — gates spend, not trust.**

```ruby
# registered hook URL: https://you.example/bml/notify?t=SECRET
result = BML.client.webhooks.handle(
  body:             request.body.read,
  headers:          request.env,
  presented_secret: params[:t]
)
```

with `options: { webhook_secret: ENV["BML_WEBHOOK_SECRET"] }` on the client. A delivery presenting no
value or the wrong one is rejected with **zero** retrieves.

**You extract it; the library only compares it** (constant-time). The library never guesses where the
secret travels and never asks for the request URL (FR-009e) — BML controls the callback's headers, so
in practice a secret can only ride in the URL you registered, and a default location would be an
invention. A matching secret never causes the payload to be believed: the retrieve still happens and
the reported status is identical either way (FR-009b).

> **Enabling a secret on an existing hook?** Re-register or update the URL **first**. Deliveries
> arriving with nothing to present are rejected, and legitimate notifications drop silently until you
> do. The rejections are audited, so this is diagnosable — but only if you look.

**2. Bound the request size at your web server.** The library enforces no size or nesting limit and
parses whatever you hand it (FR-003c). It does not own the socket, so a limit it invented would be the
wrong one. Nginx `client_max_body_size`, or a Rack middleware, is the right place.

## The re-check, and the 3 seconds it may cost you

When the payload's claimed status disagrees with the first retrieve, the library waits and retrieves
once more — BML's read path may lag the event that fired the callback.

**The default delay is 3 seconds, and it is spent inside your request** (FR-010b).

```ruby
options: { webhook_recheck_delay: 0 }   # if your response deadline is ≤ 3s
```

Set it to zero if your endpoint is under a tighter deadline than that. A sender that times out will
redeliver, which converts a latency problem into a replay problem. At zero you get exactly one
retrieve, the first result, and the disagreement is still recorded.

Note the cost lands on every disagreeing delivery — **including every replay**, which disagrees
legitimately and gains nothing from the wait.

## When the built-in candidates are wrong

The list is `transactionId`, `transaction_id`, `id`, top-level keys only, all `[UNVERIFIED]`. If you
have observed your own deliveries:

```ruby
BML.client.webhooks.handle(
  body:       body,
  headers:    headers,
  extract_id: ->(payload, headers) { headers["x-bml-transaction-id"] }
)
```

The callable gets the parsed payload and the normalized headers — headers included precisely so an
identifier that arrives outside the body does not block you. Return `nil` for "not found" and you get
the same loud `ValidationError` as an exhausted list, with no remote call. When you supply an
extractor the built-in list is not consulted at all.

Headers are normalized for you (`downcase`, `_`→`-`, leading `http-` stripped), so `request.env`,
`request.headers`, and a plain hash all work.

## What is still yours

```ruby
# at-least-once and possibly out of order — the library deduplicates nothing
return if Delivery.exists?(transaction_id: result.transaction_id, status: result.status)
```

The gem owns no datastore (FR-014). Replay and ordering protection are yours; `transaction_id` is
surfaced so you can build them. Handling the same delivery twice produces equivalent results and no
side effect beyond the retrieve.

If a notification never arrives at all, reconcile directly — no webhook needed:

```ruby
BML.client.transactions.retrieve(transaction_id).state
```

## Running the tests

```bash
bundle exec rspec spec/unit spec/contract           # deterministic; no network, no sleeping
bundle exec rspec spec/unit/webhooks_recheck_spec.rb
bundle exec rubocop
```

No test sleeps for real: the wait is injected so the 3-second default is asserted without spending it
(research R8).

## Verifying against UAT

This feature needs something no previous feature here did: **inbound** reachability from BML UAT. A
tunnel in front of a local sink is enough.

```bash
# 1. a sink that logs the raw delivery verbatim
ruby -rwebrick -e 'WEBrick::HTTPServer.new(Port: 4567).tap { |s|
  s.mount_proc("/") { |req, res| warn req.request_line, req.raw_header.join, req.body; res.body = "ok" }
  trap("INT") { s.shutdown }; s.start }'

# 2. expose it
cloudflared tunnel --url http://localhost:4567
```

Then register the URL (merchant portal, or `webhook:` on `transactions.create_v2`), drive a UAT
transaction to a status change, and capture what arrives.

```bash
BML_RUN_UAT=1 bundle exec rspec spec/integration/webhooks_uat_spec.rb
```

### Closing the release gate

Record the captured delivery verbatim in `contracts/bml-remote.md`, then resolve:

| Item | What to answer |
|---|---|
| **#1 identifier field** ⚠️ | Which key holds the transaction id. Correct the candidate list. **Release gate.** |
| #2 claimed-status field | Whether a status is present at all, and under which key. |
| #3 body format | JSON or form-encoded. Both are implemented; only one is real. |
| #4 read-path lag | Does an immediate retrieve already agree? If it always does, the 3-second default is pure cost and should be reconsidered. |
| #5 delivery metadata | Any delivery id or attempt counter — an attempt counter would help callers dedupe. |

Add the captured body as a fixture and replay it in a unit test, so the observation is enforced by the
suite rather than remembered in prose.
