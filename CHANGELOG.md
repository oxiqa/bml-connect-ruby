## [Unreleased]

### Added
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
- Feature `001-customers-endpoints` is now **implemented**; `002`–`004` remain specified, not
  implemented. `BMLConnect::Client` gains a memoized `#customers` plus `#logger`/`#timeout`/
  `#max_retries`/`#retry_backoff` accessors with safe defaults; every existing method —
  `BMLConnect::Transactions` included — keeps its 0.2.0 behavior and signature. The change is
  purely additive.
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
