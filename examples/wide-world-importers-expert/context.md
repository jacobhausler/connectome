# Source context

This skill describes Microsoft's WideWorldImporters Full OLTP v1.0 sample on SQL Server. It does not describe WideWorldImportersDW or a PostgreSQL port. The evidence below was collected on 2026-10-23 from the original restored sample with read-only access. No real subject matter expert confirmed the business definitions.

## Invoice sales and customer activity

| Object | Row grain and keys | Retrieval meaning | Evidence |
| --- | --- | --- | --- |
| `Sales.Invoices` | One invoice header. Primary key `InvoiceID`. | `InvoiceDate` is the date raised. `CustomerID` identifies the invoice customer. `BillToCustomerID` identifies the billed account, which may be a head office. `IsCreditNote` identifies a credit note. | E2 |
| `Sales.InvoiceLines` | One supplied item line. Primary key `InvoiceLineID`. Many lines can refer to one `InvoiceID`. | `Description`, `Quantity`, `PackageTypeID`, and `UnitPrice` describe the supplied item. Use the line's values for the transaction. | E2 |
| `Sales.CustomerTransactions` | One customer financial transaction. Primary key `CustomerTransactionID`. `InvoiceID` is nullable and is not unique. | `TransactionTypeID` identifies the event through `Application.TransactionTypes`. `TransactionDate` is its own date basis. Invoice events use the invoice's bill-to account. Payments need not link to an invoice. | E2, E3, E4 |
| `Sales.Customers` | One current customer per primary key `CustomerID`. The table is system-versioned. | Use separate aliases for invoice customer and bill-to account. The current `BillToCustomerID` on the customer can differ from the role recorded on an older invoice. | E2 |

`Invoices.InvoiceID` to `InvoiceLines.InvoiceID` is a one-to-many join. `InvoiceLines.StockItemID` to current `Warehouse.StockItems.StockItemID` and each customer role to current `Sales.Customers.CustomerID` are many-to-one joins backed by primary and foreign keys. The inspected foreign keys were enabled and trusted. E2.

Aggregate invoice lines to one invoice before comparing invoice-level financial events. Joining a transaction amount to raw lines repeats that amount for every line. Joining facts by `CustomerID` repeats both kinds of events and confuses invoice and billing roles. E2 and the row grains above.

The fixture has one customer invoice transaction for each of its 70,510 invoices. Their invoice dates and transaction dates match. All linked transaction customers equal `Invoices.BillToCustomerID`, while 44,245 differ from `Invoices.CustomerID`. This is observed sample behavior, not a uniqueness constraint or a rule that dates always match. E4.

## Amounts, signs, dates, and units

| Field or convention | Meaning and limit | Evidence |
| --- | --- | --- |
| `InvoiceLines.ExtendedPrice` | Tax-inclusive line value. The invoice procedure calculates rounded quantity times unit price plus rounded tax. | E3 |
| `ExtendedPrice - TaxAmount` | Ex-tax invoiced line value. Sum this stored difference for the supplied examples. | E3, E6 |
| `CustomerTransactions.AmountExcludingTax`, `TaxAmount`, `TransactionAmount` | Respectively the ex-tax amount, tax, and tax-inclusive financial transaction amount. For invoice events, the procedure takes their values from invoice lines. | E2, E3 |
| Payment amounts | The sample's 26,637 `Customer Payment Received` events have negative `TransactionAmount`, zero ex-tax amount, zero tax, and null `InvoiceID`. Summing all customer transaction amounts measures signed financial activity, not invoiced sales. | E4 |
| Credit notes | Microsoft describes them as negative invoices. None of the inspected invoices or customer transactions is a credit note. Preserve stored signs and report the population. Do not negate amounts merely because `IsCreditNote = 1`. Negative-row behavior remains untested in this fixture. | E1, E4, E6 |
| `OutstandingBalance` | Current amount outstanding for the transaction. It is not the original transaction amount or a month-end historical snapshot. `CustomerTransactions` is not temporal. | E2 |
| `IsFinalized` | Computed from whether `FinalizationDate` is present. Its description says invoices, credits, and payments have been matched. Do not filter to finalized transactions for an invoiced-sales total. | E2 |
| Monetary units | Relevant amounts are `decimal(18,2)`. No currency code was established from the inspected sources. Report source monetary units until a suitable source confirms the currency. | E2, E6 |
| Quantity | Quantity supplied with the line's package type. Retain item and package context. Do not treat a mixed-product sum as a common physical unit. | E2 |
| Calendar dates | `InvoiceDate`, `TransactionDate`, and `FinalizationDate` are SQL `date` fields. Filter with an inclusive start and exclusive end. Do not apply a time-zone conversion to a date. | E2 |
| Fiscal year | Microsoft documents November 1 as the fiscal-year start. The examples group calendar months. Fiscal year naming by start or end year remains unspecified. | E1 |

The sample contains invoice dates from 2013-01-01 through 2016-05-31. Its age does not establish the freshness of another deployment. `usql` JSON represented `date` values with a midnight UTC suffix during inspection. The example outputs format dates as `YYYY-MM-DD` to keep their calendar-date meaning explicit. E4.

For this demonstration, signed stored invoice-line amounts define the retrieval convention. The examples expose ex-tax values, tax, and tax-inclusive billing separately. Their customer filter uses `Invoices.CustomerID`. These are coordinator choices for a fictional sample, not an approved accounting revenue policy. E6.

## Product context and historical attributes

`Warehouse.StockItems` has one current row per primary key `StockItemID`. It is system-versioned. `StockItemName` and current `UnitPrice` are master-data attributes. The invoice line retains the charged price and its supplied description, which may override the item name. Repricing old quantities with the current stock price changes the question. E2.

`InvoiceLines.PackageTypeID` joins to `Warehouse.PackageTypes.PackageTypeID`. Prefer that package for invoice quantities. The stock item's current `UnitPackageID`, `OuterPackageID`, and `QuantityPerOuter` describe its current usual packaging. A historical unit-conversion policy has not been established. E2.

`Warehouse.StockItems.SupplierID` identifies the item's current usual supplier. It has an enabled, trusted foreign key to the primary key `Purchasing.Suppliers.SupplierID`; the supplier table is system-versioned. Join current rows for an explicitly requested current usual-supplier breakdown. This does not establish the actual procurement source or the supplier at invoice time. An invoice may include items from several suppliers, so supplier-level distinct invoice counts overlap. The supplier example distinguishes missing lookup visibility from an unassigned supplier. E10.

The examples join current descriptive records. For an explicitly requested system-time snapshot, use `FOR SYSTEM_TIME AS OF` with one agreed UTC instant on each applicable temporal table. SQL Server selects the version valid at that instant. `FOR SYSTEM_TIME ALL` may return several versions per key and multiply a fact join. System time does not establish the correct business-effective time for an invoice. The fixture's historical dimension completeness has not been validated. E2 and E7.

## Stock groups

| Object | Row grain and keys | Retrieval meaning | Evidence |
| --- | --- | --- | --- |
| `Warehouse.StockGroups` | One current group per primary key `StockGroupID`; `StockGroupName` has an enabled unique index. The table is system-versioned. | Resolve a requested current group name to its ID in the connected deployment. | E9 |
| `Warehouse.StockItemStockGroups` | One current product-group membership per primary key `StockItemStockGroupID`. Enabled unique indexes enforce the pair `(StockItemID, StockGroupID)`. Enabled, trusted foreign keys lead to `StockItems` and `StockGroups`. | A product may belong to several groups. The bridge is non-temporal and has `LastEditedWhen`, but no membership validity interval. | E9 |

To list memberships, join `StockItems` to the bridge on `StockItemID`, then to `StockGroups` on `StockGroupID`; retain both IDs and current names. The result is one row per membership, not per product. Use a left join from the product catalogue when products without visible membership must remain in the result, and distinguish restricted visibility from absent membership. A group's existence does not establish that it has members. E9.

Resolve a group before setting the existing [product-sales query](sql/product-sales.sql) parameters:

```sql
SELECT StockGroupID, StockGroupName
FROM Warehouse.StockGroups
WHERE StockGroupName = N'Novelty Items';
```

Require one visible match. A failed lookup must not become a `NULL` group parameter: `NULL` disables the example's optional group filter. Use the returned ID with the requested half-open invoice-date range; do not assume IDs are portable between deployments. E9 and the query's parameter behavior.

The product-sales query already uses `EXISTS` to keep each eligible invoice line once. For the union of several groups, put the selected IDs inside the same `EXISTS` condition. A direct join to all memberships produces an invoice-line/group grain. It can be useful for a separate result per group, but those group totals overlap and cannot be added into a unique-product total. `SUM(DISTINCT Quantity)` is not a repair: distinct lines can have equal quantities. E9, E11.

Current membership is the agreed convention for the demonstrated January 2016 retrieval, not a real SME-approved classification policy. Temporal item or group labels do not reconstruct historical bridge membership, and `LastEditedWhen` alone cannot recover membership intervals or deleted links. No authoritative historical membership source or exclusive/allocation rule is known for this demonstration. Keep either question open when the requested analysis depends on it. E9, E12.

## Coverage and useful gaps

| Area | Status | Next useful work |
| --- | --- | --- |
| Monthly invoiced sales | Understood and checked for signed stored amounts on invoice date. | Recheck the reconciliation when data, roles, filters, or deployment changes. |
| Customer account activity | Financial totals are checked by transaction date and account ID. Customer labels are blocked by the tested role's visibility. | Obtain approved access before customer names, categories, or buying-group breakdowns. Establish payment allocation rules before historical receivables. |
| Product context | Understood for current item, package, and usual-supplier labels. | Establish historical attributes or physical-unit conversion only when the task needs it. |
| Stock groups | Understood for current membership lookup and filtering invoice lines without duplication. | Historical membership and exclusive/allocation policy remain unresolved. |
| Credit notes and refunds | Documented or discovered, but unexercised in this sample. | Obtain a real example or an approved test case before claiming their reconciliation behavior is proven. |
| Currency and revenue policy | Unresolved. | Ask the source owner for currency and the definition required by the downstream analysis. |
| Orders, purchasing transactions, inventory movements, sensors, and the warehouse database | Not assessed for retrieval. | Inspect the relevant objects and semantics when a concrete task needs them. |

## Evidence and scope

All inspection below ran on 2026-10-23. The source was the original Microsoft Full OLTP v1.0 sample restored on SQL Server `17.0.5035.5`. Read-only visibility is the checked scope. A different role, filtered view, sample edition, or altered deployment requires rechecking.

| ID | Source and checked scope |
| --- | --- |
| E1 | Microsoft's [business description](https://learn.microsoft.com/en-us/sql/samples/wide-world-importers-what-is?view=sql-server-ver17) and [OLTP catalog](https://learn.microsoft.com/en-us/sql/samples/wide-world-importers-oltp-database-catalog?view=sql-server-ver17). Supplied copies were read on 2026-10-23. They describe business flows, credit notes, the fiscal-year start, and table roles. They are public documentation, not SME testimony. |
| E2 | Read-only `sys` metadata for the objects named here. Checked column descriptions, types, nullability, primary keys, unique indexes, foreign keys, temporal status, and the computed `IsFinalized` expression. Extended-property reads used `class = 1` to exclude index descriptions. |
| E3 | Read-only inspection of the installed `Website.InvoiceCustomerOrders` definition. Checked the line amount calculation and customer-transaction insertion. The procedure was not executed. |
| E4 | Full relevant sample aggregate checks over 70,510 invoices, 228,265 lines, 97,147 customer transactions, and 227 current products. No line had a null unit price or a mismatch in `ExtendedPrice = Quantity * UnitPrice + TaxAmount`. No negative quantity, negative `ExtendedPrice`, or credit-note invoice was observed. Invoice-to-transaction counts, dates, customer roles, payment signs, and product-group multiplicity were checked. A per-payment check confirmed that all 26,637 payments had zero ex-tax value and tax, negative transaction amounts, and null invoice links. Customer rows were not included in this data-profile claim. |
| E5 | The four original SQL files executed through `usql 0.21.6` for 2016-01-01 through 2016-03-31. Monthly line totals and invoice counts matched a separate aggregation of customer invoice transactions in each of three months. All 5,386 invoices passed the reconciliation with no missing lines, missing or multiple financial events, amount differences, bill-to differences, or date differences. Product output had 681 unique month/item/package rows with visible labels and preserved each monthly amount. Account 1 produced six activity rows covering 1,764 transactions. Its invoice totals matched a separate invoice-line aggregation by `BillToCustomerID`, and its complete activity totals matched a transaction-only control. These are cross-table consistency controls, not an external accounting report. |
| E6 | Coordinator choices on 2026-10-23. Preserve stored signs, expose ex-tax and tax-inclusive values, use invoice customer for example sales filters, keep billing accounts separate, and leave currency unresolved. No real SME interview took place. |
| E7 | Microsoft's [temporal query documentation](https://learn.microsoft.com/en-us/sql/relational-databases/tables/temporal/query-data?view=sql-server-ver17), read on 2026-10-23. It specifies current-table reads, UTC `AS OF` input, and the possibility of multiple versions from temporal ranges. |
| E8 | The tested read-only role returned zero visible rows from `Sales.Customers`. All 1,764 account 1 transactions in the checked quarter had no visible customer label, while invoice and transaction controls matched. Current customer names, categories, and buying-group membership were not established under that role. |
| E9 | Extend inspection on 2026-10-23: read-only `sys` columns, temporal status, unique indexes, and foreign keys for the three product/group objects above, plus the invoice-line item/package foreign keys. Current data contained 227 visible products, 10 groups, and 442 memberships; 133 products had multiple groups, with a maximum of three. No duplicate product-group pairs, invisible bridge parents, or products without visible membership were observed. One visible group had no members. These are sample observations, not minimum-membership constraints. |
| E10 | A fresh consuming agent received only the original source skill, read-only access, and a new usual-supplier task. It inspected supplier metadata and executed the supplied example for January-March 2016 excluding credit notes. All 21 supplier-month rows matched independent raw-record controls on keys, labels, exact amounts, quantities, and distinct invoice counts. All 17,184 selected lines retained a single visible stock item and supplier. The independent control used quantity times charged unit price and reconciled every invoice to customer transactions. No credit notes, negative quantities, or unassigned suppliers occurred, so those branches remain numerically unexercised. |
| E11 | The unchanged product-sales statement was executed on 2026-10-23 with `StartDate = 20160101`, `EndDate = 20160201`, `StockItemID = NULL`, and the resolved `Novelty Items` group ID `1`. All 91 month/item/package rows, line counts, signed quantities, and three amount fields matched an independent derivation that aggregated all January invoice lines by item/package before joining the distinct current group item set. The result covered 2,390 distinct lines on 1,376 invoices, with visible labels and a mixed-unit quantity checksum of 52,011. Joining those same lines to all memberships instead produced 6,063 rows and a quantity checksum of 87,563. No negative quantities or credit-note lines were present. This verifies current-group selection and duplication behavior, not an external accounting total, common physical quantity, historical membership, or negative-row behavior. |
| E12 | Coordinator clarification on 2026-10-23: use current membership for the January demonstration. No authoritative historical membership source or exclusive/allocation policy is known. This is a demonstration choice, not real SME testimony. |

Customer visibility was restricted during this trial. Do not treat hidden customer records as absent customers or null buying-group membership. Preserve source policies and report the access blocker for customer-based labels and classifications. The account example retains financial rows with a left join and an explicit visibility flag. E8. The fresh-agent retrieval in E10 tests the source handoff; it does not establish a real analyst's desktop setup or interview experience.
