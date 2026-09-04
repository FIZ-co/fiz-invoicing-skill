---
name: fiz-invoicing
description: >-
  Issue Portuguese fiscal documents through the FIZ Public API
  (https://api.fiz.co). Use when the user wants to create or issue an invoice,
  bill a customer, create a customer or product/service item, register a payment
  on an issued invoice, issue a credit note, work out the correct VAT rate for a
  sale, create a transport document (guia de transporte), look up bank
  transactions, or download a document PDF in FIZ. Triggers include "issue an
  invoice", "bill <customer>", "create an invoice for ...", "send a fatura",
  "add a customer/item in FIZ", "mark invoice X as paid", "credit note",
  "what VAT should I charge", "guia de transporte", "get the invoice PDF".
allowed-tools: Bash
---

# FIZ Invoicing

Issue Portuguese fiscal documents with the FIZ Public API — a REST gateway at
`https://api.fiz.co`. This skill walks through the full lifecycle: find or create
the customer, find or create the items, build a **draft** invoice, **issue** it
(this is the legally binding step), record a payment, and download the PDF. It
also covers credit notes, transport documents (guias de transporte), the VAT
calculator, and reading bank transactions.

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

> **If FIZ's MCP tools are already available in this session** (the user connected
> the FIZ connector at `https://api.fiz.co/mcp`), prefer those tools over curl:
> they carry the user's OAuth grant and its scopes, so no API key is needed, and
> the fiscal ones run a built-in confirm step. This skill's tax guidance still
> applies — the VAT and exemption reasoning below is what you need either way.
> Use the curl path when no connector is present.

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
- Settling an *already issued* invoice is a different operation:
  `POST /invoices/:id/pay` (see step 6). It is the one write allowed on an issued
  document, and it can issue a receipt (recibo) of its own.
- Beyond invoices, the same API also issues **transport documents** (guias de
  transporte, `/transport-documents`) and exposes read-only **VAT advice**
  (`/vat/calculate`) and **bank transactions** (`/bank`). Those are covered in
  their own sections below.

**Every write endpoint accepts an `Idempotency-Key` header** — send one on any
write you might have to retry, so a timeout or a network error can't bill the
customer twice. See "Idempotency" below.

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
- **Before `POST /invoices/credit-notes` and `POST /invoices/:id/cancel`** — these
  also issue a fiscal change to the AT and are not casually undone. Confirm
  separately too: for a credit note show which invoice, the reason, and the amount
  being reversed; for a cancel show which invoice is being voided.
- **Before `POST /invoices/:id/pay`** — a payment normally issues a receipt
  (recibo), a fiscal document of its own, and there is no "unpay". Confirm the
  invoice, the method, and the amount (especially for a *partial* payment, where
  the amount you send decides how much debt remains).
- **Before `POST /transport-documents/:id/issue` and `.../cancel`** — a guia is
  reported to the AT exactly like an invoice. Same rule: separate confirmation.

The reads — `GET` anything, plus `POST /vat/calculate` and
`POST /vat/validate-client`, which create nothing despite being POSTs — need no
confirmation. Use them freely to gather facts before you propose a write.

**Invocation policy (deliberate):** this skill keeps model auto-invocation
*enabled* — the `description` is the discovery surface, and the real safety net is
the preview-all-writes rule plus the separate confirmation required before *each*
irreversible fiscal act above (issue, pay, credit note, cancel, guia
issue/cancel), not gating discovery.
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

**Let the API decide the hard VAT cases: `POST /vat/calculate`.** Rather than
reasoning your way through cross-border rules, ask the API. It creates nothing —
it is a pure calculation — so you can call it before proposing any write:

```bash
fiz POST /vat/calculate '{
  "clientHasVat": true,
  "clientCountry": "ES",
  "clientVatNumber": "B12345674",
  "itemType": "SERVICE"
}'
```

Response: `{ "vat": { "rate": 0, "reason": 40, "text": "…" }, "client": { … },
"warning": null }`. It resolves OSS, reverse charge, intra-EU exemption, and the
Portuguese territories (pass `clientTerritory` or a `clientPostalCode` and it
resolves the territory itself). Use it whenever the customer is **outside
continental Portugal or outside Portugal entirely** — that is exactly where
hand-reasoning goes wrong.

Two limits to respect:
- It returns **only the normal rate of the applicable regime, or 0% with an
  exemption reason**. It never returns the reduced or intermediate band — picking
  those by item category is still your job (default `NORMAL`, see above).
- The returned `reason` is a **number** (e.g. `40`), while the item field
  `vatExemptionReason` takes the **`M`-code string** (`"M40"`). Map it, and check
  the mapping against `domain.md` rather than blindly prefixing `M`.
- Requires the account's plan to include Auto IVA; without it the call returns
  **402**. Fall back to `domain.md` and ask the user in that case.

`POST /vat/validate-client` checks a customer's VAT number on its own. Note the
semantics before trusting it: for EU countries other than PT it is a real VIES
lookup, but **for PT and non-EU customers it only checks that a number is
present** — a `true` there does not mean the number exists. If VIES is down, it
echoes back the `clientHasVat` you sent.

**Other domain rules worth knowing** (details in `domain.md`):
- **CAE** is a 5-digit Portuguese economic-activity code that must be one the
  business has registered. Don't invent it — **list the account's registered codes
  with `GET /templates`** (each template carries a `cae` array), or reuse the CAE
  from a previous invoice, or ask the user. It must be a current (Rev. 4) code.
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

Steps 1–4 are the core path: resolve the customer, resolve the items, create the
draft, issue it. Skip 1–2 if the user already gives you a customer id and item
ids. Steps 5 (PDF) and 6 (record a payment) are optional and can happen later,
long after the invoice was issued.

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

**Optional — a standing discount on the item** (`unitDiscountType` with
`unitDiscountPercent` or `unitDiscountAmount`): a discount baked into the
catalogue entry, applied every time the item is invoiced. For a discount that
applies to *one* sale only, don't touch the item — put the discount on the
invoice line instead (step 3).

### Step 3 — Create the draft invoice

Required fields: `cae` (Portuguese economic activity code), `type`,
`customerId`, and `items` (at least one `{ id, quantity }`; the ceiling is 200
lines, far above any real invoice).

```bash
fiz POST /invoices '{
  "cae": "62010",
  "type": "INVOICE",
  "customerId": "6863b1513117c5892ff55296",
  "items": [
    { "id": "68483e978073231c3947077c", "quantity": 10 }
  ]
}'
```

The response includes the new invoice `id` (needed to issue) and `status`
(`DRAFT`); `number`, `atcud` and `shortHash` come back `null` — a draft has no
number until it is issued. `currency` is `EUR` by the API — you do not send it.

**Optional — the three dates.** All are ISO 8601 with a timezone, and all may be
omitted; each omission has a defined fallback, so send one only when the user
actually asked for it.

| Field | Meaning | Omitted → |
|---|---|---|
| `date` | Issue date. **Drives the tax period the document lands in.** | now |
| `dueDate` | Payment due date. | the issue date |
| `taxPointDate` | *Data da operação* — when goods were delivered or the service performed (art. 36.º n.º 5 al. f) CIVA). | the issue date |

```json
"date": "2026-08-31T00:00:00.000Z",
"dueDate": "2026-09-30T00:00:00.000Z",
"taxPointDate": "2026-08-28T00:00:00.000Z"
```

- **`date` back-dates the document into an earlier tax period.** That is a real
  fiscal decision, not a formatting detail — only set it when the user explicitly
  says which date to issue under, and echo it back in the confirmation.
- `dueDate` being optional is what makes a `INVOICE_RECEIPT` sensible: a document
  settled on issue has no meaningful due date.
- `taxPointDate` **cannot be later than the issue date**, and is ignored on credit
  and debit notes (they inherit the operation date of the document they correct).

**Optional — notes** (`notes`): free-text note shown on the invoice, e.g.
`"notes": "PO #118"`.

**Optional — series** (`seriesId`): issue this invoice into a specific numbering
series instead of the account default. Omit it and the account's default series is
used — most accounts only have one, so you rarely need this. When the user does run
multiple series (e.g. two brands on one NIF), list them with `GET /series` and pass
the chosen `id`:
```bash
fiz GET /series
```
Returns the active series, each with `id`, `name`, `isDefault`, `status`,
`managementMode`, and `entries[]` (per document type, with the ATCUD
`validationCode`). Pass the `id` as `seriesId` on create:
```json
"seriesId": "68483b3fa19e44171e3d0808"
```
It must be a valid series id from `GET /series` — there is **no silent fallback to
the default** if it's wrong. A malformed value (not a 24-char Mongo id) is rejected
with **400**; a well-formed but unknown/wrong-account id is rejected with **404**
("that series does not exist"), *not* 400.

**Optional — per-line discount.** Each entry in `items[]` can carry its own
discount, which **overrides any standing discount on the catalogue item** and is
applied *before* the global discount:
```json
"items": [
  { "id": "68483e978073231c3947077c", "quantity": 10,
    "discountType": "PERCENT", "discountPercent": 10 }
]
```
Use `"AMOUNT"` with `discountAmount` (a per-unit value) instead. `discountType`
and its value must agree — a `PERCENT` with a `discountAmount` is a **400**, and
so is a type with no value at all. `discountPercent` must be between 0 and 100;
**100 is allowed** and means a gifted line: it still appears on the document,
priced, with nothing charged for it.

**Optional — global discount** (`summary`), applied to the whole document after
per-line discounts:
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

### Step 3b — Edit the draft (optional)

A draft can be edited before issuing with `PATCH /invoices/:id`. It uses PATCH
semantics — send only the fields you want to change; omitted fields keep their
current value. You can update `notes`, `date`, `dueDate`, `taxPointDate`, `cae`,
`customerId`, `items` (including their per-line discounts), `summary`, `payment`,
and `seriesId` (e.g. move the draft into another series):
```bash
fiz PATCH /invoices/{id} '{ "notes": "PO #118", "seriesId": "68483b3fa19e44171e3d0808" }'
```
Returns the updated draft. A **404** here means *something* referenced wasn't
found — either the invoice `id` in the path **or** a `seriesId` you passed (a
well-formed but unknown series 404s the same way it does on create). Check which
before telling the user the draft is gone. Editing is intended for drafts — once an
invoice is issued it should be corrected with a credit note, not a PATCH (the one
exception being `POST /invoices/:id/pay`, step 6).

`taxPointDate` is the one field you can **clear** rather than only change: send
`"taxPointDate": null` to drop it, and the document falls back to its issue date.
Sending `null` for `date` is *not* accepted — omit the key to leave the issue date
alone.

Replacing `items` replaces the whole array, so send every line you want to keep,
not just the changed one.

### Step 4 — Issue the invoice

This is the binding step. **Confirm with the user**, then:
```bash
fiz POST /invoices/{id}/issue
```
Returns **200** (not 201 — it finalizes an existing draft rather than creating a
resource) with the official `number`, the `atcud`, the 4-character `shortHash`
printed on the PDF, `status: ISSUED`, and a `syncWithAt` block.

**Check `syncWithAt.status`** — if it is `FAILED`, the invoice was created
locally but did not sync with the tax authority; report `atMessage` and whether
`isRetriable` is true to the user instead of claiming success.

Report the `number` back to the user — that is the reference they and their
customer will use, and it exists only after this call.

### Step 5 — Download the PDF (optional)

```bash
fiz GET /invoices/{id}/pdf
```
Returns `{ id, name, url }`; the `url` is a downloadable link to the PDF.
Add `?format=A4` or `?format=RECEIPT` to choose the layout.

The same endpoint serves **any** document by id — including a receipt returned by
step 6 and a credit note — so use the `id` of whichever document you want.

### Step 6 — Register a payment on an issued invoice (optional)

When the customer actually pays an invoice that is already issued, record it:

```bash
fiz POST /invoices/{id}/pay '{
  "method": "bankTransfer",
  "date": "2026-09-10T00:00:00.000Z"
}'
```

- Only for `INVOICE` or `DEBIT_NOTE` in status `ISSUED`. Anything else is a 400.
  (A payment on the *draft* of a `INVOICE_RECEIPT` / `SIMPLIFIED_INVOICE` is the
  `payment` object at creation instead — step 3.)
- **Omit `amount` to settle the whole outstanding balance.** Send `amount` only
  for a partial payment; minimum `0.01`, at most two decimals. Note that sending
  `"amount": null` is *not* a way to say "settle everything" — it is rejected;
  leave the key out.
- Paying is allowed on an issued document — the one exception to "an issued
  invoice cannot be modified".

The response carries `status` (`PAID` when fully settled), a `payments[]` array
of every payment recorded with its amount, and `receipt` — the **recibo (RG) this
payment issued**, with its own `id`, `number` and `atcud`. Pass that `receipt.id`
to `GET /invoices/{id}/pdf` to give the customer their receipt.

Two things to read carefully in that response:
- The legacy top-level `payment` field is filled **only when the invoice becomes
  fully paid**; on a partial payment it is `null`. Use `payments[]`, not
  `payment`, to report what was recorded.
- `receipt` is `null` for invoices imported from the AT (no receipt is issued for
  those). It is always the receipt *this* call produced, never an earlier one.

## Correcting or cancelling an issued invoice

An **issued** invoice is a final fiscal document: it cannot be deleted or
`PATCH`ed. There are two ways to undo it, both reported to the AT. (Recording a
payment on it is not an undo — it is allowed, and it is step 6 above.)

### Credit note — reverse an issued invoice

A credit note (nota de crédito) reverses a previously issued invoice. Use it to
fix a wrong amount, a wrong VAT rate, a document issued by mistake, a return, etc.
It is itself a legal document, so it needs a **reason code** (Anexo 40) and a
short **reason text**.

```bash
fiz POST /invoices/credit-notes '{
  "parentInvoiceId": "<the issued invoice id>",
  "reasonCode": "INCORRECT_VAT_RATE",
  "reason": "Correção de IVA — taxa incorreta"
}'
```

- `parentInvoiceId` — the invoice being reversed. The note copies that invoice's
  customer and lines, so it reverses the **whole** document (a full reversal).
- `reasonCode` — an Anexo 40 code (see `domain.md`), e.g. `INCORRECT_VAT_RATE`,
  `WRONG_INVOICE`, `RETURN_GOODS_SERVICES`, `OPERATION_CANCELLATION`. Pick the one
  that matches *why*, don't default blindly.
- `reason` — a human-readable text. **Required** — the note is rejected without a
  non-empty reason. If you omit it, a default label for the `reasonCode` is used.
- `issue` — optional, defaults to `true`: the note is created **and issued** in one
  call (it does not stay a draft). Pass `"issue": false` to leave a draft.

The response is the issued credit note (`documentType: CREDIT_NOTE`,
`status: ISSUED`, its own `number`/`atcud`, a `syncWithAt` block — check it like
any issue). A **full** credit note also flips the parent invoice to
`status: CANCELED`.

Because a credit note issues immediately and hits the AT, treat it like an
**issue**: confirm with the user first (which invoice, reason, amount).

### To fix a wrong invoice and re-bill

The common "I issued it with the wrong VAT / wrong price" fix is two steps:

1. **Credit note** the wrong invoice (above) — reverses it.
2. **Issue a new, correct invoice** — the normal create + issue flow, with the
   right item/VAT this time.

> After re-billing, **verify the VAT on the *new* document** (`GET` it back and
> check `items[].data.vatRate`/`taxRate`), rather than assuming it inherited what
> you expected. If you re-bill by reusing a catalog item, confirm that item still
> carries the VAT you intend — issuing corrections can leave a catalog item in a
> different state than you last saw it.

### Cancel — for a document with no credit/debit notes yet

```bash
fiz POST /invoices/{id}/cancel
```

Cancels an issued invoice directly (sets `status: CANCELED`). This is **only**
allowed while the invoice has no issued credit/debit notes against it — if it
does, the API returns **400** and you must work through those notes instead.
Prefer a credit note when you need an auditable reversal reason; use cancel for a
clean, reason-less voiding of a document nothing else references yet.

## Transport documents (guias de transporte)

A **guia de transporte** accompanies goods in transit. It is a separate fiscal
document family under `/transport-documents`, with the same draft → issue shape as
an invoice — and the same irreversibility once issued.

The one rule that catches people out: **a guia must reach the AT before the goods
start moving**, so `movementDate` cannot be in the past. Today is fine; yesterday
is a 400. Plan the call accordingly — you cannot paper over a shipment after the
fact with a guia.

### Create a draft guia

```bash
fiz POST /transport-documents '{
  "movementType": "GUIA_DE_REMESSA",
  "movementDate": "2026-09-05T08:00:00.000Z",
  "movementStartTime": "2026-09-05T08:30:00.000Z",
  "addressFrom": {
    "name": "Armazém Lisboa",
    "addressDetail": "Rua da Prata, 12",
    "postalCode": "1100-052",
    "city": "Lisboa",
    "country": "PT"
  },
  "customer": {
    "data": {
      "name": "Padaria Central, Lda",
      "taxpayerNumber": "501234560",
      "address": "Av. da Liberdade, 200",
      "postalCode": "1250-147",
      "city": "Lisboa",
      "country": "PT"
    }
  },
  "items": [ { "id": "68483e978073231c3947077c", "quantity": 10 } ]
}'
```

**`movementType`** — pick the one that matches the actual movement:

| Value | Use for |
|---|---|
| `GUIA_DE_REMESSA` | Delivery of goods to a customer |
| `GUIA_DE_DEVOLUCAO` | Goods being returned |
| `GUIA_DE_TRANSPORTE` | Generic transport |
| `GUIA_DE_ATIVOS_PROPRIOS` | Moving your own goods between your own premises |
| `GUIA_DE_CONSIGNACAO` | Goods sent on consignment |

Field rules:
- **`customer` is required for every type except `GUIA_DE_ATIVOS_PROPRIOS`** —
  moving your own assets has no recipient. Only Portuguese recipients
  (`country: "PT"`) are accepted; guias are reported to the Portuguese AT.
- `customer.data` holds the recipient snapshot. Add `customer.ref` with an
  existing customer `id` from `GET /customers` to link the guia to that customer
  as well — the snapshot is still required.
- `addressFrom` (loading place) is required; `addressTo` (unloading place) is
  optional. Both take `{ name, addressDetail, postalCode, city, country }`, and
  optionally a `ref`.
- `movementStartTime` (loading) is required. `movementEndTime` (expected
  unloading) is optional but, if sent, **must be after** `movementStartTime`.
- `vehicleID` (e.g. `"AA-00-BB"`) is optional.
- `items` uses the same `{ id, quantity }` shape as an invoice.

### Issue, cancel, and the rest

```bash
fiz POST /transport-documents/{id}/issue    # 200 — reports it to the AT. Irreversible.
fiz POST /transport-documents/{id}/cancel   # 200 — voids an issued guia
fiz PATCH /transport-documents/{id} '{ … }' # edit a draft
fiz GET  /transport-documents               # list; ?search=, ?movementType=, ?issueStatus=, ?offset=, ?limit=, ?sort=movementDate:desc
fiz GET  /transport-documents/{id}
fiz GET  /transport-documents/{id}/pdf
fiz DELETE /transport-documents/{id}        # drafts only
```

Issuing a guia is an AT-reported act: **confirm with the user first**, exactly as
you would before issuing an invoice. Issuing an already-issued guia returns 400,
as does cancelling one that was never issued.

## Bank transactions (read-only)

If the account has the accounting feature and a bank connection, you can read
transactions — useful for answering "was invoice X actually paid?" before you
record a payment.

```bash
fiz GET /bank/connections
fiz GET "/bank/transactions?connectionId=<id>&fromDate=2026-09-01T00:00:00.000Z&searchString=padaria"
```

`GET /bank/connections` returns each connection with `id`, `providerName`,
`countryCode`, `status`, and `maskedIbans` (e.g. `"PT··3003"`). Pass the `id` as
`connectionId` — it is **required** on `/bank/transactions`.

Filters: `fromDate`, `toDate`, `searchString`, `direction`, `types`, plus `page`
(default 1) and `pageSize` (default 50).

Both are reads and need no confirmation. **403** means the account's plan has no
accounting access — say so rather than retrying.

This is bank data: report only what the user asked about, and don't dump whole
statements into the conversation unprompted.

## Idempotency — make a retry safe

Every write endpoint accepts an optional **`Idempotency-Key`** header. Send one
and a repeat of the same request replays the original response instead of
executing again — the difference between a timeout costing you nothing and a
timeout issuing a second invoice.

The `fiz` helper sends the header when `FIZ_IDEMPOTENCY_KEY` is set, and reports
back what the API said about it: an `IDEMPOTENT-REPLAYED:` line when a stored
response was replayed, and a `RETRY-AFTER:` line when a 409 says to wait.

**Write the key out as a literal, and don't rely on shell state to carry it.**
Generate the UUID once, then paste that same literal value into the retry. A key
held in a shell variable is the wrong tool here: each command you run may be a
separate shell, so the variable is often gone by the next call — and even in one
shell, `$(uuidgen)` produces a *different* key every time it is evaluated.

```bash
# 1. Generate the key once, and keep the value in front of you.
uuidgen
# → 3f9a1c7e-2b64-4f10-9e83-5d2a17c4b8e6

# 2. Use that literal value on the attempt...
FIZ_IDEMPOTENCY_KEY="3f9a1c7e-2b64-4f10-9e83-5d2a17c4b8e6" fiz POST /invoices/{id}/issue

# 3. ...and on every retry of THAT SAME operation — the identical literal.
FIZ_IDEMPOTENCY_KEY="3f9a1c7e-2b64-4f10-9e83-5d2a17c4b8e6" fiz POST /invoices/{id}/issue
```

A per-command prefix like this is right *because* it doesn't persist: nothing
leaks into the next, unrelated write (which would earn a 422). What has to
persist is the **value**, and you carry that yourself — read it back from the
output of step 1 rather than regenerating it.

The one thing never to do is put `$(uuidgen)` in the command you might repeat: it
re-runs on the retry, sends a brand-new key, and issues a second document — the
exact failure this feature exists to prevent.

With raw curl, add the same literal both times — spelled out in full, since the
key must be printable ASCII with no spaces:

```bash
curl -sS -w '\n%{http_code}' -X POST \
  "$FIZ_API_URL/invoices/<id>/issue" \
  -H "x-api-key: $FIZ_API_KEY" \
  -H "Idempotency-Key: 3f9a1c7e-2b64-4f10-9e83-5d2a17c4b8e6"
```

**Use a key on every write whose repetition would be harmful** — issue, pay,
credit note, cancel, and document creation. Generate a fresh key per logical
operation (a UUID is ideal). On a straightforward retry — a timeout, a dropped
connection — reuse that same key; a new key there defeats the whole mechanism.
The exception is a 409 saying the first attempt's outcome is unknown: see below,
where reusing the key is exactly the wrong move.

Responses to know:
- **Replay** — same status and body as the first call, plus the header
  `Idempotent-Replayed: true`. Report the original result; don't treat it as a
  new document.
- **409** — covers three different situations, and they need *opposite* actions.
  **Read the `message` before doing anything**, and never retry a 409 blindly:
  - *"still being processed"* — the first attempt is in flight. Wait
    `Retry-After` seconds and retry the **same** key. Only this case is a
    plain retry; the helper prints the delay as a `RETRY-AFTER:` line.
  - *"started but never reported a result"* — the first attempt **may already
    have taken effect**. Do **not** retry the same key; it will keep answering
    409. Verify first, then resend with a **new** key only if the write did not
    land. **Check the postcondition, not the document's existence** — see below.
  - *"already succeeded, but its response is no longer available"* — the write
    **did** happen and only the stored response expired. Look the document up;
    a retry under a new key would create a second one.

  In the last two cases, verifying before any retry is the whole point — that is
  what stops a duplicate invoice.

**How to verify: check the postcondition, not existence.** Only a *create* can be
confirmed by "does the document exist?". Every other write acts on a document
that already existed, so its presence proves nothing — `GET` it and check the
specific thing the call was supposed to change:

| Call | What to check on the `GET` |
|---|---|
| `POST /invoices` (create) | a draft with your data exists — the one case where existence is the answer |
| `POST /invoices/:id/issue` | `status` is `ISSUED` and `number`/`atcud` are no longer `null` |
| `POST /invoices/:id/pay` | list the receipts belonging to **this** invoice: `GET "/invoices?documentType=RECEIPT&parentInvoiceId=<invoice-id>"`, and check whether one matches your payment's date and amount. Don't try to confirm it from `GET /invoices/:id` alone — that returns only the legacy `payment` (`method`/`date`, no amount), so a partial payment is invisible there, and `status: PAID` could be explained by an earlier payment |
| `POST /invoices/credit-notes` | `GET "/invoices?documentType=CREDIT_NOTE&parentInvoiceId=<invoice-id>"` returns your note |
| `POST /invoices/:id/cancel` | `status` is `CANCELED` |
| `PATCH /invoices/:id` | the fields you sent hold the new values |
| `DELETE /invoices/:id` | the document is gone (404) |
| `POST /transport-documents/:id/issue` | `GET /transport-documents/:id` shows the guia issued (it has a number and is no longer a draft) |

If the postcondition holds, the write landed — report it and **do not resend**.
If you cannot establish it either way, stop and tell the user what you know: an
unnecessary duplicate of a fiscal document is worse than a delay.
- **422** — this key was already used with a *different* body. That means you
  changed the payload; fix the payload or use a new key for a genuinely new
  operation.
- **400** — the key is malformed. It must be printable ASCII with no spaces, at
  most 128 characters.

A key is remembered for 30 days. Without the header nothing changes — the
behaviour is exactly as before.

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
| List series       | `GET /series`              |
| List registered CAE codes | `GET /templates`   |
| Work out the VAT rate for a sale | `POST /vat/calculate` |
| Check a customer's VAT number | `POST /vat/validate-client` |
| Create draft      | `POST /invoices`           |
| Edit draft        | `PATCH /invoices/:id`      |
| Issue             | `POST /invoices/:id/issue` |
| Register a payment on an issued invoice | `POST /invoices/:id/pay` |
| Credit note (reverse an issued invoice) | `POST /invoices/credit-notes` |
| Cancel an issued invoice | `POST /invoices/:id/cancel` |
| List invoices     | `GET /invoices`            |
| Get one invoice   | `GET /invoices/:id`        |
| Download PDF (any document, by id) | `GET /invoices/:id/pdf` |
| Delete (draft)    | `DELETE /invoices/:id`     |
| Create a guia de transporte | `POST /transport-documents` |
| Issue a guia      | `POST /transport-documents/:id/issue` |
| List guias        | `GET /transport-documents` |
| Bank connections / transactions | `GET /bank/connections`, `GET /bank/transactions` |

Every write above accepts an optional `Idempotency-Key` header.

## Error handling

**Always check the HTTP status, not just that the command ran.** On error the API
returns a normal-looking JSON body — `{ "statusCode": 400, "message": "...",
"timestamp": "..." }` — with the matching HTTP status. With raw `curl -s` that
body prints and `curl` still exits 0, so it is easy to mistake an error for a
result. The `fiz` helper guards against this: it prints an `HTTP <code>` line and
returns non-zero on 4xx/5xx. If you must use raw curl, add `-w '\n%{http_code}'`
(or `-o body -w '%{http_code}'`) and inspect the code.

Common statuses:
- **401** — no API key was sent. Tell the user to set `FIZ_API_KEY` in their
  environment (not in chat).
- **403** — a key *was* sent but was rejected, or the account's plan lacks the
  feature (e.g. `/bank` without accounting access). These are different problems:
  a wrong key is for the user to replace, a plan limit is not fixable by retrying.
- **400** — validation error; the `message` says which field. Common cases:
  empty `items`, `payment` on an unsupported `type`, an unknown/extra field
  (strict whitelist), a discount type without its matching value, a
  `taxPointDate` after the issue date, a past `movementDate` on a guia, a
  malformed `Idempotency-Key`, or a malformed date (dates must be full ISO 8601
  with timezone, e.g. `2026-07-18T00:00:00.000Z`).
- **402** — the account's plan doesn't include the feature (`/vat/calculate`
  needs Auto IVA). Report it; don't retry.
- **404** — something referenced doesn't exist. On endpoints that take more than
  one reference, work out *which*: a well-formed but unknown `seriesId` 404s just
  like an unknown invoice id.
- **409 / 422** — idempotency: a request with this key is still in flight (409,
  retry the same key after `Retry-After`), or the key was reused with a different
  body (422). See "Idempotency" above.
- **5xx** — backend/AT problem; surface it, and **do not retry the same write
  blindly** — it may have partially succeeded. An `Idempotency-Key` does *not*
  make this retry automatic: only an early validation 400 releases the key, so
  after a 5xx the key is spent and reusing it answers 409, not a replay. Recover
  the same way as the "outcome unknown" 409 above: `GET` and check the
  **postcondition** for that call (see the table under "Idempotency" — for
  anything but a create, the document's existence proves nothing), and resend
  with a **new** key only if the write did not land. What the key buys you here
  is the guarantee that a blind retry cannot silently duplicate — not a free
  retry.

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
  customer/item/invoice/guia field, all enum values, full request/response
  shapes).

The live Swagger UI at **https://api.fiz.co/** is the authoritative contract —
check it when something here looks out of date. The MCP connector is documented
at **https://api.fiz.co/docs/mcp**.

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
