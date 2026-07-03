USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

-- ============================================================
-- BQ06B: CUSTOMER_NRR_BASE_2024
-- Purpose: Join BQ06A to BQ03A (aggregated to customer level)
--          to get starting and ending MRR for each customer
--          in the NRR base.
-- Grain: one row per customer
-- ============================================================

-- Additional notes as a reminder about BQ03A
-- BQ03A — SUBSCRIPTION_MRR_BY_MONTH_2024 (already built)
-- Now that we know which customers had their first payment before 2024, 
-- we need to track how their MRR moved throughout the year. That answer lives in BQ03A.

-- BQ03A originates from the subscription events table, which records five types of events: 
-- created, upgraded, downgraded, canceled, and reactivated. 

-- Each of these events carries a plan amount. 
-- BQ03A takes those events and fans them out across every month from December 2023 through December 2024 — 
-- assigning the correct plan amount to each month based on which event was active at that time.

-- BQ03A is MRR contribution by subscription event and reporting month.
-- Before joining to the customer cohort table, its MRR must be summed to customer level. 
-- A customer with multiple subscriptions needs their combined MRR, not individual subscription rows. 
-- To get there, we aggregate BQ03A by CUSTOMER_ID and join to BQ06A — and that is BQ06B.
-- Key columns needed: CUSTOMER_ID, MRR_MONTH, MRR_CENTS.


-- Step 1: bq03a_start_aggregated
-- Start from BQ03A_SUBSCRIPTION_MRR_BY_MONTH_2024 and keep only rows where MRR_MONTH = '2023-12-01'. 
-- BQ03A is below the customer grain, so this step groups by CUSTOMER_ID and sums MRR_CENTS. 
-- This creates STARTING_MRR_CENTS, which shows how much recurring revenue each customer contributed 
-- at the start of the 2024 measurement period.


CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ06B_CUSTOMER_NRR_BASE_2024 AS

WITH bq03a_start_aggregated AS
(
    -- Step 1: Aggregate BQ03A to customer level for December 2023 (starting MRR)
    --         BQ03A is subscription-level — sum across all subscriptions per customer
    SELECT
        CUSTOMER_ID,
        SUM(MRR_CENTS) AS STARTING_MRR_CENTS

    FROM LEDGERLY.ANALYTICS.BQ03A_SUBSCRIPTION_MRR_BY_MONTH_2024

    WHERE MRR_MONTH = '2023-12-01'

    GROUP BY
        CUSTOMER_ID
),


-- Step 2: bq03a_end_aggregated
-- Start from BQ03A_SUBSCRIPTION_MRR_BY_MONTH_2024 again and keep only rows where 
-- MRR_MONTH = '2024-12-01'. 
-- This step also groups by CUSTOMER_ID and sums MRR_CENTS. 
-- This creates ENDING_MRR_CENTS, which shows how much recurring revenue each customer contributed at 
-- the end of the 2024 measurement period.

bq03a_end_aggregated AS
(
    -- Step 2: Aggregate BQ03A to customer level for December 2024 (ending MRR)
    SELECT
        CUSTOMER_ID,
        SUM(MRR_CENTS) AS ENDING_MRR_CENTS

    FROM LEDGERLY.ANALYTICS.BQ03A_SUBSCRIPTION_MRR_BY_MONTH_2024

    WHERE MRR_MONTH = '2024-12-01'

    GROUP BY
        CUSTOMER_ID
),

-- Step 3: cohort_mrr_start_join
-- Join BQ06A_PAID_SIGNUP_COHORT_BY_CUSTOMER to the customer-level starting MRR table on CUSTOMER_ID. 
-- This adds each customer’s STARTING_MRR_CENTS to their paid signup cohort. 
-- The customer cohort comes from BQ06A, and the starting MRR comes from BQ03A.

cohort_mrr_start_join AS
(
    -- Step 3: Join BQ06A to starting MRR on CUSTOMER_ID
    SELECT
        c.CUSTOMER_ID,
        c.PAID_SIGNUP_COHORT_MONTH,
        COALESCE(m.STARTING_MRR_CENTS, 0) AS STARTING_MRR_CENTS

    FROM LEDGERLY.ANALYTICS.BQ06A_PAID_SIGNUP_COHORT_BY_CUSTOMER AS c

    LEFT JOIN bq03a_start_aggregated AS m
        ON c.CUSTOMER_ID = m.CUSTOMER_ID
),



-- Step 4: cohort_mrr_start_filtered
-- Keep only customers where STARTING_MRR_CENTS > 0. This is the real NRR base filter. 
-- A customer with no MRR at the start of 2024 had nothing to retain during 2024, 
-- so that customer does not belong in the 2024 NRR base.

cohort_mrr_start_filtered AS
(
    -- Step 4: Keep only customers where starting MRR > 0
    --         This is the real NRR base filter.
    --         Any customer with no MRR in December 2023
    --         had nothing to retain going into 2024 and is excluded.
    SELECT
        CUSTOMER_ID,
        PAID_SIGNUP_COHORT_MONTH,
        STARTING_MRR_CENTS

    FROM cohort_mrr_start_join

    WHERE STARTING_MRR_CENTS > 0
),


-- Step 5: cohort_mrr_end_join
-- Join the filtered starting base to the customer-level ending MRR table on CUSTOMER_ID. 
-- This should be a LEFT JOIN so every customer from the starting NRR base remains in the result. 
-- If a customer has no matching December 2024 MRR row, 
-- the customer stays in the table and their ending MRR is left as NULL; 
-- BQ06C will convert that missing ending MRR to zero when it sums cohort totals.

-- Key columns: CUSTOMER_ID, PAID_SIGNUP_COHORT_MONTH, STARTING_MRR_CENTS, ENDING_MRR_CENTS


cohort_mrr_end_join AS
(
    -- Step 5: Join to ending MRR on CUSTOMER_ID
    --         LEFT JOIN keeps all customers from the starting base
    --         Customers that churned during 2024 return no row
    --         on the right side and contribute zero to the ending sum
    SELECT
        s.CUSTOMER_ID,
        s.PAID_SIGNUP_COHORT_MONTH,
        s.STARTING_MRR_CENTS,
        e.ENDING_MRR_CENTS

    FROM cohort_mrr_start_filtered AS s

    LEFT JOIN bq03a_end_aggregated AS e
        ON s.CUSTOMER_ID = e.CUSTOMER_ID
)

SELECT * FROM cohort_mrr_end_join;