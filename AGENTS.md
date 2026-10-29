# Agent instructions — bml-connect-ruby

This repository is one project in the Msgowl ecosystem. Its documentation is not kept
here; it lives in the shared `agent-docs/` tree beside this repository in the workspace:

```
msgowl/                       workspace root, not a repository
├── agent-docs/
│   ├── README.md             index of every project
│   ├── guides/               rules that bind every repository
│   ├── _templates/
│   └── bml-connect-ruby/     ← this project's documentation
└── bml-connect-ruby/         ← this repository
```

## Before you change anything

1. Read
   [`../agent-docs/guides/code-conventions.md`](../agent-docs/guides/code-conventions.md).
   It binds this repository.
2. Read [`../agent-docs/bml-connect-ruby/README.md`](../agent-docs/bml-connect-ruby/README.md).

## Where things go

This repository is under spec-driven development with Spec Kit; see
[`../agent-docs/guides/spec-driven-development.md`](../agent-docs/guides/spec-driven-development.md).

- Spec Kit working artifacts, one folder per feature branch: `specs/<n>-<name>/` in this
  repository. This is the one kind of documentation that does live here.

- What this project is, how to run it, its interfaces, operational notes:
  `../agent-docs/bml-connect-ruby/README.md`. Most of these are still stubs, so when you work
  something out, write it down there.
- Notes on external APIs and decisions: `../agent-docs/bml-connect-ruby/research/`.
- Do not put project documentation in a `docs/` or `agent-docs/` folder inside this
  repository.

## If `../agent-docs` is missing

This checkout is not inside the workspace layout described in
`agent-docs/guides/workspace-layout.md`. Say so and ask where the `agent-docs/` tree is. Do
not recreate it here.

## Version control

Do not commit, push, or create or switch branches unless you were asked to in this session.
