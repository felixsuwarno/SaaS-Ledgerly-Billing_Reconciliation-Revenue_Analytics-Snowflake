USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

-- ============================================================
-- BQ06A: PAID_SIGNUP_COHORT_BY_CUSTOMER
-- Purpose: Find each customer's first paid invoice date
--          and assign them to a cohort month.
--          Only customers who first paid before 2024 are kept.
--          Canceled subscriptions are NOT removed here —
--          churn must stay in the base for NRR to be accurate.
--          The real NRR base filter is STARTING_MRR_CENTS > 0 in BQ06B.
-- Grain: one row per customer
-- ============================================================

CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ06A_PAID_SIGNUP_COHORT_BY_CUSTOMER AS


-- Step 1: invoices_filtered
-- Start from STG_INVOICES because paid signup has to be proven from invoice payment data. 
-- This step keeps only paid invoice rows. 
-- Use INVOICE_PAID = TRUE and INVOICE_STATUS = 'paid'. 
-- Keep only CUSTOMER_ID and INVOICE_CREATED, 
-- because this table only needs to find when each customer first paid.

WITH invoices_filtered AS
(
    -- Step 1: Filter STG_INVOICES to paid invoices only
    SELECT
        CUSTOMER_ID,
        INVOICE_CREATED

    FROM LEDGERLY.STAGING.STG_INVOICES

    WHERE INVOICE_PAID   = TRUE
      AND INVOICE_STATUS = 'paid'
),


-- Step 2: invoices_first_paid
-- Group the paid invoice rows by CUSTOMER_ID. For each customer, 
-- take the earliest INVOICE_CREATED date using MIN(). 
-- This creates FIRST_PAID_INVOICE_DATE, 
-- which represents the first paid invoice date for that customer.

invoices_first_paid AS
(
    -- Step 2: Per CUSTOMER_ID, find the earliest paid invoice date
    SELECT
        CUSTOMER_ID,
        MIN(INVOICE_CREATED) AS FIRST_PAID_INVOICE_DATE

    FROM invoices_filtered

    GROUP BY
        CUSTOMER_ID
),



-- Step 3: invoices_cohort_month
-- Convert FIRST_PAID_INVOICE_DATE into a month. 
-- This creates PAID_SIGNUP_COHORT_MONTH. 
-- Customers whose first paid invoice falls in the same month 
-- are grouped into the same paid signup cohort.

invoices_cohort_month AS
(
    -- Step 3: Convert first paid invoice date into cohort month
    SELECT
        CUSTOMER_ID,
        FIRST_PAID_INVOICE_DATE,
        DATE_TRUNC('month', FIRST_PAID_INVOICE_DATE::DATE) AS PAID_SIGNUP_COHORT_MONTH

    FROM invoices_first_paid
),

-- Step 4: invoices_cohort_pre_2024
-- Keep only customers whose PAID_SIGNUP_COHORT_MONTH is before 2024-01-01. 
-- This removes customers who first became paid during 2024, 
-- because 2024 NRR should only measure customers who already existed in the paid base before the 2024 
-- measurement period.

-- Key columns: CUSTOMER_ID, FIRST_PAID_INVOICE_DATE, PAID_SIGNUP_COHORT_MONTH

invoices_cohort_pre_2024 AS
(
    -- Step 4: Keep only customers whose first payment happened before 2024
    SELECT
        CUSTOMER_ID,
        FIRST_PAID_INVOICE_DATE,
        PAID_SIGNUP_COHORT_MONTH

    FROM invoices_cohort_month

    WHERE PAID_SIGNUP_COHORT_MONTH < '2024-01-01'
)

SELECT * FROM invoices_cohort_pre_2024;