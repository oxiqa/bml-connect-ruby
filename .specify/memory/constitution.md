<!--
Sync Impact Report
==================
Version change: 1.0.0 → 2.0.0
Rationale: MAJOR. The constitution was ratified for the `bml_tokenization` project, whose
remote contract was assumed rather than observed. It is re-adopted here for
`bml-connect-ruby` and Principle III is redefined: contracts are now derived from the
published `reference/Connect-API.json` OpenAPI document and MUST be verified against a live
environment, not from stubbed tests alone. That redefinition is backward-incompatible with
the previous "contract tests verify conformance" wording, which stubs satisfied.

Modified principles:
  - III. Contract-Driven Integration → redefined (published-spec authority + live verification)
  - II. Test-First → amended (adds the anti-stub-only gate)
Added principles: (none)
Added sections:
  - Source of Truth (new, under Security & Compliance Requirements)
Removed sections: (none)

Templates & artifacts requiring review:
  - .specify/templates/plan-template.md — Constitution Check gates map to Principles I–V
  - .specify/templates/spec-template.md — security/compliance requirements captured
  - .specify/templates/tasks-template.md — test-first task ordering enforced

Deferred items / follow-up TODOs: (none)
-->

# BML Connect Ruby Constitution

## Core Principles

### I. Security & Cardholder Data Protection (NON-NEGOTIABLE)

Protecting cardholder data is the primary reason this library exists; every design and code
decision MUST default to the most protective option.

- Sensitive Authentication Data (full track data, CVV/CVV2, PIN/PIN blocks) MUST NEVER be
  persisted after authorization, in any store, log, cache, or backup.
- The Primary Account Number (PAN) MUST NOT be stored in plaintext. A stored card MUST be
  represented only by its BML-issued `token` plus the masked `paddedCardNumber` summary.
- Tokens MUST NOT be reversible without access to BML's protected vault. This library MUST
  expose no detokenization operation.
- Secrets (API key, App ID) MUST be injected from the environment or a secrets manager and
  MUST NEVER be committed to source control.
- All data in transit MUST use TLS.

Rationale: This library handles Bank of Maldives payment credentials. A single leak of PAN or
authentication data is a regulatory and reputational failure that no other quality can offset.

### II. Test-First (NON-NEGOTIABLE)

Tests define behavior before implementation exists.

- Every change to production behavior MUST begin with a failing test that expresses the
  intended behavior; implementation follows to make it pass (Red-Green-Refactor).
- Tokenization and charge boundaries MUST have tests covering success, failure, and rejection
  paths, including malformed and out-of-range inputs.
- A change MUST NOT be merged if it reduces coverage of security-critical paths.
- **A stubbed test alone MUST NOT be treated as evidence that a remote endpoint exists.** Every
  request path, HTTP method, and authentication header a resource sends MUST be traceable to
  `reference/Connect-API.json`, and any stub URL MUST be derived from the client's configured
  base URL rather than hardcoded.

Rationale: Payment logic is unforgiving; test-first prevents regressions in exactly the code
paths where silent failure is most costly. The added gate exists because a full green suite of
WebMock stubs previously certified an API surface that did not exist.

### III. Contract-Driven Integration

Boundaries with the BML Connect API are defined by BML's published contract, not by ours.

- `reference/Connect-API.json` (OpenAPI 3.1, "Connect API" v2.0) is the **single source of
  truth** for paths, HTTP methods, field names, required/optional status, and the
  authentication scheme. Where this library and that document disagree, the document wins.
- A resource MUST NOT be declared complete until it has been exercised against the UAT
  environment with real credentials and the observed responses recorded in the feature's
  `contracts/bml-remote.md`.
- Any field, path, or behavior NOT present in the published spec MUST be marked
  `[UNVERIFIED]` in the contract document until confirmed with BML, and MUST NOT be relied on
  by default behavior.
- Sandbox and production configurations MUST be selectable without code changes.

Rationale: A payment client is only useful when its callers can rely on it reaching a real
endpoint. Deriving the contract from an assumed shape produced a library that never spoke to
BML at all.

### IV. Observability & Auditability

The library MUST be diagnosable in production and MUST retain an immutable record of
security-relevant actions.

- Logging MUST be structured (machine-parseable) and MUST NEVER contain PAN, CVV, PIN, full
  track data, or secrets; sensitive fields MUST be masked or omitted.
- Every operation that creates, charges against, or deletes a stored token MUST produce an
  audit record capturing who, what, when, and outcome — sufficient to reconstruct access
  without exposing the protected data itself.
- Errors MUST be surfaced with actionable context; silent failure of a security control is a
  defect.

Rationale: Debuggability and audit are inseparable here — the same events operators need to
troubleshoot are the events compliance requires us to prove.

### V. Simplicity & Explicitness

Prefer the simplest design that satisfies the requirement and the security principles above.

- Apply YAGNI: build for current, specified requirements, not speculative ones.
- Additional abstraction, indirection, or dependency MUST be justified by a concrete need;
  unjustified complexity MUST be removed in review.
- Behavior MUST be explicit over implicit — no hidden fallbacks that weaken a security control.
- The library MUST NOT invent conveniences the platform does not offer. If BML requires two
  calls, this library MUST NOT present one that silently performs both.

Rationale: Complexity is where security bugs hide; a smaller, clearer surface is easier to
review, test, and defend. The final clause exists because a prior design collapsed BML's
two-step create-then-charge flow into a single fictional call.

## Security & Compliance Requirements

- The library operates on Bank of Maldives payment credentials and MUST be designed to align
  with PCI DSS expectations for handling and transmitting cardholder data.
- The cardholder-data environment MUST be minimized: this library never receives raw PAN or
  CVV. Card capture happens on BML's hosted payment page.
- Dependencies MUST be tracked, and known-vulnerable dependencies MUST be remediated before
  release.
- BML Connect credentials (API key, App ID) and their mode (`production` / `sandbox`) MUST be
  configuration-driven and MUST NOT be hardcoded.

### Source of Truth

- `reference/Connect-API.json` is vendored into this repository deliberately, so that every
  spec, contract, and test can cite an exact, versioned document rather than a rendered docs
  site. BML's documentation portal is a client-rendered application whose content cannot be
  fetched or diffed; the vendored JSON is the reviewable artifact.
- When BML publishes a new revision, replacing that file is a reviewable change on its own,
  and every affected `contracts/bml-remote.md` MUST be re-checked against it.

## Development Workflow & Quality Gates

- Every pull request MUST pass automated tests and MUST demonstrate compliance with Principles
  I–V; reviewers MUST explicitly verify the security and test-first principles.
- Changes touching tokenization, charge, or credential-handling code MUST receive review from
  at least one reviewer other than the author.
- Secrets scanning MUST run against changes; a detected secret blocks merge until remediated.
- A change that cannot be verified by an automated or documented test MUST NOT be merged until
  such verification exists or the gap is explicitly justified and recorded.
- **Spec-conformance gate**: a PR adding or changing a remote call MUST cite the
  `reference/Connect-API.json` path it implements. A call with no citation MUST NOT merge.

## Governance

This constitution supersedes other development practices for this project. Where a practice
conflicts with a principle here, the principle wins.

- Amendments MUST be proposed as a change to this document, MUST state the rationale, and MUST
  update the version and dates below.
- Versioning follows semantic versioning: MAJOR for backward-incompatible governance or
  principle removals/redefinitions, MINOR for a newly added or materially expanded principle
  or section, PATCH for clarifications and non-semantic refinements.
- All PRs and reviews MUST verify compliance with this constitution; unjustified complexity or
  weakened security controls MUST be rejected.
- Runtime development guidance for agents and contributors is maintained alongside the Spec Kit
  templates in `.specify/`; those templates MUST stay consistent with the principles above.

**Version**: 2.0.0 | **Ratified**: 2026-08-17 | **Last Amended**: 2026-09-07
