/*
Purpose. Retrieve signed invoiced values for another analysis.
Parameters. Edit StartDate, EndDate, and optional InvoiceCustomerID below.
Grain. One row per calendar month with invoice lines in the selected population.
Population. All invoice and credit-note lines in the half-open InvoiceDate range.
Values. Source monetary units. Ex-tax, tax, and tax-inclusive values stay separate.
Caveats. Preserve stored signs. Months without lines are absent. No payment or
finalization filter applies. Customer means the invoice customer, not the bill-to
account. The reconciliation query detects headers without lines.
Checked scope. January-March 2016, no credit notes; see ../context.md, E5.
*/
WITH Parameters AS (
    SELECT CAST('20160101' AS date) AS StartDate,
           CAST('20160401' AS date) AS EndDate,
           CAST(NULL AS int) AS InvoiceCustomerID
), InvoiceAmounts AS (
    SELECT i.InvoiceID, i.InvoiceDate, i.IsCreditNote,
           SUM(il.ExtendedPrice - il.TaxAmount) AS AmountExcludingTax,
           SUM(il.TaxAmount) AS TaxAmount,
           SUM(il.ExtendedPrice) AS AmountIncludingTax
    FROM Sales.Invoices AS i
    JOIN Sales.InvoiceLines AS il ON il.InvoiceID = i.InvoiceID
    CROSS JOIN Parameters AS p
    WHERE i.InvoiceDate >= p.StartDate AND i.InvoiceDate < p.EndDate
      AND (p.InvoiceCustomerID IS NULL OR i.CustomerID = p.InvoiceCustomerID)
    GROUP BY i.InvoiceID, i.InvoiceDate, i.IsCreditNote
)
SELECT CONVERT(char(10), DATEFROMPARTS(YEAR(InvoiceDate), MONTH(InvoiceDate), 1), 23) AS MonthStart,
       COUNT_BIG(*) AS InvoiceCount,
       SUM(CONVERT(bigint, IsCreditNote)) AS CreditNoteCount,
       SUM(AmountExcludingTax) AS InvoicedAmountExcludingTax,
       SUM(TaxAmount) AS InvoicedTaxAmount,
       SUM(AmountIncludingTax) AS InvoicedAmountIncludingTax
FROM InvoiceAmounts
GROUP BY DATEFROMPARTS(YEAR(InvoiceDate), MONTH(InvoiceDate), 1)
ORDER BY MonthStart;
