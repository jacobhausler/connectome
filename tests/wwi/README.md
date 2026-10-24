# Wide World Importers proving case

This fixture uses Microsoft's original **WideWorldImporters Full OLTP v1.0** backup. It is a downloaded public sample restored locally. No tables were translated, synthesized, or replaced. The database and its runtime are test infrastructure; they are not dependencies of the Connectome factory.

WWI exercises order and invoice grains, customer versus billing-account relationships, financial transactions, product groups, and temporal reference data. These relationships make it useful for checking whether a generated skill helps an agent write new SQL.

## Restore the public sample

Use a development SQL Server instance that supports the Full sample's features. Follow Microsoft's [WWI installation instructions](https://learn.microsoft.com/en-us/sql/samples/wide-world-importers-oltp-install-configure?view=sql-server-ver17). Restore into a fresh database. Do not overwrite an existing database.

Download the [official backup](https://github.com/microsoft/sql-server-samples/releases/download/wide-world-importers-v1.0/WideWorldImporters-Full.bak) outside this repository. Its verified SHA-256 is:

```text
e842bad6ce02f74f166947e559dab1b476edd7eaae3da2ab9e3f522f1dd87124
```

The backup is 127,111,168 bytes. Its logical files are `WWI_Primary`, `WWI_UserData`, `WWI_Log`, and `WWI_InMemory_Data_1`. Use the server's own restore tooling to choose local destinations. The sample retains its [Microsoft MIT license](https://github.com/microsoft/sql-server-samples/blob/master/license.txt).

Create a dedicated reader through the database administrator's usual process. The trial account had `db_datareader` and `VIEW DEFINITION`, with INSERT, UPDATE, and DELETE denied. It was neither a server administrator nor database owner. Store its credentials outside the repository and expert skill.

The native connection URL must name `WideWorldImporters`. Use the server owner's TLS settings. The disposable localhost trial accepted its own temporary server certificate; that setting is not a remote deployment default.

## Verify the fixture

The recorded run on 2026-10-23 used usql 0.21.6 and SQL Server 2025 CU10, version 17.0.5035.5, on Ubuntu 24.04.3. The restored database retained compatibility level 130. Use `usql` directly with your private native configuration.

```sh
usql -X -w --config /absolute/private/config.yaml wide_world_importers \
	--set ON_ERROR_STOP=on -J -c 'SELECT DB_NAME() AS database_name, COUNT_BIG(*) AS invoices FROM Sales.Invoices;'
```

The original fixture returned these values:

| Check | Result |
| --- | ---: |
| Physical user tables, including history | 48 |
| Foreign keys | 98 |
| System-versioned tables | 17 |
| History tables | 17 |
| Memory-optimized tables | 2 |
| Invoices | 70,510 |
| Invoice lines | 228,265 |
| Orders | 73,595 |
| Order lines | 231,412 |
| Invoice date range | 2013-01-01 through 2016-05-31 |

A zero-row UPDATE under the reader failed with SQL Server error 229. A separate wrong-password check failed with error 18456. Both returned client exit code 1. These checks establish the tested account boundary, not a universal SQL safety mechanism.

## Reproduce the agent trials

Run Create with the factory, the read-only connection, a useful existing query, and Microsoft's [business description](https://learn.microsoft.com/en-us/sql/samples/wide-world-importers-what-is?view=sql-server-ver17) and [table catalog](https://learn.microsoft.com/en-us/sql/samples/wide-world-importers-oltp-database-catalog?view=sql-server-ver17). The first scope is monthly invoiced sales, related customer transactions, and useful product context.

For this public sample, documentation and explicit coordinator choices stand in for an SME. The example must label those choices and preserve unknowns. It does not establish that an actual analyst interview has succeeded.

Give a fresh consuming agent only the resulting source skill, its own connection, and a retrieval task that the creation agent has not seen. Establish expected values separately from raw source data, then compare the returned rows and their semantics. Keep the controls out of that agent's context.

The completed fresh-use task was:

> For each calendar month January through March 2016, retrieve invoiced merchandise value excluding tax, units, and distinct invoice count by the stock item's current usual supplier. Include unassigned suppliers if any. Exclude credit notes. Include the query and explain what each row and amount represents.

Extend a separate working copy to explain product stock groups and retrieve signed quantities for **Novelty Items in January 2016** without double counting. Check the affected query against source data and confirm that supported sales guidance survives. Keep historical membership and allocation policy open when the source does not answer them.

## Recorded results

| Trial | Checked result |
| --- | --- |
| Create | Four original SQL examples executed. All 5,386 January-March invoices reconciled to their customer financial events; monthly amounts and invoice counts matched. |
| Fresh use | A separate agent wrote the [supplier query](../../examples/wide-world-importers-expert/sql/monthly-supplier-sales.sql) without seeing expected results. All 21 supplier-month rows matched on keys, labels, exact decimal amounts, quantities, and distinct invoice counts. |
| Extend | A different agent reused the existing [product query](../../examples/wide-world-importers-expert/sql/product-sales.sql). Its January Novelty Items result had 91 unique month/item/package rows and 2,390 invoice lines. Signed quantities summed to 52,011, matching the independent control. |
| Access | All 12 Linux helper tests passed, including hidden terminal input, special characters and Unicode, permissions, reuse, renewal, cancellation, preservation of existing configuration, concurrent creation, and intervening edits. Two separate usql processes reused a saved profile to authenticate and return `SELECT 1`. |
| Packaging | Both skill folders passed frontmatter validation. Relative links resolved, standalone helper copies matched, and only intended source-skill files were included. |

The [supplier expectations](expected-suppliers.json) were derived independently from raw invoice headers, lines, current stock items, and suppliers. The control summed `Quantity * UnitPrice` with exact decimal arithmetic and counted invoice-ID sets within each supplier/month. It checked that this amount equalled `ExtendedPrice - TaxAmount` on all 17,184 selected lines and reconciled all 5,386 invoices to customer transactions. The creation and consuming agents did not receive those expectations.

| Invoice month | Amount excluding tax | Recorded quantity | Global distinct invoices |
| --- | ---: | ---: | ---: |
| January 2016 | 4,447,705.95 | 250,297 | 1,844 |
| February 2016 | 4,005,616.85 | 216,618 | 1,655 |
| March 2016 | 4,645,254.00 | 252,408 | 1,887 |

Amounts use source monetary units; no currency was established. Quantities mix products and package types. Supplier-level distinct invoice counts overlap: adding the 21 counts gives 12,755, while their invoice-ID union contains 5,386 invoices. The fresh agent explained these limitations and used current usual suppliers rather than claiming historical procurement attribution.

The [stock-group expectation](expected-novelty-items.json) selects each invoice line once through a set of current member stock items. It was also checked against a separate live `EXISTS` query. The Extend agent found that 83 of the group's 91 products also belonged to other groups. Joining the same lines to all memberships inflated the quantity checksum from 52,011 to 87,563. Its extension records membership grain, name resolution, and the non-temporal bridge without adding another packaged query. A missing group-name lookup must not become a null filter, because null intentionally selects all groups in the existing example.

## Customer visibility boundary

The original proposed handoff task grouped invoices by the recipient customer's buying group. The reader has SELECT on `Sales.Customers`, but the sample's enabled `Application.FilterCustomersBySalesTerritoryRole` policy exposes no customer rows to that identity. All 5,386 selected invoice headers have unresolved customer lookups under this access.

That task remains **blocked**. No expected buying-group table was fabricated, and hidden customer rows were not classified as ungrouped. No sales-territory role memberships were added. The skill preserves the restriction and tells the consuming agent to obtain approved access for customer labels or classifications. Financial retrievals remain usable; the account query retains transactions and flags unavailable customer labels.

## Run the access checks

From the repository root, run `python3 -m unittest discover -s tests -v`. The standard-library suite exercises real pseudo-terminal input on macOS/Linux. Python is a development-test dependency, not a requirement of either shipped helper.

Set `USQL_BIN` to an installed upstream binary to include its native profile-loading check. An optional `CONNECTOME_AUTH_FIXTURE` can name a private JSON file with `base_url`, `username`, and `password` for a disposable authorized database login; the live test uses it internally and suppresses credential values and client diagnostics. Without these inputs, the relevant integration checks are explicitly skipped. Keep the fixture outside the repository and never use production credentials for the public test fixture.

## Verification boundary

These checks cover one original restored fixture and specified dates. Those populations contain no credit notes, negative invoice quantities, or unassigned suppliers, so numeric equality does not exercise those branches. The queries preserve signs and explicit population filters, but the record makes no claim that absent cases were tested.

On 2026-10-24, the [Ubuntu/macOS CI run](https://github.com/jacobhausler/connectome/actions/runs/40091168591) passed all 10 core helper tests on both hosts. The initial macOS run exposed signed-byte expansion when encoding Unicode credentials; the fix keeps each encoded byte within 0–255 and the original round-trip tests now pass. CI explicitly skips the two optional client/database integration checks. A separate Linux rerun with the verified usql binary passed 11 tests, with only live database authentication skipped because the temporary fixture was no longer present. The live database results above remain the recorded 2026-10-23 run.

Windows PowerShell 5.1 input and ACL behavior remain unexecuted. A tool-driven terminal trial does not establish the experience in a particular desktop app, VPN access, a real analyst interview, or app restart behavior. Local persistence across two independent client processes was verified.
