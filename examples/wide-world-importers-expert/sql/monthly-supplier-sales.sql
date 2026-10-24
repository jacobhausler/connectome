/*
Purpose: Retrieve monthly invoiced merchandise value, recorded units, and distinct
invoice counts by the stock item's current usual supplier for downstream analysis.
Grain: One calendar month and current usual supplier, with visibility/assignment
status kept separate so an inaccessible lookup is not labelled unassigned.
Population: Invoice lines with InvoiceDate >= 2016-01-01 and < 2016-04-01,
excluding credit notes. Only supplier/month groups with invoice lines are returned.
Parameters: Edit StartDate and EndDate in the one-row Parameters CTE.
Amounts: SUM(ExtendedPrice - TaxAmount), in source monetary units; currency unknown.
Units: SUM(Quantity) as recorded for each line's supplied package, across products.
These are mixed package counts, not a normalized common physical unit.
Invoice count: Distinct InvoiceID within this supplier/month; nonadditive across
suppliers because one invoice may contain items from several usual suppliers.
Attribution: Current Warehouse.StockItems.SupplierID; both stock item and supplier
master records are current. This is not the historical supplier on the invoice date.
Left joins preserve unassigned or unavailable lookups if any occur.
Checked scope: January-March 2016; see ../context.md, E10.
*/
WITH Parameters AS (
    SELECT CAST('20160101' AS date) AS StartDate,
           CAST('20160401' AS date) AS EndDate
), LinePopulation AS (
    SELECT DATEFROMPARTS(YEAR(i.InvoiceDate), MONTH(i.InvoiceDate), 1) AS MonthStart,
           i.InvoiceID,
           si.SupplierID AS CurrentUsualSupplierID,
           s.SupplierName AS CurrentUsualSupplierName,
           CASE
               WHEN si.StockItemID IS NULL THEN 'Stock item unavailable'
               WHEN si.SupplierID IS NULL THEN 'Unassigned'
               WHEN s.SupplierID IS NULL THEN 'Supplier label unavailable'
               ELSE 'Assigned'
           END AS SupplierAssignmentStatus,
           il.Quantity,
           il.ExtendedPrice - il.TaxAmount AS LineAmountExcludingTax
    FROM Sales.Invoices AS i
    JOIN Sales.InvoiceLines AS il ON il.InvoiceID = i.InvoiceID
    LEFT JOIN Warehouse.StockItems AS si ON si.StockItemID = il.StockItemID
    LEFT JOIN Purchasing.Suppliers AS s ON s.SupplierID = si.SupplierID
    CROSS JOIN Parameters AS p
    WHERE i.InvoiceDate >= p.StartDate AND i.InvoiceDate < p.EndDate
      AND i.IsCreditNote = 0
)
SELECT CONVERT(char(10), MonthStart, 23) AS MonthStart,
       CurrentUsualSupplierID,
       CurrentUsualSupplierName,
       SupplierAssignmentStatus,
       SUM(LineAmountExcludingTax) AS InvoicedMerchandiseExcludingTax,
       SUM(CONVERT(bigint, Quantity)) AS UnitsAsRecorded,
       COUNT(DISTINCT InvoiceID) AS DistinctInvoiceCount
FROM LinePopulation
GROUP BY MonthStart, CurrentUsualSupplierID, CurrentUsualSupplierName, SupplierAssignmentStatus
ORDER BY MonthStart, CurrentUsualSupplierID, SupplierAssignmentStatus;
