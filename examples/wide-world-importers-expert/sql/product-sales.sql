/*
Purpose. Retrieve invoiced product values with current product and package context.
Parameters. Edit StartDate, EndDate, and optional StockItemID or StockGroupID.
Grain. Calendar month, StockItemID, and the invoice line's PackageTypeID.
Population. Signed invoice lines in the half-open InvoiceDate range. A stock-group
filter uses current membership and EXISTS so products in other groups are not repeated.
Values. Source monetary units. Quantity is supplied quantity for this item and package.
Caveats. Product names are current. Amounts come from invoice lines. Group totals
overlap if this query is rerun for several groups and then added together.
Checked scope. All products, January-March 2016; Novelty Items, January 2016.
See ../context.md, E5 and E11.
*/
WITH Parameters AS (
    SELECT CAST('20160101' AS date) AS StartDate,
           CAST('20160401' AS date) AS EndDate,
           CAST(NULL AS int) AS StockItemID,
           CAST(NULL AS int) AS StockGroupID
)
SELECT CONVERT(char(10), DATEFROMPARTS(YEAR(i.InvoiceDate), MONTH(i.InvoiceDate), 1), 23) AS MonthStart,
       il.StockItemID, si.StockItemName AS CurrentStockItemName,
       il.PackageTypeID, pt.PackageTypeName,
       COUNT_BIG(*) AS InvoiceLineCount,
       SUM(CONVERT(bigint, il.Quantity)) AS SuppliedQuantity,
       SUM(il.ExtendedPrice - il.TaxAmount) AS InvoicedAmountExcludingTax,
       SUM(il.TaxAmount) AS InvoicedTaxAmount,
       SUM(il.ExtendedPrice) AS InvoicedAmountIncludingTax
FROM Sales.Invoices AS i
JOIN Sales.InvoiceLines AS il ON il.InvoiceID = i.InvoiceID
LEFT JOIN Warehouse.StockItems AS si ON si.StockItemID = il.StockItemID
LEFT JOIN Warehouse.PackageTypes AS pt ON pt.PackageTypeID = il.PackageTypeID
CROSS JOIN Parameters AS p
WHERE i.InvoiceDate >= p.StartDate AND i.InvoiceDate < p.EndDate
  AND (p.StockItemID IS NULL OR il.StockItemID = p.StockItemID)
  AND (p.StockGroupID IS NULL OR EXISTS (
      SELECT 1 FROM Warehouse.StockItemStockGroups AS sg
      WHERE sg.StockItemID = il.StockItemID AND sg.StockGroupID = p.StockGroupID
  ))
GROUP BY DATEFROMPARTS(YEAR(i.InvoiceDate), MONTH(i.InvoiceDate), 1),
         il.StockItemID, si.StockItemName, il.PackageTypeID, pt.PackageTypeName
ORDER BY MonthStart, il.StockItemID, il.PackageTypeID;
