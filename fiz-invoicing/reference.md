# FIZ Public API — Full Reference

Complete field reference for the endpoints used to issue invoices. Base URL:
`https://api.fiz.co`. Auth header: `x-api-key`. All requests except the docs
require it.

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
| `termsOfPayment`          | string  | no       | `"Pagamento a 30 dias"`                                 |
| `isAutoVATEnabled`        | boolean | no       | default `false`                                         |
| `withholdingTaxAvailable` | boolean | no       | default `false`                                         |
| `withholdingTaxPercent`   | number  | no       | ≥ 0, e.g. `25`                                          |
| `withholdingTaxType`      | enum    | no       | `IRS` \| `IRC` \| `IS`                                  |
| `withholdingTaxReason`    | string  | no       | free text                                               |

Response: the created item, including `id` (use in the invoice `items` array).

### `GET /items`, `GET /items/:id`, `PATCH /items/:id`, `DELETE /items/:id`

List supports `?search=`. `PATCH` accepts any subset of the create fields.

---

## Invoices

### `POST /invoices` — create draft

| Field        | Type     | Required | Notes                                                     |
|--------------|----------|----------|-----------------------------------------------------------|
| `dueDate`    | string   | **yes**  | ISO 8601 w/ timezone, e.g. `2026-07-18T00:00:00.000Z`     |
| `cae`        | string   | **yes**  | Portuguese economic activity code, e.g. `"62010"`         |
| `type`       | enum     | **yes**  | see Document types below                                  |
| `customerId` | string   | **yes**  | customer `id`                                             |
| `items`      | array    | **yes**  | ≥ 1 element of `{ id: string, quantity: number ≥ 1 }`     |
| `summary`    | object   | no       | global discount, see below                                |
| `payment`    | object   | no       | only for `INVOICE_RECEIPT` / `SIMPLIFIED_INVOICE`         |

The API sets `date` (now) and `currency` (`EUR`) itself — do not send them.

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

### `POST /invoices/:id/issue` — issue (finalize)

No body. Returns the invoice with the official `number`, `status: ISSUED`, and a
`syncWithAt` block:

| Field         | Type    | Notes                                            |
|---------------|---------|--------------------------------------------------|
| `status`      | enum    | `SYNCED` \| `PROCESSING` \| `FAILED`             |
| `atCode`      | string? | tax-authority code                               |
| `atMessage`   | string  | human-readable sync message                      |
| `systemError` | string? | internal error if any                            |
| `isRetriable` | boolean | whether issuing can be retried                   |
| `updatedAt`   | string  | timestamp                                        |

If `status` is `FAILED`, surface `atMessage` and `isRetriable` to the user.

### `GET /invoices` — list

Query params: `offset` (default 0), `limit` (default 20), `sort`
(e.g. `date:desc`), `search`, `documentType`, `status`
(`DRAFT`/`ISSUED`/`PAID`/`CANCELED`/`CREATED`/`SCHEDULED`), `aggregatedStatus`,
`date`, `dueDate`, `fromDate`, `toDate`, `currency`, `description`, `notes`,
`filterAllStatusesByDate`, `includeATInvoices`.

### `GET /invoices/:id` — get one

Returns the full invoice: `number`, `atcud`, `status`, totals in `summary`,
`items`, `customer`, `issuer`, `qrCode`, `syncWithAt`, etc.

### `GET /invoices/:id/pdf` — download PDF

Query params: `format` (`A4` | `RECEIPT`), `isDuplicate` (boolean),
`templateId` (string). Returns `{ id, name, url }`.

### `DELETE /invoices/:id`

Deletes the invoice (used for drafts). Returns `{ id, createdAt }`.

---

## Validation rules to remember

- **Strict whitelist**: any unknown property → 400. Send only documented fields.
- `dueDate` / `payment.date` must be full ISO 8601 **with timezone**
  (`...T00:00:00.000Z`), not a bare `YYYY-MM-DD`.
- `items` must have at least one entry; each `quantity` ≥ 1.
- `payment` is restricted to `INVOICE_RECEIPT` / `SIMPLIFIED_INVOICE`.
- Enum values are case-sensitive and exactly as written above. Note `payment.method`
  uses camelCase (`mbWay`, `bankTransfer`) while document types and vat rates use
  UPPER_SNAKE_CASE.
