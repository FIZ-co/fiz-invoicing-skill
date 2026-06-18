---
name: fiz-invoicing
description: >-
  Issue invoices through the FIZ Public API (https://api.fiz.co). Use when the
  user wants to create or issue an invoice, bill a customer, create a customer
  or product/service item, register a payment, or download an invoice PDF in
  FIZ. Triggers include "issue an invoice", "bill <customer>", "create an
  invoice for ...", "send a fatura", "add a customer/item in FIZ", "get the
  invoice PDF".
allowed-tools: Bash
---

# FIZ Invoicing

Issue invoices with the FIZ Public API — a REST gateway at `https://api.fiz.co`.
This skill walks through the full lifecycle: find or create the customer, find
or create the items, build a **draft** invoice, **issue** it (this is the legally
binding step), and optionally download the PDF.

## Setup

Every request needs the client's API key in the `x-api-key` header. Get a key at
**https://app.fiz.co/settings/integrations**.

Store it in an environment variable so it never gets hardcoded into commands:

```bash
export FIZ_API_KEY="fiz_api_..."     # the user's key from app.fiz.co
export FIZ_API_URL="https://api.fiz.co"   # optional; this is the default
```

All examples below use `$FIZ_API_KEY` and `$FIZ_API_URL`. If `FIZ_API_URL` is
unset, use `https://api.fiz.co`. If `FIZ_API_KEY` is unset, **stop and tell the
user to set it in their environment** (`export FIZ_API_KEY=…` in their shell, or a
secret manager) — **do not ask them to paste the key into the chat**, and never
print or echo the key value. An API key is a credential; keep it out of the
conversation transcript.

A reusable curl helper is provided in `scripts/fiz.sh`. Commands run from the
session's working directory (your project root), **not** the skill directory, so
source the helper by its absolute path via `${CLAUDE_SKILL_DIR}` (Claude Code sets
this to the skill's own directory):

```bash
source "${CLAUDE_SKILL_DIR}/scripts/fiz.sh"   # resolves from any working directory
fiz GET /invoices
```

On a runtime that doesn't provide `CLAUDE_SKILL_DIR`, substitute that runtime's
equivalent skill-directory path (a bare relative `scripts/fiz.sh` will not resolve
from the project root).

The helper prints the HTTP status and **returns non-zero on 4xx/5xx**, so an error
response is never mistaken for success — see "Error handling" below. Plain `curl`
examples are shown inline too; if you use raw `curl`, always check the HTTP status,
not just whether the command exited 0.

## The mental model

- An invoice references a **customer** (by id) and one or more **items** (by id).
  So customers and items must exist *before* you can build the invoice.
- `POST /invoices` creates a **draft**. A draft is not yet a legal document — it
  is not sent to the tax authority and can be edited or deleted freely.
- `POST /invoices/:id/issue` **issues** it — assigns the official number and
  ATCUD, syncs with the Portuguese tax authority (AT), and makes it final.
  **Issuing is not reversible; confirm with the user before issuing.** An issued
  invoice cannot be deleted — the only way to undo it is a credit note.
- The only exception to "create then issue": if you pass a `payment` object on
  creation for the types `INVOICE_RECEIPT` or `SIMPLIFIED_INVOICE`, the document
  records the payment — but you still issue it to finalize.

## Confirmation before writes

These endpoints change state on the user's account. Two levels of care:

- **Plan, then preview all writes before the first one.** Once you know what the
  request needs, list *every* write you intend to make for this task — each
  endpoint plus its JSON payload (the customer to create, each item, the draft
  invoice) — and show that batch to the user in one preview. Proceed through the
  writes once they approve the plan. If the plan changes mid-run (e.g. an item
  lookup fails and you now need to create one), preview the new write before
  sending it. Never invent customer data, tax fields, or amounts — use only what
  the user gave you.
- **Before `POST /invoices/:id/issue`** — this is irreversible and reported to the
  tax authority. **Always get an explicit, separate confirmation** (beyond the plan
  approval above), showing the draft's customer, line items, VAT, and total. Do not
  issue on your own initiative.

**Invocation policy (deliberate):** this skill keeps model auto-invocation
*enabled* — the `description` is the discovery surface, and the real safety net is
the preview-all-writes + separate issue confirmation above, not gating discovery.
The Codex manifest (`agents/openai.yaml`) is set to match
(`allow_implicit_invocation: true`). An operator who wants manual-only use can set
`disable-model-invocation: true` in the frontmatter (loads only on `/fiz-invoicing`).

## This is Portuguese tax invoicing — why correctness matters

FIZ issues **legally binding fiscal documents** that are reported to the
Portuguese tax authority (Autoridade Tributária, "AT"). A wrong VAT rate or a
missing exemption reason is not a cosmetic bug — it produces an incorrect tax
document that, once issued, can only be corrected with a credit note. Get the
tax fields right *before* issuing.

The two things most likely to be wrong, and that you must reason about:

**1. VAT rate (`vatRate` on each item) — never guess it.** The rate band
(`NORMAL` | `INTERMEDIATE` | `REDUCED` | `EXEMPT`) and the percentage it maps to
depend on the territory (Continental / Açores / Madeira). **Default to `NORMAL`**
— `REDUCED`/`INTERMEDIATE` apply only to specific legally-defined categories
(certain foods, restaurants, cultural events…). If the user hasn't named such a
category, use `NORMAL` and say so, or ask; never silently apply a reduced rate.
The per-territory percentage table is in `domain.md`.

**2. VAT exemption requires a reason code (`vatExemptionReason`).**
If `vatRate` is `EXEMPT`, Portuguese law requires a *motivo de isenção* — an
`M`-code stating the legal basis. Always set one; an exempt item without a valid
reason is an invalid document and can be rejected when you issue. The code must
reflect the *actual* reason: small-business regime → `M10`, activity exempt by
nature (health/education) → `M07`, EU B2B / reverse charge → `M40`/`M16`/`M19`.
If the user is exempt but doesn't know the code, ask *why* and map it — don't pick
arbitrarily. The full code list with legal references is in `domain.md`.

**Other domain rules worth knowing** (details in `domain.md`):
- **CAE** is a 5-digit Portuguese economic-activity code that must be one the
  business has registered. Don't invent it — ask the user, or reuse the CAE from
  a previous invoice. It must be a current (Rev. 4) code.
- **NIF** (`taxpayerNumber`) is a 9-digit Portuguese tax number with a checksum;
  required for B2B, optional for final consumers. For EU B2B, the customer's
  VAT number matters for reverse-charge treatment.
- **Withholding tax** (retenção na fonte: IRS/IRC/IS) is configured on the item;
  common rate is 25% for self-employed services. It is *withheld by the payer*,
  reducing the amount actually paid.
- **Document type** affects rules: a `SIMPLIFIED_INVOICE` is for small retail
  sales and may omit full customer data; an `INVOICE` to a business for over
  €1,000 needs the customer NIF.

## Workflow

Follow these steps. Skip 1–2 if the user already gives you a customer id and item
ids.

### Step 1 — Resolve the customer

Search first to avoid duplicates, then create if needed.

Examples use the `fiz` helper (see Setup) — it checks the HTTP status for you. The
equivalent raw `curl` is in the appendix.

Find by search term (name, tax number, email):
```bash
fiz GET "/customers?search=Joao"
```

Create a customer (only `name` is required):
```bash
fiz POST /customers '{
  "name": "João Silva",
  "email": "joao.silva@example.com",
  "taxpayerNumber": "303741791",
  "country": "PT"
}'
```
Keep the returned `id` — that is the `customerId` for the invoice.

### Step 2 — Resolve the items (products / services)

Find existing items:
```bash
fiz GET "/items?search=consulting"
```

> **Reuse an existing item only if its tax fields match the sale.** A search hit
> with the right *name* is not enough — for a fiscal document the item's `vatRate`,
> `vatTerritory`, `vatExemptionReason`, `taxRate` and withholding fields must match
> the treatment you intend for *this* customer and sale. If any of them differs
> (e.g. same service but the customer is exempt, in another territory, or subject
> to withholding), **create a new item** with the correct fields rather than
> reusing the mismatched one. When unsure, inspect the found item's fields and
> confirm with the user.

Create an item. Required: `name`, `type` (`PRODUCT` | `SERVICE`), `unitPrice`,
`vatRate` (`NORMAL` | `INTERMEDIATE` | `REDUCED` | `EXEMPT`):
```bash
fiz POST /items '{
  "name": "Consulting hour",
  "type": "SERVICE",
  "unitPrice": 80,
  "vatRate": "NORMAL"
}'
```
Keep each returned `id` — those are the item ids for the invoice.

> `unitPrice` is the unit price; per-line totals are computed by FIZ from the
> `quantity` you give in the invoice. **Choose `vatRate` deliberately** — see the
> domain section above; default to `NORMAL` unless the category clearly warrants a
> reduced rate. If `vatRate` is `EXEMPT`, always set a `vatExemptionReason` M-code
> that matches *why* the sale is exempt (e.g. `M10` for the small-business regime).
> The field is technically optional at item creation, but an exempt item without a
> valid reason is incorrect and can be rejected later when you issue the invoice.
> See `domain.md` for the full code list.

### Step 3 — Create the draft invoice

Required fields: `dueDate` (ISO 8601), `cae` (Portuguese economic activity
code), `type`, `customerId`, and `items` (at least one `{ id, quantity }`).

```bash
fiz POST /invoices '{
  "dueDate": "2026-07-18T00:00:00.000Z",
  "cae": "62010",
  "type": "INVOICE",
  "customerId": "6863b1513117c5892ff55296",
  "items": [
    { "id": "68483e978073231c3947077c", "quantity": 10 }
  ]
}'
```

The response includes the new invoice `id` (needed to issue) and `status`
(`DRAFT`). The invoice `date` is set to now and `currency` is `EUR` by the API —
you do not send them.

**Optional — global discount** (`summary`):
```json
"summary": { "globalDiscountType": "PERCENT", "globalDiscountPercent": 10 }
```
Use `"AMOUNT"` with `globalDiscountAmount` for a fixed-value discount instead.

**Optional — payment on creation** (`payment`): only allowed when `type` is
`INVOICE_RECEIPT` or `SIMPLIFIED_INVOICE`; the API returns 400 otherwise.
```json
"payment": { "method": "mbWay", "date": "2026-07-18T00:00:00.000Z" }
```
`method` is one of: `cash`, `card`, `bankTransfer`, `mbWay`, `multibanco`,
`spin`, `other`.

### Step 4 — Issue the invoice

This is the binding step. **Confirm with the user**, then:
```bash
fiz POST /invoices/{id}/issue
```
The response has the official `number`, `status: ISSUED`, and a `syncWithAt`
block. **Check `syncWithAt.status`** — if it is `FAILED`, the invoice was created
locally but did not sync with the tax authority; report `atMessage` and whether
`isRetriable` is true to the user instead of claiming success.

### Step 5 — Download the PDF (optional)

```bash
fiz GET /invoices/{id}/pdf
```
Returns `{ id, name, url }`; the `url` is a downloadable link to the PDF.
Add `?format=A4` or `?format=RECEIPT` to choose the layout.

## Document types (`type`)

Values: `INVOICE` · `INVOICE_RECEIPT` · `SIMPLIFIED_INVOICE` · `RECEIPT` ·
`CREDIT_NOTE` · `DEBIT_NOTE`. **Default to `INVOICE`** unless the user asks for a
receipt or simplified invoice. Only `INVOICE_RECEIPT` and `SIMPLIFIED_INVOICE`
accept a `payment` object on creation. See `domain.md` for what each type means
and when to use it.

## Common operations reference

| Action            | Method & path              |
|-------------------|----------------------------|
| List/search customers | `GET /customers?search=…` |
| Create customer   | `POST /customers`          |
| List/search items | `GET /items?search=…`      |
| Create item       | `POST /items`              |
| Create draft      | `POST /invoices`           |
| Issue             | `POST /invoices/:id/issue` |
| List invoices     | `GET /invoices`            |
| Get one invoice   | `GET /invoices/:id`        |
| Download PDF      | `GET /invoices/:id/pdf`    |
| Delete (draft)    | `DELETE /invoices/:id`     |

## Error handling

**Always check the HTTP status, not just that the command ran.** On error the API
returns a normal-looking JSON body — `{ "statusCode": 400, "message": "...",
"timestamp": "..." }` — with the matching HTTP status. With raw `curl -s` that
body prints and `curl` still exits 0, so it is easy to mistake an error for a
result. The `fiz` helper guards against this: it prints an `HTTP <code>` line and
returns non-zero on 4xx/5xx. If you must use raw curl, add `-w '\n%{http_code}'`
(or `-o body -w '%{http_code}'`) and inspect the code.

Common statuses:
- **401** — missing/invalid API key. Tell the user to set `FIZ_API_KEY` in their
  environment (not in chat).
- **400** — validation error; the `message` says which field. Common cases:
  empty `items`, `payment` on an unsupported `type`, an unknown/extra field
  (strict whitelist), malformed `dueDate` (must be full ISO 8601 with timezone,
  e.g. `2026-07-18T00:00:00.000Z`).
- **5xx** — backend/AT problem; surface it, don't retry the same write blindly
  (a create may have partially succeeded — check with a `GET` first).

Always echo the API's `message` back to the user rather than retrying blindly.

The full, authoritative request/response contract is the live Swagger UI at
**https://api.fiz.co/** — consult it if a field here looks out of date.

## When you need more detail

Two companion files in this skill directory:
- **`domain.md`** — the Portuguese tax domain: VAT rates per territory, the full
  list of exemption (`M`) codes and when each applies, document types, CAE/NIF
  rules, withholding tax, and how AT sync / issuing irreversibility work. Read it
  whenever a tax decision is non-obvious (especially choosing a `vatRate` or an
  exemption reason).
- **`reference.md`** — the complete field-by-field API reference (every
  customer/item/invoice field, all enum values, full request/response shapes).

## Appendix — raw curl (without the helper)

Prefer the `fiz` helper above; it checks the HTTP status. If it isn't available,
use raw `curl` **with `-w '\n%{http_code}'`** and inspect the trailing status line
— do **not** use a bare `curl -s`, which hides the status and makes an error body
look like success. The pattern is the same for every call (add `-X POST` and a
`-d '{…}'` body for writes):

```bash
curl -sS -w '\n%{http_code}' \
  "$FIZ_API_URL/customers?search=Joao" \
  -H "x-api-key: $FIZ_API_KEY"
```

The last printed line is the HTTP status: treat `2xx` as success, anything else as
failure (the JSON above it holds the error `message`).
