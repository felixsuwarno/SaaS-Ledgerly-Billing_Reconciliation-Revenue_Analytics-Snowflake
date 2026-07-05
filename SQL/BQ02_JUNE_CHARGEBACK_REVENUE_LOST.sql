USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

-- ============================================================
-- BQ02: How much old invoice revenue did we lose to June chargebacks, and why?
-- Old invoice revenue = invoices whose invoice period ended before June 2024.
-- June chargebacks = dispute balance transaction rows that became available in June 2024.
-- The dispute reason explains why the revenue was lost.
-- ============================================================

-- CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ02_JUNE_CHARGEBACK_REVENUE_LOST AS

-- Step 1: Find June chargeback money movement.

-- The business question asks how much old invoice revenue we lost to June chargebacks, 
-- so the first thing we need to identify is the June chargebacks. 

-- In this dataset, chargebacks are found in STG_BALANCE_TRANSACTIONS, 
-- where BALANCE_REPORTING_CATEGORY = 'dispute'. 

-- Then we apply the June requirement by keeping only rows where BALANCE_AVAILABLE_ON falls from June 1, 
-- 2024 through June 30, 2024. 

-- After this step, each row is one June chargeback balance transaction tied to an invoice and customer.

WITH june_chargebacks AS
(
    SELECT
        BALANCE_SOURCE_ID AS DISPUTE_ID,
        INVOICE_ID,
        CUSTOMER_ID,
        BALANCE_REPORTING_CATEGORY,
        BALANCE_AVAILABLE_ON,
        BALANCE_NET_CENTS
    FROM LEDGERLY.STAGING.STG_BALANCE_TRANSACTIONS
    WHERE BALANCE_REPORTING_CATEGORY = 'dispute'
        AND BALANCE_AVAILABLE_ON >= '2024-06-01'
        AND BALANCE_AVAILABLE_ON < '2024-07-01'
),


-- Step 2: Add dispute reasons to June chargebacks.
-- The June chargeback rows from Step 1 tell us which invoice and customer were hit, 
-- but they do not tell us why the chargeback happened. 

-- The “why” part of the question lives in STG_DISPUTES, specifically in DISPUTE_REASON. 

-- This step joins the June chargeback rows to STG_DISPUTES using DISPUTE_ID, 
-- because Step 1 renamed BALANCE_SOURCE_ID into the dispute ID used for matching. 

-- After this step, each June chargeback row has the dispute reason attached.

to_disputes AS
(
    SELECT
        JC.DISPUTE_ID,
        JC.INVOICE_ID,
        JC.CUSTOMER_ID,
        JC.BALANCE_AVAILABLE_ON,
        JC.BALANCE_NET_CENTS,
        D.DISPUTE_REASON
    FROM june_chargebacks AS JC
    INNER JOIN LEDGERLY.STAGING.STG_DISPUTES AS D
        ON JC.DISPUTE_ID = D.DISPUTE_ID
),

-- Step 3: Keep only June chargebacks tied to old invoices.

-- The business question asks about old invoice revenue, 
-- so we need to confirm whether the invoice tied to each June chargeback belongs to a billing period before June 2024. 

-- That information lives in STG_INVOICES, specifically in INVOICE_PERIOD_END. 

-- This step joins the June chargeback rows from Step 2 to STG_INVOICES using INVOICE_ID, 
-- then keeps only invoices where INVOICE_PERIOD_END falls from January 1, 2024 through May 31, 2024. 

-- After this step, every remaining row is a June chargeback with 
-- its dispute reason attached and proof that the chargeback hit old invoice revenue.

old_invoice_chargebacks AS
(
    SELECT
        TD.DISPUTE_ID,
        TD.INVOICE_ID,
        TD.CUSTOMER_ID,
        I.INVOICE_PERIOD_END,
        TD.BALANCE_AVAILABLE_ON,
        TD.BALANCE_NET_CENTS,
        TD.DISPUTE_REASON
    FROM to_disputes AS TD
    INNER JOIN LEDGERLY.STAGING.STG_INVOICES AS I
        ON TD.INVOICE_ID = I.INVOICE_ID
    WHERE I.INVOICE_PERIOD_END >= '2024-01-01'
        AND I.INVOICE_PERIOD_END < '2024-06-01'
),


-- Step 4: Summarize old invoice revenue lost by dispute reason.

-- Step 3 already has the correct chargeback rows for the business question: 
-- June chargebacks tied to old invoices, 
-- with dispute reasons attached. 

-- Because the final question asks “how much” and “why,” 
-- this step groups the rows by DISPUTE_REASON. 

-- It counts distinct INVOICE_ID into INVOICE_COUNT, which shows how many old invoices were affected by each reason. 
-- It also adds the chargeback amounts into TOTAL_LOST_NET_CENTS, 
-- which shows how much old invoice revenue was lost for each reason.

summary_by_reason AS
(
    SELECT
        DISPUTE_REASON,
        COUNT(DISTINCT INVOICE_ID) AS INVOICE_COUNT,
        ABS(SUM(BALANCE_NET_CENTS)) AS TOTAL_LOST_NET_CENTS
    FROM old_invoice_chargebacks
    GROUP BY DISPUTE_REASON
    ORDER BY INVOICE_COUNT DESC
)

SELECT *
FROM summary_by_reason;