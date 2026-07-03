-- ============================================================
-- BQ07B: COHORT_NRR_MOVEMENT_2024
-- Input: BQ07A_CUSTOMER_NRR_MOVEMENT_2024
--        One row per customer with movement amounts and label.
-- Grain: one row per paid signup cohort month
-- ============================================================
 
CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ07B_COHORT_NRR_MOVEMENT_2024 AS


-- Step 1: movement_filtered keeps the cohort movement columns from BQ07A.
-- BQ07A already produced one clean movement row per customer. 
-- movement_filtered starts there and keeps only the columns BQ07B needs: paid signup cohort month, 
-- customer movement label, starting MRR, ending MRR, and the movement amount columns. 
-- This keeps the cohort table focused on summarizing customer movement, not recalculating it.

WITH movement_filtered AS
(

    SELECT
        PAID_SIGNUP_COHORT_MONTH,
        CUSTOMER_MOVEMENT_TYPE,
        STARTING_MRR_CENTS,
        ENDING_MRR_CENTS,
        EXPANSION_MRR_CENTS,
        CONTRACTION_MRR_CENTS,
        CHURN_MRR_CENTS,
        UNCHANGED_MRR_CENTS,
        NET_MRR_CHANGE_CENTS
 
    FROM LEDGERLY.ANALYTICS.BQ07A_CUSTOMER_NRR_MOVEMENT_2024
),



-- Step 2: movement_aggregated aggregates customer counts and 
-- MRR movement amounts by paid signup cohort month.

-- movement_aggregated groups the customer rows by paid signup cohort month, 
-- and it builds two stories at once: the customer-count story and the MRR story. 

-- The customer-count fields count how many customers 
-- expanded, 
-- contracted, 
-- churned, or 
-- stayed unchanged. 

-- The MRR fields sum how much money came from 
-- starting MRR, 
-- ending MRR, 
-- expansion, 
-- contraction, 
-- churn, 
-- unchanged MRR, and 
-- net MRR change. 

-- Ending MRR uses missing ending MRR as zero before summing, 
-- so a fully churned cohort returns zero instead of NULL.


movement_aggregated AS
(

    SELECT
        PAID_SIGNUP_COHORT_MONTH,

        -- Customer counts
        COUNT(*)                                                          AS            CUSTOMER_COUNT,
        COUNT(CASE WHEN CUSTOMER_MOVEMENT_TYPE = 'expanded'   THEN 1 END) AS   EXPANDED_CUSTOMER_COUNT,
        COUNT(CASE WHEN CUSTOMER_MOVEMENT_TYPE = 'contracted' THEN 1 END) AS CONTRACTED_CUSTOMER_COUNT,
        COUNT(CASE WHEN CUSTOMER_MOVEMENT_TYPE = 'churned'    THEN 1 END) AS    CHURNED_CUSTOMER_COUNT,
        COUNT(CASE WHEN CUSTOMER_MOVEMENT_TYPE = 'unchanged'  THEN 1 END) AS  UNCHANGED_CUSTOMER_COUNT,

        -- MRR movement amounts
        SUM(STARTING_MRR_CENTS)             AS STARTING_MRR_CENTS,
        SUM(COALESCE(ENDING_MRR_CENTS, 0))  AS ENDING_MRR_CENTS,
        SUM(EXPANSION_MRR_CENTS)            AS EXPANSION_MRR_CENTS,
        SUM(CONTRACTION_MRR_CENTS)          AS CONTRACTION_MRR_CENTS,
        SUM(CHURN_MRR_CENTS)                AS CHURN_MRR_CENTS,
        SUM(UNCHANGED_MRR_CENTS)            AS UNCHANGED_MRR_CENTS,
        SUM(NET_MRR_CHANGE_CENTS)           AS NET_MRR_CHANGE_CENTS

    FROM movement_filtered

    GROUP BY
        PAID_SIGNUP_COHORT_MONTH
),


-- Step 3: movement_rates_calculated calculates cohort-level 
-- expansion rate, 
-- contraction rate, 
-- churn rate, 
-- GRR, and 
-- NRR.

-- movement_rates_calculated divides each movement amount by starting MRR and multiplies by 100, 
-- so the rate columns are true percent values. 

-- Expansion rate shows how much existing customers increased recurring revenue. 
-- Contraction rate shows how much recurring revenue was lost from customers who stayed but paid less. 
-- Churn rate shows how much recurring revenue was lost from customers whose ending MRR 
-- was missing or zero. 
-- GRR shows how much of the cohort's starting MRR remained after contraction and churn, 
-- before adding expansion.
-- NRR shows the final year-end result after expansion, contraction, and churn. 

-- Since BQ07B uses true percent format, 126.59 means 126.59%.


movement_rates_calculated AS
(

    SELECT
        PAID_SIGNUP_COHORT_MONTH,
        CUSTOMER_COUNT,
        EXPANDED_CUSTOMER_COUNT,
        CONTRACTED_CUSTOMER_COUNT,
        CHURNED_CUSTOMER_COUNT,
        UNCHANGED_CUSTOMER_COUNT,
        STARTING_MRR_CENTS,
        ENDING_MRR_CENTS,
        EXPANSION_MRR_CENTS,
        CONTRACTION_MRR_CENTS,
        CHURN_MRR_CENTS,
        UNCHANGED_MRR_CENTS,
        NET_MRR_CHANGE_CENTS,

        ROUND
        (
            EXPANSION_MRR_CENTS * 1.0
            /
            NULLIF(STARTING_MRR_CENTS, 0) * 100
            ,2
        ) AS EXPANSION_RATE_PCT,

        ROUND
        (
            CONTRACTION_MRR_CENTS * 1.0
            /
            NULLIF(STARTING_MRR_CENTS, 0) * 100
            ,2
        ) AS CONTRACTION_RATE_PCT,

        ROUND
        (
            CHURN_MRR_CENTS * 1.0
            /
            NULLIF(STARTING_MRR_CENTS, 0) * 100
            ,2
        ) AS CHURN_RATE_PCT,

        ROUND
        (
            (STARTING_MRR_CENTS - CONTRACTION_MRR_CENTS - CHURN_MRR_CENTS) * 1.0
            /
            NULLIF(STARTING_MRR_CENTS, 0) * 100
            ,2
        ) AS GRR_PCT,

        ROUND
        (
            (STARTING_MRR_CENTS + EXPANSION_MRR_CENTS - CONTRACTION_MRR_CENTS - CHURN_MRR_CENTS) * 1.0
            /
            NULLIF(STARTING_MRR_CENTS, 0) * 100
            ,2
        ) AS NRR_PCT

    FROM movement_aggregated
)
 
SELECT * FROM movement_rates_calculated;
 
 
