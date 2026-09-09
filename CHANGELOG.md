## [Unreleased]

### Added
- **Transactions v2 surface**, implementing feature `003-transactions-v2` on the shared `Resource`
  transport — **additive**, no released method changed. New value-object methods `create_v2`,
  `retrieve`, `update`, `capture` and `cancel` target the documented `/public/v2/transactions` and
  `/public/transactions/{id}` endpoints, return whitelisted `BMLConnect::Models::TransactionRecord`
  objects, and raise the shared typed error hierarchy. Highlights:
  - `create_v2` supports variant 3 (existing `customerId`) and variant 4 (inline `customer`);
    variants 1/2 (shop orders) and 5 (foreign exchange) are rejected locally by name.
  - `tokenizationDetails` (`BMLConnect::Models::TokenizationDetails`) instructs BML to store a card;
    `tokenize`/`paymentType` are required, and `recurringFrequency`/future `expiryDate` are required
    when `paymentType` is `RECURRING` — all validated before any remote call.
  - `amount` (on both `create_v2` and `capture`) must be a **positive Integer in minor units**; a
    Float, String, zero, or negative is rejected by name and never coerced.
  - **No auto-retry on create or capture** (no documented idempotency key); a timeout raises
    `AvailabilityError` after exactly one attempt. Retrieve/list/update/cancel retry with backoff.
  - `create_v2`/`update`/`capture`/`cancel` emit masked audit records; the hosted payment URL is
    treated as a completion secret — omitted from `#to_h`/`#inspect` and never logged or audited.
    `TransactionRecord#payment_url` raises `UnverifiedFieldError` (new) rather than returning `nil`
    when no URL field is present, pending UAT confirmation of which v2 field carries it.
  - `state` is passed through verbatim (never normalized); v2 requests send **no** `signature`
    until UAT settles whether v2 accepts one.
- **Deprecated** the legacy v1 `transactions.create` (undocumented-but-live `POST
  /public/transactions`). It still works unchanged and returns a `Faraday::Response`, but now logs a
  single, once-per-process deprecation warning pointing at `create_v2`.
- Fixed a latent Ruby 2.7 bug in `BMLConnect::Models::Transaction`: a missing-fields `create`
  raised `NoMethodError` (`Set#join`, Ruby 3.0+) instead of the intended `ArgumentError` on the 2.7
  runtime `msgowl/website` uses. Bug fix only — makes the code do what its own test already asserts.
- **Stored card tokens resource** (`client.tokens`), implementing feature `002-stored-card-tokens`
  against BML's `/public-customers/{customerId}/tokens` contract: `list`, `retrieve`, and `delete`
  (soft delete, `204`). Read-and-delete **only** — BML publishes no token-creation endpoint, so the
  resource deliberately exposes no `create`/`tokenize`/`detokenize` method and a test enforces the
  absence (SC-006). Returns whitelisted `BMLConnect::Models::Token` / `TokenList` value objects
  (mirroring BML's field names — no `last_four`/`scheme` alias) and raises the shared typed error
  hierarchy. Only `delete` is audited, once, even across retries; the optional `actor:` is screened
  for card data.
- Extended the shared transport to retry `429` responses (in addition to `408`/timeouts/`5xx`) with
  bounded backoff on every resource (FR-013a); a surviving `429` still surfaces as `RateLimitError`
  carrying `Retry-After`. Retry knobs are `max_retries` / `retry_backoff` on the client
  (`max_retries: 0` disables).
- **Customers resource** (`client.customers`), implementing feature `001-customers-endpoints`
  against BML's `/public-customers` contract: `create`, `retrieve`, `list`, partial `update`
  (`PATCH`), and `archive` (soft delete). Returns whitelisted `BMLConnect::Models::Customer` /
  `CustomerList` value objects and raises a typed error hierarchy
  (`ValidationError`/`NotFoundError`/`AuthenticationError`/`ConflictError`/`RateLimitError`/`AvailabilityError`)
  instead of the raw `Faraday::Response` that `transactions` returns.
- Shared infrastructure consumed by later features `002`/`004`: `BMLConnect::Errors`,
  `Masking` (Luhn-gated PAN detection + log scrubbing), `Audit` (masked structured audit line via
  the client's logger — no separate sink), and a `Resource` transport base (URL derived from the
  client's base URL, status→error mapping, bounded retry with backoff, `Retry-After` on 429).
- Local safeguards: required-field and lightweight email-shape validation, and PAN/CVV screening
  of **every** caller-supplied string (and the optional `actor`) before any remote call.
- Test tiers: unit, contract (WebMock, stub URLs derived from `client.base_url`), an
  OpenAPI-conformance test that reads `reference/Connect-API.json` (Constitution II anti-stub
  gate), and an opt-in, credential-gated UAT suite that loads a repo-local `.env` (git-ignored;
  see `.env.example`). Added `webmock` and `dotenv` development dependencies and a `.gitleaks.toml`
  secret-scanning config.
- Vendored BML's published OpenAPI contract at `reference/Connect-API.json` (Connect API v2.0),
  with `reference/README.md` describing the endpoint inventory, what is out of scope, and the two
  things this gem does that the document does not describe.
- Spec Kit machinery (`.specify/`, `speckit-feature`) and four feature specifications covering
  the tokenization surface, each with plan, research, data model, tasks, and both an HTTP and a
  Ruby contract:
  - `specs/001-customers-endpoints` — `/public-customers` CRUD + archive
  - `specs/002-stored-card-tokens` — `/public-customers/{customerId}/tokens` list, retrieve, delete
  - `specs/003-transactions-v2` — `/public/v2/transactions`, `tokenizationDetails`, update, capture, cancel
  - `specs/004-token-charge` — `/public-customers/charge`
- `MIGRATION.md` recording the move of tokenization work into this gem from `bml_tokenization`,
  including the endpoint, authentication, data-model and flow corrections that prompted it.

### Changed
- Project constitution amended to **2.0.0** (`.specify/memory/constitution.md`). Principle III
  now requires contracts to derive from `reference/Connect-API.json` and be verified against a
  live environment. Principle II gains an explicit gate that a stubbed test is not evidence an
  endpoint exists. Principle V gains a rule against presenting one call where the platform
  requires two.
- `README.md` gains a roadmap, an explanation of how BML tokenization actually works, and a
  backward-compatibility statement.

### Notes
- Features `001-customers-endpoints`, `002-stored-card-tokens` and `003-transactions-v2` are now
  **implemented**; `004-token-charge` remains specified, not implemented. `BMLConnect::Client`
  gains memoized `#customers`/`#tokens` plus `#logger`/`#timeout`/`#max_retries`/`#retry_backoff`
  accessors with safe defaults. Feature `003` is additive to the released transactions surface:
  `create`, `get` and `list` keep their 0.2.0 behavior, signature, and `Faraday::Response` return
  type; the v2 value-object methods sit alongside them.
- Feature `003` is **not production-ready** until UAT confirms which v2 response field carries the
  hosted payment URL (`create_v2` may be called but its `payment_url` will raise until then), and
  until the `msgowl/website` suite is verified to pass unchanged against this gem (release gate).
- `specs/004-token-charge` is **release-blocked**: it is unconfirmed whether BML's `tokenId`
  field expects a token's `id` or its `token` value. Charging the wrong identifier is a
  money-movement defect.
- No feature has yet been observed against BML UAT. The available API key is rejected there with
  `PP-C-004` even on the known-working legacy transactions path, so every feature's verification
  table is open pending a newly issued UAT credential.

## [0.2.0] - 2021-09-17

### Changes
- Downgraded ruby to >=2.3

## [0.1.0] - 2021-09-16

- Initial release
