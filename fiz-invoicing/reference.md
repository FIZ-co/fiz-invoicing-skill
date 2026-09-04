# FIZ Public API — Full Reference

Complete field reference for the endpoints used to issue Portuguese fiscal
documents. Base URL: `https://api.fiz.co`. Auth header: `x-api-key`. All requests
except the docs require it — **no key → 401, a rejected key → 403.**

The live Swagger UI at `https://api.fiz.co/` is the authoritative contract.

The API validates with a strict whitelist: **unknown fields cause a 400**. Send
only the fields listed here.

---

## Customers

### `POST /customers`

| Field             | Type   | Required | Notes / example                         |
|-------------------|--------|----------|-----------------------------------------|
| `name`            | string | **yes**  | `"João Silva"`                          |
| `firstName`       | string | no       | `"João"`                                |
| `lastName`        | string | no       | `"Silva"`                               |
| `email`           | string | no       | valid email                             |
| `taxpayerNumber`  | string | no       | NIF, e.g. `"303741791"`                 |
| `country`         | string | no       | ISO 3166-1 alpha-2, default `"PT"`      |
| `phone`           | string | no       | `"+351912345678"`                       |
| `mobile`          | string | no       | `"+351912345678"`                       |
| `fax`             | string | no       | `"+351212345678"`                       |
| `address`         | string | no       | `"Rua das Flores, 123"`                 |
| `city`            | string | no       | `"Lisboa"`                              |
| `postalCode`      | string | no       | `"1000-100"`                            |
| `website`         | string | no       | `"https://example.com"`                 |
| `companyName`     | string | no       | `"Silva & Associados Lda"`              |
| `companyPosition` | string | no       | `"Diretor Geral"`                       |
| `description`     | string | no       | free text                               |
| `photo`           | string | no       | URL                                     |

Response: the created customer, including `id` (use as `customerId`).

### `GET /customers`, `GET /customers/:id`, `PATCH /customers/:id`, `DELETE /customers/:id`

List supports `?search=`. `PATCH` accepts any subset of the create fields.

---

## Items (products / services)

### `POST /items`

| Field                     | Type    | Required | Notes / values                                          |
|---------------------------|---------|----------|---------------------------------------------------------|
| `name`                    | string  | **yes**  | `"Consulting hour"`                                     |
| `type`                    | enum    | **yes**  | `PRODUCT` \| `SERVICE`                                  |
| `unitPrice`               | number  | **yes**  | ≥ 0, e.g. `80`                                          |
| `vatRate`                 | enum    | **yes**  | `NORMAL` \| `INTERMEDIATE` \| `REDUCED` \| `EXEMPT`     |
| `description`             | string  | no       |                                                         |
| `unitType`                | enum    | no       | `UNIT` \| `HOUR` \| `DAY` \| `MONTH` \| `WEEK` \| `BOX` \| `PACKAGE` \| `METER` \| `SQUARE_METER` \| `CUBIC_METER` \| `KILOGRAM` \| `LITER` \| `NA` |
| `vatTerritory`            | enum    | no       | e.g. `CONTINENTAL` (Portuguese territory)               |
| `taxRate`                 | number  | no       | percentage, ≥ 0, e.g. `23`                              |
| `vatExemptionReason`      | string  | no       | required when `vatRate` is `EXEMPT`; an `M`-code matching the legal reason — see `domain.md` |
| `ossCountry`              | string  | no       | OSS country code; mutually exclusive with `vatTerritory`  |
| `unitDiscountType`        | enum    | no       | `PERCENT` \| `AMOUNT` — a standing discount applied whenever the item is invoiced |
| `unitDiscountPercent`     | number  | no       | 0–100; requires `unitDiscountType: PERCENT`             |
| `unitDiscountAmount`      | number  | no       | ≥ 0, per unit; requires `unitDiscountType: AMOUNT`       |
| `termsOfPayment`          | string  | no       | `"Pagamento a 30 dias"`                                 |
| `isAutoVATEnabled`        | boolean | no       | default `false`                                         |
| `withholdingTaxAvailable` | boolean | no       | default `false`                                         |
| `withholdingTaxPercent`   | number  | no       | ≥ 0, e.g. `25`                                          |
| `withholdingTaxType`      | enum    | no       | `IRS` \| `IRC` \| `IS`                                  |
| `withholdingTaxReason`    | string  | no       | free text                                               |

Response: the created item, including `id` (use in the invoice `items` array).

### `GET /items`, `GET /items/:id`, `PATCH /items/:id`, `DELETE /items/:id`

List supports `?search=`. **`PATCH /items/:id` requires `type`** even when you
aren't changing it — send the item's current value alongside whatever you are
updating. To clear a standing discount:

```json
{ "type": "SERVICE", "unitDiscountType": null }
```

`taxRate` is derived from the item's VAT fields when you don't send it — set
`vatRate` (and `vatTerritory` where relevant) and let the API compute the
percentage, rather than sending a `taxRate` that contradicts them.

A per-line discount on an invoice **overrides** the item's `unitDiscount*` for
that line.

---

## Invoices

### `POST /invoices` — create draft

| Field          | Type     | Required | Notes                                                     |
|----------------|----------|----------|-----------------------------------------------------------|
| `cae`          | string   | **yes**  | Portuguese economic activity code, e.g. `"62010"`         |
| `type`         | enum     | **yes**  | see Document types below                                  |
| `customerId`   | string   | **yes**  | customer `id`                                             |
| `items`        | array    | **yes**  | at least 1 element (upper bound 200), see the item-line table below |
| `date`         | string   | no       | issue date, ISO 8601 w/ timezone; omit → now. Determines the tax period. An explicit `null` is rejected — omit the key |
| `dueDate`      | string   | no       | ISO 8601 w/ timezone; omit → the issue date               |
| `taxPointDate` | string   | no       | *data da operação* (art. 36.º n.º 5 al. f) CIVA); omit → the issue date. Must not be after the issue date. Ignored on credit/debit notes |
| `notes`        | string   | no       | free-text note on the invoice                             |
| `seriesId`     | string   | no       | series `id` from `GET /series`; omit → account default. Malformed id → 400; well-formed but unknown id → 404 (no silent fallback) |
| `summary`      | object   | no       | global discount, see below                                |
| `payment`      | object   | no       | only for `INVOICE_RECEIPT` / `SIMPLIFIED_INVOICE`         |

The API sets `currency` (`EUR`) itself — do not send it.

**`items[]` element:**

| Field             | Type   | Required | Notes                                              |
|-------------------|--------|----------|----------------------------------------------------|
| `id`              | string | **yes**  | item `id` from `GET /items`                        |
| `quantity`        | number | **yes**  | ≥ 1                                                |
| `discountType`    | enum   | no       | `PERCENT` \| `AMOUNT` — overrides the item's `unitDiscount*`; applied before the global discount |
| `discountPercent` | number | no       | 0–100 (**100 allowed** = gifted line); requires `discountType: PERCENT` |
| `discountAmount`  | number | no       | ≥ 0, per unit; requires `discountType: AMOUNT`     |

A `discountType` without its matching value, or a value without the matching
type, is a **400**.

Response fields `number`, `atcud` and `shortHash` are `null` on a draft — they
are assigned at issue.

**`summary` object:**

| Field                   | Type   | Notes                                  |
|-------------------------|--------|----------------------------------------|
| `globalDiscountType`    | enum   | `PERCENT` \| `AMOUNT`                   |
| `globalDiscountPercent` | number | use with `PERCENT`, e.g. `10` = 10%    |
| `globalDiscountAmount`  | number | use with `AMOUNT`, absolute value      |

**`payment` object:**

| Field    | Type   | Notes                                                              |
|----------|--------|--------------------------------------------------------------------|
| `method` | enum   | `cash` \| `card` \| `bankTransfer` \| `mbWay` \| `multibanco` \| `spin` \| `other` |
| `date`   | string | ISO 8601 w/ timezone                                               |

Passing `payment` for any `type` other than `INVOICE_RECEIPT` or
`SIMPLIFIED_INVOICE` returns **400** with:
`"payment can only be provided for document types: INVOICE_RECEIPT, SIMPLIFIED_INVOICE"`.

**Document types (`type` — `Invoice_Document_Type`):**

`INVOICE` · `INVOICE_RECEIPT` · `SIMPLIFIED_INVOICE` · `RECEIPT` ·
`CREDIT_NOTE` · `DEBIT_NOTE`

**Response (abridged):**
```json
{
  "id": "6900afc7e9a04d2adc897c68",
  "documentType": "INVOICE",
  "status": "DRAFT",
  "series": { "ref": "…", "name": "FIZ2025…" },
  "payment": null,
  "customer": { "ref": "…", "data": { "name": "…", "taxpayerNumber": "…", "email": "…", "country": "PT" } },
  "dueDate": "2026-07-18T00:00:00.000Z",
  "date": "2026-06-18T11:57:59.008Z",
  "items": [
    { "id": "…", "ref": "<item id>", "meta": { "quantity": 10, "taxAmount": 184 },
      "data": { "name": "…", "unitPrice": 80, "taxRate": 23, "vatRate": "NORMAL" } }
  ]
}
```

The example above is the typical `DRAFT` case. When you pass a `payment` object
(only for `INVOICE_RECEIPT` / `SIMPLIFIED_INVOICE`), the created document may come
back with a non-draft `status` and a populated `payment` field. Either way you
still call the issue endpoint to finalize.

### `PATCH /invoices/:id` — edit a draft

Updates a draft invoice with PATCH semantics: only the fields you send are
changed; omitted fields keep their current value. Accepts any subset of the create
fields **except `type`** (the document type cannot be changed on update):
`notes`, `date`, `dueDate`, `taxPointDate`, `cae`, `customerId`, `items` (with
their per-line discounts), `summary`, `payment`, `seriesId`. Returns the updated
invoice, including its `number`/`atcud`/`shortHash`. Intended for drafts; an
issued invoice should be corrected with a credit note rather than edited — the
one write allowed on an issued document is `POST /invoices/:id/pay`.

`items` is replaced wholesale, not merged: send every line you want to keep.

**`taxPointDate` can be cleared** with an explicit `"taxPointDate": null`, after
which the document falls back to its issue date. `date` cannot — a `null` there is
rejected; omit the key to leave the issue date unchanged.

**404 on PATCH has two causes:** an unknown invoice `id` in the path, *or* a
well-formed but unknown `seriesId` in the body (same as create) — don't assume it's
always the invoice id.

**`payment` differs from create here:** unlike `POST /invoices`, PATCH does **not**
enforce the `INVOICE_RECEIPT` / `SIMPLIFIED_INVOICE` restriction on `payment` (the
type-dependent validator is dropped on update because `type` is omitted). So a
`payment` object is accepted on a PATCH regardless of document type — avoid sending
one unless the document type actually supports it.

```bash
curl -sS -w '\n%{http_code}' -X PATCH \
  "$FIZ_API_URL/invoices/<id>" \
  -H "x-api-key: $FIZ_API_KEY" -H 'Content-Type: application/json' \
  -d '{ "notes": "PO #118", "seriesId": "68483b3fa19e44171e3d0808" }'
```

### `POST /invoices/:id/issue` — issue (finalize)

No body. Returns **200** (not 201 — it finalizes an existing draft) with the
official `number`, the `atcud`, the 4-character `shortHash` printed on the PDF,
`status: ISSUED`, and a `syncWithAt` block:

| Field         | Type    | Notes                                            |
|---------------|---------|--------------------------------------------------|
| `status`      | enum    | `SYNCED` \| `PROCESSING` \| `FAILED`             |
| `atCode`      | string? | tax-authority code                               |
| `atMessage`   | string  | human-readable sync message                      |
| `systemError` | string? | internal error if any                            |
| `isRetriable` | boolean | whether issuing can be retried                   |
| `updatedAt`   | string  | timestamp                                        |

If `status` is `FAILED`, surface `atMessage` and `isRetriable` to the user.

### `POST /invoices/credit-notes` — reverse an issued invoice

Creates a credit note that reverses `parentInvoiceId` (a full reversal — the
parent's customer and lines are copied). By default it is **issued immediately**.

**Request:**

| Field             | Type    | Req | Notes                                                        |
|-------------------|---------|-----|--------------------------------------------------------------|
| `parentInvoiceId` | string  | yes | The issued invoice to reverse.                               |
| `reasonCode`      | enum    | yes | Anexo 40 credit-note reason (see `domain.md`), e.g. `INCORRECT_VAT_RATE`. |
| `reason`          | string  | no  | Free-text reason. Required by the AT; if omitted a default label for `reasonCode` is used. |
| `issue`           | boolean | no  | Default `true` → created **and issued**. `false` → left as a draft. |

**Response:** the credit note — `documentType: CREDIT_NOTE`, its own `id`,
`number`, `atcud`, `status` (`ISSUED` unless `issue:false`), `creditNoteReasonCode`,
`parentInvoiceId`, `customer`, `items`, `summary`, and a `syncWithAt` block (check
it like any issue). A full credit note also sets the **parent** to
`status: CANCELED`.

Common errors: **404** if `parentInvoiceId` doesn't exist; **400** for an invalid
`reasonCode`.

### `POST /invoices/:id/cancel` — cancel an issued invoice

No body. Sets the invoice to `status: CANCELED` (and syncs the cancellation with
the AT). Returns the cancelled invoice with `canceledAt` and a `syncWithAt` block.

**400** if the invoice already has issued credit/debit notes against it — cancel
is only for a document nothing else references yet; otherwise reverse it with a
credit note.

### `POST /invoices/:id/pay` — register a payment on an issued invoice

Settles an invoice that is **already issued** — the one write allowed on an issued
document. Only for `documentType` `INVOICE` or `DEBIT_NOTE` in status `ISSUED`.

| Field    | Type   | Req | Notes                                                        |
|----------|--------|-----|--------------------------------------------------------------|
| `method` | enum   | yes | `cash` \| `card` \| `bankTransfer` \| `mbWay` \| `multibanco` \| `spin` \| `other` |
| `date`   | string | yes | ISO 8601 w/ timezone                                          |
| `amount` | number | no  | **Omit to settle the full outstanding balance.** Partial payment: ≥ 0.01, max 2 decimals. An explicit `null` is rejected — omit the key |

**Response:**

| Field       | Type    | Notes                                                       |
|-------------|---------|-------------------------------------------------------------|
| `status`    | enum    | `PAID` once fully settled                                    |
| `payments`  | array   | every payment recorded, each `{ method, date, amount }`      |
| `payment`   | object? | **legacy** — populated only when the invoice becomes fully paid (`{ method, date }`, no amount). `null` on a partial payment; use `payments` |
| `receipt`   | object? | the recibo (RG) **this** payment issued: `{ id, number, atcud, documentType, status, date, series }`. Pass `receipt.id` to `GET /invoices/{id}/pdf`. `null` for invoices imported from the AT (no receipt is issued). Never an earlier receipt |
| `syncWithAt`| object  | as on issue                                                  |

A receipt carries no `syncWithAt` of its own, so there is no receipt-level sync
status to check — read the `syncWithAt` on the payment response (the invoice's)
instead. Don't read the missing block as meaning a payment has no fiscal
significance.

**400** for a document of the wrong type or status, or an `amount` below 0.01 /
with more than 2 decimals. **404** for an unknown invoice id.

### `GET /invoices` — list

Query params: `offset` (default 0), `limit` (default 20), `sort`
(e.g. `date:desc`), `search`, `documentType`, `status`
(`DRAFT`/`ISSUED`/`PAID`/`CANCELED`/`CREATED`/`SCHEDULED`), `aggregatedStatus`,
`date`, `dueDate`, `fromDate`, `toDate`, `currency`, `description`, `notes`,
`parentInvoiceId`, `filterAllStatusesByDate`, `includeATInvoices`.

`parentInvoiceId` is the reliable way to find the documents derived from one
invoice — the receipts a payment issued, or its credit notes — since a list entry
carries `parentInvoiceId` but no series, so matching on date alone can pick up
another invoice's document:

```bash
fiz GET "/invoices?documentType=RECEIPT&parentInvoiceId=6900afc7e9a04d2adc897c68"
```

### `GET /invoices/:id` — get one

Returns the full invoice: `number`, `atcud`, `status`, totals in `summary`,
`items`, `customer`, `issuer`, `qrCode`, `syncWithAt`, etc.

### `GET /invoices/:id/pdf` — download PDF

Query params: `format` (`A4` | `RECEIPT`), `isDuplicate` (boolean),
`templateId` (string). Returns `{ id, name, url }`.

### `DELETE /invoices/:id`

Deletes the invoice (used for drafts). Returns `{ id, createdAt }`.

---

## Series

### `GET /series` — list the account's active series

Read-only. No query params. Returns an array of the account's **active** series.
Use a series `id` as the `seriesId` when creating or PATCHing an invoice to issue it
into that numbering sequence; omit `seriesId` to use the account's default series.

Each element:

| Field            | Type      | Notes                                                  |
|------------------|-----------|--------------------------------------------------------|
| `id`             | string    | the series id — use as `seriesId` on an invoice        |
| `name`           | string?   | e.g. `"SAAS"`                                           |
| `isDefault`      | boolean?  | whether this is the account's default series           |
| `status`         | string?   | e.g. `"ACTIVE"`                                         |
| `managementMode` | string?   | numbering mode: `AUTOMATIC` \| `MANUAL`                 |
| `entries`        | array?    | per-document-type entries (with ATCUD), see below       |

**`entries[]` element:**

| Field            | Type      | Notes                                                  |
|------------------|-----------|--------------------------------------------------------|
| `documentType`   | string    | document type the entry applies to, e.g. `"INVOICE"`   |
| `validationCode` | string?   | series ATCUD validation code assigned by the AT, e.g. `"AAJF"` |
| `isVerified`     | boolean?  | whether the entry is verified/communicated to the AT   |

```bash
curl -sS -w '\n%{http_code}' \
  "$FIZ_API_URL/series" \
  -H "x-api-key: $FIZ_API_KEY"
```

---

## Templates

### `GET /templates` — list document templates

Read-only, no query params. Each element:

| Field  | Type      | Notes                                                    |
|--------|-----------|----------------------------------------------------------|
| `id`   | string    | template id — usable as `templateId` on the PDF endpoint |
| `name` | string    | e.g. `"Modelo Padrão"`                                    |
| `cae`  | string[]? | the CAE codes registered on the account                  |

The `cae` array is the practical way to find a **valid CAE for the account**
instead of guessing one for `POST /invoices`.

---

## VAT (read-only calculators)

Both endpoints are POSTs that **create nothing** — they only compute. Safe to
call before proposing any write.

### `POST /vat/calculate` — the correct VAT for a sale

| Field              | Type    | Req | Notes                                                     |
|--------------------|---------|-----|-----------------------------------------------------------|
| `clientHasVat`     | boolean | yes | `true` = B2B, `false` = final consumer (B2C)              |
| `itemType`         | enum    | yes | `PRODUCT` \| `SERVICE`                                    |
| `clientCountry`    | string  | no  | ISO 3166-1 alpha-2; default `PT`                          |
| `clientTerritory`  | enum    | no  | `continental` \| `azores` \| `madeira` (Portugal only)    |
| `clientVatNumber`  | string  | no  | national format for PT (a `PT` prefix is stripped); other EU countries validated via VIES |
| `clientPostalCode` | string  | no  | lets the API resolve a PT client's territory itself       |
| `clientIsTIENI`    | boolean | no  | client is a *trabalhador independente* / ENI — used to resolve the territory of PT B2B clients with a personal NIF |
| `invoiceCae`       | string  | no  | the invoice's CAE                                         |

**Response:**

```json
{
  "vat":     { "rate": 0, "reason": 40, "text": "…" },
  "client":  { "country": "ES", "territory": null, "vies": 1 },
  "warning": null, "warningCode": null
}
```

| Field         | Notes                                                                    |
|---------------|--------------------------------------------------------------------------|
| `vat.rate`    | Percentage. **Always the normal rate of the applicable regime, or 0 when exempt** — reduced/intermediate bands are never returned; choosing those by item category is the caller's job |
| `vat.reason`  | Exemption reason as a **number** (e.g. `40`), `null` when VAT applies. The item field `vatExemptionReason` takes the `M`-code **string** (`"M40"`) — map it, checking `domain.md` |
| `vat.text`    | Explanation of the rate/exemption applied                                 |
| `client.territory` | Territory used, possibly resolved from the postal code               |
| `client.vies` | `0`/`1`. For EU countries other than PT this reflects a VIES validation; for PT and non-EU it only reflects the presence of a number. Falls back to the `clientHasVat` you sent if VIES is unavailable |

Handles OSS, reverse charge, intra-EU exemption and the Portuguese territories.
**402** when the account's plan doesn't include Auto IVA.

### `POST /vat/validate-client` — check a customer's VAT number

Request: `clientHasVat` (required), `clientCountry`, `clientVatNumber`.
Response: `{ "valid": boolean }`.

**Read the semantics before trusting it:** for EU countries other than PT it is a
real VIES lookup (cached 24h); **for PT and non-EU clients it only checks that a
number is present** — any non-empty value returns `true`. If VIES is unavailable
it returns the `clientHasVat` you sent.

---

## Transport documents (guias de transporte)

Same draft → issue lifecycle as invoices, under `/transport-documents`, and
equally irreversible once issued.

### `POST /transport-documents` — create draft

| Field               | Type   | Req | Notes                                                      |
|---------------------|--------|-----|------------------------------------------------------------|
| `movementType`      | enum   | yes | `GUIA_DE_REMESSA` \| `GUIA_DE_DEVOLUCAO` \| `GUIA_DE_TRANSPORTE` \| `GUIA_DE_ATIVOS_PROPRIOS` \| `GUIA_DE_CONSIGNACAO` |
| `movementDate`      | string | yes | ISO 8601 w/ timezone. **Must not be in the past** (today or later, `Europe/Lisbon`) — a guia must reach the AT before the goods move |
| `movementStartTime` | string | yes | loading time, ISO 8601 w/ timezone                          |
| `movementEndTime`   | string | no  | expected unloading; must be **after** `movementStartTime`   |
| `addressFrom`       | object | yes | loading place — see the address shape below                 |
| `addressTo`         | object | no  | unloading place, same shape                                 |
| `customer`          | object | yes* | recipient. **Required for every type except `GUIA_DE_ATIVOS_PROPRIOS`** — conditional, so it is not listed among the schema's unconditional required fields |
| `vehicleID`         | string | no  | e.g. `"AA-00-BB"`                                            |
| `items`             | array  | yes | elements of `{ id, quantity }`, same as an invoice           |

**Address shape** (`addressFrom` / `addressTo`):

| Field           | Type   | Req | Example                     |
|-----------------|--------|-----|-----------------------------|
| `name`          | string | yes | `"Armazém Lisboa"`          |
| `addressDetail` | string | yes | `"Rua da Prata, 12, 2.º"`   |
| `postalCode`    | string | yes | `"1100-052"`                |
| `city`          | string | yes | `"Lisboa"`                  |
| `country`       | string | yes | ISO 3166-1 alpha-2, `"PT"`  |
| `ref`           | string | no  | id of a saved location      |

**`customer` shape:** `{ "data": { … }, "ref": "<customer id>" }`. `data` is
required and holds the recipient snapshot — `name` (required), plus optional
`taxpayerNumber`, `address`, `postalCode`, `city`, `country`. **Only Portuguese
recipients (`country: "PT"`) are accepted.** `ref` optionally links the guia to an
existing customer from `GET /customers`; the snapshot is still required.

### The rest of the lifecycle

| Action        | Method & path                            | Notes                                  |
|---------------|------------------------------------------|----------------------------------------|
| Edit draft    | `PATCH /transport-documents/:id`         | 200; subset of the create fields       |
| Issue         | `POST /transport-documents/:id/issue`    | 200; reports to the AT. **400** if invalid or already issued |
| Cancel        | `POST /transport-documents/:id/cancel`   | 200. **400** if not issued or already cancelled |
| List          | `GET /transport-documents`               | `offset`, `limit`, `sort` (e.g. `movementDate:desc`), `search`, `movementType`, `issueStatus` (`DRAFT` \| `ISSUED` \| `CANCELED`) |
| Get one       | `GET /transport-documents/:id`           |                                        |
| PDF           | `GET /transport-documents/:id/pdf`       |                                        |
| Delete        | `DELETE /transport-documents/:id`        | drafts only                            |

---

## Bank (read-only)

### `GET /bank/connections`

No params. Array of `{ id, providerName, countryCode, status, createdAt,
updatedAt, maskedIbans[] }` (e.g. `"PT··3003"`).

### `GET /bank/transactions`

| Param          | Req | Notes                                             |
|----------------|-----|---------------------------------------------------|
| `connectionId` | yes | from `GET /bank/connections`                      |
| `page`         | no  | default 1                                         |
| `pageSize`     | no  | default 50                                        |
| `fromDate`     | no  | ISO 8601 w/ timezone                              |
| `toDate`       | no  | ISO 8601 w/ timezone                              |
| `searchString` | no  | free text (description, merchant, …)              |
| `direction`    | no  | `Income` \| `Expense` — **capitalised**, unlike the UPPER_SNAKE enums elsewhere |
| `types`        | no  | array of `Purchase` \| `Transfer` \| `MbwayTransfer` \| `Withdrawal` \| `Fee` \| `Other` |
| `language`     | no  | `pt` \| `en` — language of category names         |

**403** when the account has no accounting access.

---

## Idempotency

Every **write** endpoint (`POST` / `PATCH` / `DELETE` on customers, items,
invoices and transport documents) accepts an optional `Idempotency-Key` request
header. Without it, behaviour is unchanged.

| Aspect          | Value                                                              |
|-----------------|--------------------------------------------------------------------|
| Header          | `Idempotency-Key: <key>`                                            |
| Key format      | printable ASCII, no spaces, ≤ 128 chars (a UUID is ideal). Malformed → **400** |
| Replay          | same status + body as the first call, plus `Idempotent-Replayed: true` |
| In progress     | **409** with `Retry-After` — the only 409 that is a plain retry, with the *same* key |
| Outcome unknown / response expired | **409** without `Retry-After` — the write may already have happened. `GET` to check before retrying; reusing the key just 409s again, and a new key risks a duplicate. The `message` says which case it is |
| Key reused with a different body | **422**                                            |
| Retention       | 30 days                                                             |
| After a 5xx     | The key is **spent**, not released — only an early validation 400 frees it. Reusing it answers 409; `GET` to check whether the write landed, then resend with a new key if it did not |

Generate one key per logical operation and reuse it across ordinary retries (a
timeout, a dropped connection); a new key there defeats the mechanism. The
exception is a 409 reporting an unknown outcome — verify with a `GET` first.

Carry the key as a **literal value**, not in shell state: generate it once and
reuse the identical string on every retry of that operation. A command embedding
`$(uuidgen)` re-evaluates it on the retry and sends a different key, which is
what produces the duplicate. A key scoped to a single command is otherwise
desirable — it can't attach to the next, different write and earn a 422.

---

## Validation rules to remember

- **Strict whitelist**: any unknown property → 400. Send only documented fields.
- **Every date** (`date`, `dueDate`, `taxPointDate`, `payment.date`,
  `movementDate`, …) must be full ISO 8601 **with timezone**
  (`...T00:00:00.000Z`), not a bare `YYYY-MM-DD`.
- `items` must have 1–200 entries; each `quantity` ≥ 1.
- A discount needs both halves: a `discountType` without its matching
  `discountPercent`/`discountAmount` — or a value without the type — is a 400.
  `discountPercent` is 0–100 inclusive.
- `taxPointDate` must not be after the issue date.
- `null` is not a general "use the default": `taxPointDate` accepts it (clears the
  field), while `date` and `pay`'s `amount` reject it. To take a default, **omit
  the key**.
- `payment` is restricted to `INVOICE_RECEIPT` / `SIMPLIFIED_INVOICE` **on create
  only** (`POST /invoices`); on `PATCH /invoices/:id` that type check is not
  applied, so a `payment` is accepted regardless of document type.
- `seriesId`, when present, is never silently ignored: a malformed value (not a
  24-char Mongo id) → **400**, while a well-formed but unknown/wrong-account id →
  **404** (on both create and PATCH).
- Enum values are case-sensitive and exactly as written above. Note `payment.method`
  uses camelCase (`mbWay`, `bankTransfer`) while document types and vat rates use
  UPPER_SNAKE_CASE.
