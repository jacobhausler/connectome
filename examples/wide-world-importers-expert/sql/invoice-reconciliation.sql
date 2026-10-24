/*
Purpose. Compare invoice lines with the separate customer invoice financial events.
Parameters. Use the same StartDate, EndDate, and InvoiceCustomerID as the sales query.
Grain. One diagnostic summary over selected invoice headers, including headers with
no lines or no linked invoice or credit-note transaction.
Population. InvoiceDate selects headers. Financial events link by InvoiceID and type,
independent of TransactionDate. Payments without an InvoiceID are not invoice controls.
Caveats. Zero mismatches prove this comparison within this scope. They do not prove
accounting policy, payment allocation, a declared one-to-one relationship, or freshness.
Checked scope. January-March 2016, no credit notes; see ../context.md, E5.
*/
WITH Parameters AS (
    SELECT CAST('20160101' AS date) AS StartDate,
           CAST('20160401' AS date) AS EndDate,
           CAST(NULL AS int) AS InvoiceCustomerID
), SelectedInvoices AS (
    SELECT i.InvoiceID, i.InvoiceDate, i.BillToCustomerID
    FROM Sales.Invoices AS i
    CROSS JOIN Parameters AS p
    WHERE i.InvoiceDate >= p.StartDate AND i.InvoiceDate < p.EndDate
      AND (p.InvoiceCustomerID IS NULL OR i.CustomerID = p.InvoiceCustomerID)
), LineAmounts AS (
    SELECT i.InvoiceID, COUNT_BIG(il.InvoiceLineID) AS LineCount,
           SUM(il.ExtendedPrice - il.TaxAmount) AS AmountExcludingTax,
           SUM(il.TaxAmount) AS TaxAmount,
           SUM(il.ExtendedPrice) AS AmountIncludingTax
    FROM SelectedInvoices AS i
    LEFT JOIN Sales.InvoiceLines AS il ON il.InvoiceID = i.InvoiceID
    GROUP BY i.InvoiceID
), InvoiceEvents AS (
    SELECT ct.InvoiceID, COUNT_BIG(*) AS EventCount,
           SUM(ct.AmountExcludingTax) AS AmountExcludingTax,
           SUM(ct.TaxAmount) AS TaxAmount,
           SUM(ct.TransactionAmount) AS AmountIncludingTax,
           SUM(CASE WHEN ct.CustomerID <> i.BillToCustomerID THEN 1 ELSE 0 END) AS WrongAccountCount,
           SUM(CASE WHEN ct.TransactionDate <> i.InvoiceDate THEN 1 ELSE 0 END) AS DifferentDateCount
    FROM SelectedInvoices AS i
    JOIN Sales.CustomerTransactions AS ct ON ct.InvoiceID = i.InvoiceID
    JOIN Application.TransactionTypes AS tt ON tt.TransactionTypeID = ct.TransactionTypeID
    WHERE tt.TransactionTypeName IN (N'Customer Invoice', N'Customer Credit Note')
    GROUP BY ct.InvoiceID
)
SELECT COUNT_BIG(*) AS InvoiceCount,
       COALESCE(SUM(CASE WHEN l.LineCount = 0 THEN 1 ELSE 0 END), 0) AS InvoicesWithoutLines,
       COALESCE(SUM(CASE WHEN e.EventCount IS NULL THEN 1 ELSE 0 END), 0) AS InvoicesWithoutFinancialEvent,
       COALESCE(SUM(CASE WHEN e.EventCount > 1 THEN 1 ELSE 0 END), 0) AS InvoicesWithMultipleFinancialEvents,
       COALESCE(SUM(CASE WHEN l.AmountExcludingTax <> e.AmountExcludingTax
                              OR l.TaxAmount <> e.TaxAmount
                              OR l.AmountIncludingTax <> e.AmountIncludingTax
                         THEN 1 ELSE 0 END), 0) AS InvoicesWithDifferentAmounts,
       COALESCE(SUM(e.WrongAccountCount), 0) AS EventsWithDifferentBillToAccount,
       COALESCE(SUM(e.DifferentDateCount), 0) AS EventsOnDifferentDate
FROM SelectedInvoices AS i
JOIN LineAmounts AS l ON l.InvoiceID = i.InvoiceID
LEFT JOIN InvoiceEvents AS e ON e.InvoiceID = i.InvoiceID;
