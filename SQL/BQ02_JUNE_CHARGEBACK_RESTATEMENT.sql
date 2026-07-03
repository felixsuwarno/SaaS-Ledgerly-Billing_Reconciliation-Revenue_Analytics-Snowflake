USE DATABASE LEDGERLY;
USE SCHEMA STAGING;

-- How much prior-period revenue was restated by June 2024 chargebacks, and why?
-- means all lost disputes, where the money goes back to the customer, and the decision is made in June 2024,
-- but the invoices are "prior period" meaning they are billed before June 2024



CREATE OR REPLACE TABLE ANALYTICS.BQ02_JUNE_CHARGEBACK_RESTATEMENT AS

-- start investigating Balance Transactions table
-- filter all records whose reporting_category is "dispute"
-- and whose dates are in June 2024
WITH JUNE_CHARGEBACKS AS 
(
    SELECT
        BALANCE_SOURCE_ID           AS DISPUTE_ID,
        INVOICE_ID,
        CUSTOMER_ID,
        BALANCE_REPORTING_CATEGORY,
        BALANCE_AVAILABLE_ON,
        BALANCE_NET_CENTS
    FROM STG_BALANCE_TRANSACTIONS
    WHERE BALANCE_REPORTING_CATEGORY = 'dispute'
      AND BALANCE_AVAILABLE_ON >= '2024-06-01'
      AND BALANCE_AVAILABLE_ON  < '2024-07-01'
),

-- join to dispute table, the goal is to fetch the cause of the chargeback
TO_DISPUTES AS 
(
    SELECT
        JC.INVOICE_ID,
        JC.CUSTOMER_ID,
        JC.DISPUTE_ID,
        JC.BALANCE_REPORTING_CATEGORY,
        JC.BALANCE_AVAILABLE_ON,
        JC.BALANCE_NET_CENTS,
        D.DISPUTE_REASON
    FROM JUNE_CHARGEBACKS JC
    JOIN STG_DISPUTES D
        ON JC.DISPUTE_ID = D.DISPUTE_ID
),

-- join to invoice table to confirm invoices are prior period (Jan-May 2024)
PRIOR_PERIOD AS 
(
    SELECT
        TD.*,
        I.INVOICE_PERIOD_END
    FROM TO_DISPUTES TD
    JOIN STG_INVOICES I
        ON TD.INVOICE_ID = I.INVOICE_ID
    WHERE I.INVOICE_PERIOD_END >= '2024-01-01'
      AND I.INVOICE_PERIOD_END  < '2024-06-01'
),

-- aggregate to each invoice and report what happens to these invoices
-- how much money the company lost per invoice
-- the cause of the chargebacks
INVOICES_RESTATED AS 
(
    SELECT
        INVOICE_ID,
        CUSTOMER_ID,
        INVOICE_PERIOD_END,
        DISPUTE_REASON,
        SUM(BALANCE_NET_CENTS)           AS TOTAL_RESTATEMENT_NET_CENTS,
        COUNT(DISTINCT DISPUTE_ID)       AS DISPUTE_COUNT
    FROM PRIOR_PERIOD
    GROUP BY
        INVOICE_ID,
        CUSTOMER_ID,
        INVOICE_PERIOD_END,
        DISPUTE_REASON
),

summary_by_reason AS
(
    SELECT
        DISPUTE_REASON,
        COUNT(INVOICE_ID)               AS INVOICE_COUNT,
        SUM(TOTAL_RESTATEMENT_NET_CENTS) AS TOTAL_LOST_NET_CENTS
    FROM INVOICES_RESTATED
    GROUP BY
        DISPUTE_REASON
)

SELECT * FROM SUMMARY_BY_REASON;



