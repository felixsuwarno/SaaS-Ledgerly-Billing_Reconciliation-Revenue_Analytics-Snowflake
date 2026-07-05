USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

-- ============================================================
-- BQ05C: COHORT_NRR_2024
-- Purpose: Aggregate BQ05B to one row per cohort month.
--          Calculate NRR and rank cohorts strongest to weakest.
-- Grain: one row per paid signup cohort month
-- ============================================================

CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ05C_COHORT_NRR_2024 AS


-- Step 1: cohort_mrr_aggregated
-- Start from BQ05B_CUSTOMER_NRR_BASE_2024 because BQ05B already has one row per customer in the 2024 NRR base. 
-- This step groups customers by PAID_SIGNUP_COHORT_MONTH.
-- For each cohort, it counts customers, sums STARTING_MRR_CENTS, and sums ENDING_MRR_CENTS. 
-- Missing ending MRR is treated as zero because customers with starting MRR 
-- but no December 2024 MRR row still belong in the cohort and should contribute zero ending MRR.

WITH cohort_mrr_aggregated AS
(

    SELECT
        PAID_SIGNUP_COHORT_MONTH,
        COUNT(DISTINCT CUSTOMER_ID)             AS CUSTOMER_COUNT,
        SUM(STARTING_MRR_CENTS)                 AS STARTING_MRR_CENTS,
        SUM(COALESCE(ENDING_MRR_CENTS, 0))      AS ENDING_MRR_CENTS

    FROM LEDGERLY.ANALYTICS.BQ05B_CUSTOMER_NRR_BASE_2024

    GROUP BY
        PAID_SIGNUP_COHORT_MONTH
),


-- Step 2: cohort_nrr_calculated
-- Calculate NRR_PCT for each paid signup cohort by dividing ENDING_MRR_CENTS by STARTING_MRR_CENTS. 
-- This shows how much recurring revenue the cohort retained by year-end 
-- compared with the recurring revenue it had at the start of the measurement period. 
-- A result above 1.0 means the cohort ended with more MRR than it started with. 
-- A result below 1.0 means the cohort ended with less MRR than it started with.

cohort_nrr_calculated AS
(
    SELECT
        PAID_SIGNUP_COHORT_MONTH,
        CUSTOMER_COUNT,
        STARTING_MRR_CENTS,
        ENDING_MRR_CENTS,
        ROUND(ENDING_MRR_CENTS * 1.0 / STARTING_MRR_CENTS, 4) AS NRR_PCT

    FROM cohort_mrr_aggregated
),

-- Step 3: cohort_nrr_ranked
-- Rank the cohorts by NRR_PCT in both directions. 
-- NRR_RANK_HIGHEST = 1 identifies the strongest paid signup cohort. 
-- NRR_RANK_LOWEST = 1 identifies the weakest paid signup cohort. 
-- This final table answers BQ05: which paid signup cohorts had the strongest and weakest 2024 year-end NRR.

-- Key columns: 
-- PAID_SIGNUP_COHORT_MONTH, CUSTOMER_COUNT, STARTING_MRR_CENTS, ENDING_MRR_CENTS, NRR_PCT, 
-- NRR_RANK_HIGHEST, NRR_RANK_LOWEST

cohort_nrr_ranked AS
(
    SELECT
        PAID_SIGNUP_COHORT_MONTH,
        CUSTOMER_COUNT,
        STARTING_MRR_CENTS,
        ENDING_MRR_CENTS,
        NRR_PCT,
        RANK() OVER (ORDER BY NRR_PCT DESC) AS NRR_RANK_HIGHEST,
        RANK() OVER (ORDER BY NRR_PCT ASC)  AS NRR_RANK_LOWEST

    FROM cohort_nrr_calculated
)

SELECT * FROM cohort_nrr_ranked
ORDER BY NRR_PCT DESC;