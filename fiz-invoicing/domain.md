# FIZ Invoicing — Portuguese Tax Domain Reference

Background for issuing *correct* invoices through the FIZ Public API. These are
the real business rules behind the fields.

> **Last reviewed: 2026-01.** Tax rules change. The VAT **rate table** below is
> verified against the FIZ backend (the engine's own rate definitions) and matches
> published Portuguese rates as of this date. Other figures — the Art. 53.º
> turnover threshold (~€15,000), the €3,000 cash ceiling, the €1,000 NIF rule, the
> CAE Rev. 4 requirement, and the specifics of individual M-codes — are provided
> for guidance and were **not** all re-verified line by line. Treat them as a
> starting point: the authoritative behaviour is whatever the FIZ API enforces and
> what the user's accountant confirms. When a value here conflicts with either,
> trust them over this file.

## Official sources — verify tax details here

This file is a convenience summary. For anything that affects a real fiscal
document, check the primary sources below (all from the Portuguese Tax Authority,
*Autoridade Tributária e Aduaneira* — AT) or a qualified accountant. Tell the user
to do the same when a tax point is material or uncertain.

- **CIVA — Código do IVA** (the VAT Code itself; defines rates, exemptions,
  reverse charge): https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/civa_rep/Pages/codigo-do-iva-indice.aspx
  (full PDF: https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/Cod_download/Documents/CIVA.pdf)
- **All tax codes (CIVA, RITI, etc.)**: https://info.portaldasfinancas.gov.pt/pt/informacao_fiscal/codigos_tributarios/Pages/default-com-pdf.aspx
- **VAT exemption codes (motivos de isenção, the `M`-codes)** — the authoritative
  artifact is the `TaxExemptionCode` table annexed to **Portaria n.º 302/2016**
  (later revised; for 2023 M08 was split into M30–M43 and M19/M25 added). Official
  text of the Portaria (Diário da República):
  https://diariodarepublica.pt/dr/detalhe/portaria/302-2016-105300290
  General AT VAT portal:
  https://info.portaldasfinancas.gov.pt/pt/apoio_contribuinte/modelos_formularios/iva/Pages/imposto-sobre-o-valor-acrescentado.aspx
- **ATCUD & invoice QR code** — required by **Portaria n.º 195/2020**, mandatory
  since 1 Jan 2023. (Handled by FIZ on issue; listed here for reference.)
- **Portal das Finanças (AT) — VAT home**: https://www.portaldasfinancas.gov.pt/pt/IVA/menu.action

The FIZ web app and Public API are the source of truth for what FIZ will *accept*;
these AT sources are the source of truth for what is *legally correct*.

---

## VAT rates (IVA) by territory

Each item carries a `vatRate` (`NORMAL` | `INTERMEDIATE` | `REDUCED` | `EXEMPT`).
The percentage that rate maps to depends on the Portuguese territory of the
issuing business:

| `vatRate`      | Continental | Açores | Madeira |
|----------------|-------------|--------|---------|
| `NORMAL`       | 23%         | 16%    | 22%     |
| `INTERMEDIATE` | 13%         | 9%     | 12%     |
| `REDUCED`      | 6%          | 4%     | 4%      |
| `EXEMPT`       | 0%          | 0%     | 0%      |

Notes:
- These are the percentages FIZ applies; the API computes tax amounts from the
  `vatRate` + the business's territory, so you select the *rate band*, not the
  raw percentage.
- **Default to `NORMAL`.** `INTERMEDIATE` and `REDUCED` apply only to specific
  legally-defined categories (e.g. certain foodstuffs, restaurant services,
  cultural events, some utilities). Don't apply them unless the user states the
  category warrants it.
- Rates are subject to change by the annual State Budget (Orçamento do Estado).
  If you need the authoritative current set programmatically, the FIZ web app
  reads them from the backend `vatFramework` query rather than hardcoding.

(Historical note for maintainers: some older internal constants and docs listed
Açores Normal as 18% and Madeira Reduced as 5%; the live rate table used by the
invoicing engine uses the values above. Use these.)

---

## VAT exemption reasons (motivo de isenção, "M-codes")

When `vatRate` is `EXEMPT`, Portuguese law requires stating *why* — a code from
the AT's official list (the `TaxExemptionCode` table from **Portaria n.º 302/2016**,
revised for 2023; see "Official sources" above). Always provide one: the field is
technically optional at item creation, but an exempt item without a valid code is
an invalid document and can be rejected when the invoice is issued. The code must
match the actual legal basis; pick by situation, not by convenience. The mappings
below are a guide — confirm the exact code against the AT table or an accountant.

> **This list is a routing guide, not the complete or authoritative table.** It
> covers the codes you'll meet most often and helps you pick a likely one from the
> user's situation. The full, current definitions live in the Portaria n.º
> 302/2016 `TaxExemptionCode` annex (linked under "Official sources"). For any
> tax-critical document, verify the chosen code there or with an accountant.

Most common in practice:

| Code | Legal basis | When it applies |
|------|-------------|-----------------|
| **M10** | Art. 53.º CIVA | Small-business exemption — business under the annual turnover threshold (~€15,000). The typical reason a freelancer/small business doesn't charge VAT ("regime de isenção do artigo 53.º"). |
| **M07** | Art. 9.º CIVA | Activity exempt by nature: healthcare, education, certain social, cultural, financial and real-estate services. |
| **M01** | Art. 16.º n.º 6 CIVA | Exclusion from the taxable amount (specific items excluded from the taxable base). Not a generic "I'm exempt" code — only when this article actually applies. |
| **M40** | Art. 6.º CIVA | Reverse charge — B2B **services** to a taxable customer in another country; the buyer self-assesses the VAT. |
| **M16** | Art. 14.º RITI | Intra-EU **goods** to a VAT-registered EU business (VIES-validated). |
| **M19** | Other exemptions | Catch-all for other legal exemptions / certain cross-border cases. |

Other codes that exist in the system (use only when the specific legal basis
applies): M02, M04, M05, M06, M09, M11, M12, M13, M14, M15, M20, M21, M25, M26,
M30 (reverse charge — recyclable waste/scrap), M31 (reverse charge — civil
construction), M32, M33, M34, M41, M42 (reverse charge — real estate), M43
(reverse charge — investment gold), M44, M45, M46, M99 (not subject / not taxed).

How to choose, by what the user tells you:
- "I'm a small business / under the threshold / artigo 53" → **M10**
- "Healthcare / medical / education / training" → **M07**
- "Export outside the EU" → **M05** (or **M99** for not-subject cases)
- "EU business customer, services, they pay the VAT" → **M40**
- "EU business customer, physical goods" → **M16**
- "Construction / waste / scrap reverse charge" → **M31 / M30**
- Unsure → **ask the user why they're exempt**; do not guess.

---

## Document types

| Type                 | Portuguese          | Use                                                                 |
|----------------------|---------------------|---------------------------------------------------------------------|
| `INVOICE`            | Fatura              | Standard invoice; customer pays later. NIF required if total >€1,000. Most common. |
| `INVOICE_RECEIPT`    | Fatura-recibo       | Invoice + payment proof in one, when paid immediately. Supports `payment` on creation. |
| `SIMPLIFIED_INVOICE` | Fatura simplificada | Small retail sales; customer NIF/details optional. Supports `payment` on creation. |
| `RECEIPT`            | Recibo              | Payment receipt referencing a parent invoice.                       |
| `CREDIT_NOTE`        | Nota de crédito     | Reduces/annuls a previously issued invoice — the only way to "cancel" an issued invoice. Needs a reason. |
| `DEBIT_NOTE`         | Nota de débito      | Increases a previously issued invoice.                              |

Default to `INVOICE` unless the user asks for a receipt/simplified document. Only
`INVOICE_RECEIPT` and `SIMPLIFIED_INVOICE` accept a `payment` object at creation
time (the API returns 400 for other types).

---

## CAE — economic activity code

- 5-digit Portuguese activity classification (Classificação das Atividades
  Económicas), e.g. `62010` = computer programming. Individuals may use a 4-digit
  CIRS code instead.
- Required on every invoice (except credit/debit notes).
- Must be a code the business has **registered with the AT**, and must be a
  current **Rev. 4** code (outdated Rev. 3 codes are rejected).
- Don't invent one. Ask the user, or reuse the CAE from one of their previous
  invoices (`GET /invoices` shows it).

---

## NIF / taxpayerNumber

- Portuguese tax number: 9 digits with a mod-11 check digit. NIFs/NIPC starting
  with `5` are companies; `1/2/3` individuals; `9`-prefixed are special entities.
- Required for B2B invoices; for an `INVOICE` to a business over €1,000 the
  customer NIF is required. Optional for final consumers ("consumidor final") and
  for simplified invoices.
- For **EU B2B**, the customer's VAT number (PT + 9 digits for Portugal, country-
  specific elsewhere) determines reverse-charge treatment and may be VIES-checked.
- The API stores numbers without the country prefix.

---

## Withholding tax (retenção na fonte)

Configured per item, not on the invoice as a whole:
- `withholdingTaxType`: `IRS` (individuals' income tax), `IRC` (corporate income
  tax), or `IS` (stamp duty — Imposto de Selo).
- `withholdingTaxPercent`: 1–99%. A very common value is **25%** for self-employed
  professional services; some services use other rates (e.g. 11.5%, 23%).
- `withholdingTaxReason`: required only when the type is `IS`.
- Meaning: the *payer* withholds this amount and remits it to the AT, so the
  amount the supplier actually receives is reduced. It does not change the VAT.

Default is no withholding unless the user says their services are subject to it.

---

## Issuing, AT sync, and irreversibility

- **Draft** (`DRAFT`): created locally, *not* sent to AT, freely editable and
  deletable.
- **Issue** (`POST /invoices/:id/issue`): assigns the official sequential number,
  ATCUD, QR code, and communicates the document to the AT / e-Fatura. After this
  the document is `ISSUED` and **immutable** — it cannot be edited or deleted.
- **ATCUD** is the AT unique document code, mandatory on issued invoices since
  2023; its presence means the document is certified and registered.
- **Sequential numbering**: you cannot issue an invoice dated before the last
  issued invoice in its series. Backdating is restricted by law.
- Marking an invoice **paid** does not notify the AT (internal tracking only).
- To reverse an issued invoice you issue a **credit note** (`CREDIT_NOTE`) with a
  reason — there is no "delete" for issued documents.
- After issuing, always check `syncWithAt.status` in the response. `SYNCED` =
  registered with AT; `PROCESSING` = pending; `FAILED` = created locally but not
  accepted by AT — report `atMessage` and `isRetriable` rather than telling the
  user it succeeded.

---

## Payment methods (`payment.method`)

`cash` · `card` · `bankTransfer` · `mbWay` · `multibanco` · `spin` · `other`

Note: **cash** payments in Portugal have a legal per-transaction ceiling
(€3,000 for most cases) — relevant if a user tries to record a large cash payment.
