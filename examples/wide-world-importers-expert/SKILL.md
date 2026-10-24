---
name: wide-world-importers-expert
description: >-
  Retrieve invoiced sales, customer financial activity, and product context from
  Microsoft's WideWorldImporters OLTP SQL Server database. Use for monthly invoice
  totals, customer account activity, invoice-to-transaction reconciliation,
  current stock-group membership, or product and supplier sales inputs to another analysis.
---

# Wide World Importers expert

Use the logical connection `wide_world_importers` with `usql` directly. Establish or renew your own access with [setup](setup.md) only when needed.

Read [source context](context.md) before writing unfamiliar SQL. It records grains, customer roles, amount definitions, date bases, evidence, and open questions.

## Retrieve the requested data

Start from a relevant example and edit its one-row `Parameters` CTE. For a new question, adapt the selected fields, joins, and grouping after checking the relevant source context and metadata. Each file is one read-only T-SQL statement.

- [Monthly invoiced sales](sql/monthly-invoiced-sales.sql) returns signed invoice-line values by calendar month.
- [Customer account activity](sql/customer-account-activity.sql) keeps invoices and payments visible by transaction type.
- [Product sales](sql/product-sales.sql) adds current product and package context. For group questions, first read [stock groups](context.md#stock-groups) to resolve the filter and membership basis.
- [Sales by usual supplier](sql/monthly-supplier-sales.sql) retrieves a current supplier breakdown, with invoice counts that can overlap across suppliers.
- [Invoice reconciliation](sql/invoice-reconciliation.sql) checks invoice-line totals against related customer transactions.

Use a date range and selected columns. Inspect join cardinality before adding another fact or a many-to-many classification. Keep the invoice customer distinct from the billing account. Clarify the customer role when the requested result depends on it.

Check customer visibility before retrieving customer names, categories, or buying groups. The tested role could read financial facts but no customer rows. If that restriction applies, report the access blocker for that part of the task. An unmatched lookup does not establish an ungrouped customer.

Preserve source signs. Keep ex-tax sales, tax, tax-inclusive billing, and customer payments separately labelled. Do not infer a currency code from the business location. Do not infer historical receivables from the current outstanding balances.

Return the selected fields, units, row grain, date basis, population, source query, and meaningful limitations with the retrieved data. Identify current versus historical descriptive attributes. Let the consuming agent decide the downstream analysis.

## Keep useful learning

After meaningful use, check whether the work established a reusable correction or filled a recorded gap. Update the affected context or SQL with the evidence, date, and checked scope. Keep unresolved observations as questions. If nothing changed, do nothing.

For a substantive improvement, explain its effect and ask whether the user wants to share it through their separate process. Keep submission, review, merging, and scheduling outside this source skill.
