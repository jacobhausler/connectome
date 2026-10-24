# Connect to Wide World Importers

Use this guide when the logical `wide_world_importers` connection is missing, expired, or points at the wrong source.

## Obtain the source and access

Ask the source owner for the SQL Server DNS name, TCP port, OLTP database name, authentication method, approved read-only identity, and TLS trust settings. Confirm any row-level role or session requirements with that owner. Do not put passwords or tokens in chat, SQL files, or this skill.

This example targets the original `WideWorldImporters` OLTP catalog. `WideWorldImportersDW` has a different model. Microsoft's [Full OLTP v1.0 release](https://github.com/microsoft/sql-server-samples/releases/tag/wide-world-importers-v1.0) provides a public sample backup, not a hosted database endpoint. For a local demonstration, have an authorized operator restore that backup to SQL Server and provide a read-only login. The [Microsoft sample repository](https://github.com/microsoft/sql-server-samples/tree/master/samples/databases/wide-world-importers) describes the sample and its prerequisites.

The examples need `SELECT` on `Sales.Invoices`, `Sales.InvoiceLines`, `Sales.CustomerTransactions`, `Sales.Customers`, `Application.TransactionTypes`, `Warehouse.StockItems`, `Warehouse.PackageTypes`, `Warehouse.StockItemStockGroups`, and `Purchasing.Suppliers`. Reading group labels also needs `Warehouse.StockGroups`. New schema investigation may need metadata visibility. The examples do not require procedure execution or database writes.

Check for `usql` first. If missing, use its [upstream installation instructions](https://github.com/xo/usql#installing) and a build with SQL Server support. Follow the host's software installation policy. Direct retrieval was tested with `usql 0.21.6` on SQL Server `17.0.5035.5`. Driver and authentication support belong to the installed client.

## Configure the logical connection

Reuse a valid connection owned by the current user. Otherwise, keep a native `usql` profile under the logical name `wide_world_importers`. The agent chooses a persistent private path outside the skill, repository, and synced or shared folders. The commands below use `.connectome/connections/wide_world_importers.yaml` in the user's home directory; choose another private location if that home is shared or synced.

For SQL username/password access, use the included helper. The agent fills in the nonsecret host, port, database, and local paths, then opens a user-visible terminal or helps the analyst run the prepared command in their own terminal. The analyst enters the username and password there with input hidden. Never request credentials in chat, tool arguments, environment variables, or a command line.

```text
sqlserver://WWI_SQL_HOST:1433?database=WideWorldImporters&encrypt=true&TrustServerCertificate=false
```

Use the owner's certificate trust settings. Put the catalog in the connection URL. Do not depend on a separate `USE` statement across client executions. For another authentication method, use the client's upstream native setup and retain that method; these optional helpers only handle username/password entry.

Explain once: the profile stores plaintext credentials in a separate local file with owner-only permissions. If that storage is unsuitable or cannot be protected, use an approved existing native connection or report the blocker.

On macOS or Linux, from this skill folder:

```bash
WWI_USQL_CONFIG="$HOME/.connectome/connections/wide_world_importers.yaml"
/bin/bash scripts/setup-connection.sh "$WWI_USQL_CONFIG" wide_world_importers \
  'sqlserver://WWI_SQL_HOST:1433?database=WideWorldImporters&encrypt=true&TrustServerCertificate=false'
```

On Windows, use Windows PowerShell 5.1 in the human's local terminal:

```powershell
$WWI_USQL_CONFIG = Join-Path $env:USERPROFILE '.connectome\connections\wide_world_importers.yaml'
& powershell.exe -NoProfile -File .\scripts\setup-connection.ps1 `
  $WWI_USQL_CONFIG wide_world_importers `
  'sqlserver://WWI_SQL_HOST:1433?database=WideWorldImporters&encrypt=true&TrustServerCertificate=false'
```

If execution policy blocks the script, report the restriction and use an approved native setup. Do not bypass policy. Both helpers preserve existing profiles without prompting. Do not run two renewals for one profile at once.

`WWI_USQL_CONFIG` is a nonsecret local path, not part of the shared folder. Record the chosen path locally so another session can reuse it. From the skill folder, check the database and execute a query directly. These single-line commands work in Bash and PowerShell with the variable set above.

```bash
usql -X -w --config "$WWI_USQL_CONFIG" wide_world_importers --set ON_ERROR_STOP=on -J -c 'SELECT DB_NAME() AS DatabaseName;'
usql -X -w --config "$WWI_USQL_CONFIG" wide_world_importers --set ON_ERROR_STOP=on -J -f sql/monthly-invoiced-sales.sql
```

Expect the owner's OLTP database name, normally `WideWorldImporters`. `-X` avoids startup-file surprises. `-w` makes a missing credential fail instead of opening an unattended prompt. Keep each example as one statement with a `Parameters` CTE. The tested `-f` path does not depend on variables or database selection set in a previous statement.

## Check visibility and renew access

Check the source's date range before assuming that example dates suit a new deployment.

```sql
SELECT MIN(InvoiceDate) AS FirstInvoiceDate,
       MAX(InvoiceDate) AS LastInvoiceDate,
       COUNT_BIG(*) AS VisibleInvoiceCount
FROM Sales.Invoices;
```

Confirm the customer visibility needed by your task. During this trial, the read-only role returned zero rows from `Sales.Customers` while exposing invoice and financial data. Customer labels, categories, and buying-group membership could not be established. A missing customer join is not evidence of an ungrouped customer. Report this access blocker and ask the owner for the approved scope. Preserve source policies. The account example retains financial rows and flags unavailable labels.

If credentials change or expire, rerun the same helper command with `--renew` on Bash or `-Renew` on Windows. Enter credentials locally again, then rerun the database and visibility checks. Do not repeat credential setup for a DNS, VPN, TLS, or permission failure; report the specific blocker. Keep the semantic context unchanged unless the source itself changed.

The Bash helper's hidden input, private permissions, reuse, renewal, and real authentication were exercised on Linux. Windows interactive input and ACLs, macOS behavior, and a real analyst's desktop session still require host verification. A shared folder contains these helpers and instructions, never a configured connection.
