/*
Purpose. Retrieve financial activity for one customer account.
Parameters. Edit StartDate, EndDate, and AccountCustomerID. The sample uses public
account ID 1. Set AccountCustomerID to NULL only when all accounts are needed.
Grain. One row per month, account CustomerID, and transaction type.
Population. Customer transactions dated within the half-open range. No join to
Invoices removes events without InvoiceID. Invoice events belong to bill-to accounts.
Values. Source monetary units. TransactionAmount retains its sign. RemainingBalance
is the current outstanding balance of these period transactions, not month-end AR.
Caveats. Ex-tax plus tax is not a payment formula. The sample stores both as zero
for payments. Type labels and account names are current descriptions. A hidden
customer row leaves the current name null without removing its transactions.
CustomerLabelVisible = 0 requires an access limitation in the result note.
Checked scope. Account 1, January-March 2016; see ../context.md, E5 and E8.
*/
WITH Parameters AS (
    SELECT CAST('20160101' AS date) AS StartDate,
           CAST('20160401' AS date) AS EndDate,
           CAST(1 AS int) AS AccountCustomerID
)
SELECT CONVERT(char(10), DATEFROMPARTS(YEAR(ct.TransactionDate), MONTH(ct.TransactionDate), 1), 23) AS MonthStart,
       ct.CustomerID AS AccountCustomerID,
       c.CustomerName AS CurrentAccountName,
       CASE WHEN c.CustomerID IS NULL THEN 0 ELSE 1 END AS CustomerLabelVisible,
       ct.TransactionTypeID, tt.TransactionTypeName,
       COUNT_BIG(*) AS TransactionCount,
       SUM(ct.AmountExcludingTax) AS AmountExcludingTax,
       SUM(ct.TaxAmount) AS TaxAmount,
       SUM(ct.TransactionAmount) AS SignedTransactionAmount,
       SUM(ct.OutstandingBalance) AS CurrentRemainingBalanceOnPeriodTransactions
FROM Sales.CustomerTransactions AS ct
JOIN Application.TransactionTypes AS tt ON tt.TransactionTypeID = ct.TransactionTypeID
LEFT JOIN Sales.Customers AS c ON c.CustomerID = ct.CustomerID
CROSS JOIN Parameters AS p
WHERE ct.TransactionDate >= p.StartDate AND ct.TransactionDate < p.EndDate
  AND (p.AccountCustomerID IS NULL OR ct.CustomerID = p.AccountCustomerID)
GROUP BY DATEFROMPARTS(YEAR(ct.TransactionDate), MONTH(ct.TransactionDate), 1),
         ct.CustomerID, c.CustomerID, c.CustomerName, ct.TransactionTypeID, tt.TransactionTypeName
ORDER BY MonthStart, AccountCustomerID, ct.TransactionTypeID;
