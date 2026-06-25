# CLAUDE.md

Guidance for working in this repository.

## This repository is PUBLIC

`FIZ-co/fiz-invoicing-skill` is a **public** repo. Anything committed or posted
here — code, commit messages, PR titles/bodies, issue and review comments — is
world-readable. Treat every artifact as published.

The skill is developed against the **private** `FIZ-co/public-api` repo (the
NestJS gateway behind `https://api.fiz.co`). **Never leak private context into
this repo's public surface.** Concretely, keep the following OUT of commit
messages, PR descriptions, and comments:

- Links to or numbers of `public-api` (or any private repo) issues/PRs
  (e.g. "PR #33", "backend-core#2228").
- Local filesystem paths (`/Users/...`, `/fiz/public-api`, ...).
- Names of private implementation details: internal file names, DTO/class names
  (`UpdateInvoiceDto`), decorator/validator names (`@IsPaymentAllowedForType`),
  GraphQL operation names, "the validator is dropped on update", etc.
- Mentions of internal process that imply private-repo access (e.g. "verified
  against the public-api e2e specs / source").

**Instead, describe the observable API contract**, framed for an external reader:
endpoints, request/response fields, enum values, and HTTP status codes
(e.g. "a well-formed but unknown `seriesId` → 404, a malformed one → 400"). The
public source of truth is the live Swagger UI at `https://api.fiz.co/` — cite that,
not internal code.

It is fine to *use* the private `public-api` source while working locally to get
the behaviour right; just don't reproduce it in public artifacts.

## What this repo is

A **skill** that teaches an AI agent to issue Portuguese invoices through the FIZ
Public API. It is documentation + a small bash helper, not application code:

- `fiz-invoicing/SKILL.md` — the agent-facing playbook (workflow, safety rules).
- `fiz-invoicing/reference.md` — field-by-field API reference.
- `fiz-invoicing/domain.md` — Portuguese tax domain (VAT, exemption codes, etc.).
- `fiz-invoicing/scripts/fiz.sh` — curl helper that checks HTTP status.

Because the skill drives **legally binding fiscal documents**, factual accuracy
against the real API contract matters. When you change the docs, verify claims
(status codes, field names, restrictions) against the actual API behaviour before
shipping — but, per the rule above, don't cite the private implementation when you
describe them publicly.
