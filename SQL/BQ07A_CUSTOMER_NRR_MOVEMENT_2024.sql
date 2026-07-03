-- ============================================================
-- BQ07A: CUSTOMER_NRR_MOVEMENT_2024
-- Business question: How did expansion, contraction, and churn
--                   affect 2024 year-end NRR by paid signup cohort?
-- Input: BQ06B_CUSTOMER_NRR_BASE_2024
--        One row per customer. STARTING_MRR_CENTS > 0.
--        ENDING_MRR_CENTS is NULL for churned customers.
-- Grain: one row per customer
-- ============================================================

-- A reminder of the helper table we will be using :
-- BQ06B_CUSTOMER_NRR_BASE_2024 is the customer-level NRR base. 
-- It has :
-- - one row per customer, 
-- - the customer's paid signup cohort month, 
-- - their MRR at the start of the 2024 measurement window, 
-- - their MRR at the end of the 2024 measurement window. 
-- - Every row has STARTING_MRR_CENTS > 0. 
-- - Customers with no MRR row at the end of the measurement window can have ENDING_MRR_CENTS as NULL,
--   which means they churned before year-end.

-- Key columns: CUSTOMER_ID, PAID_SIGNUP_COHORT_MONTH, STARTING_MRR_CENTS, ENDING_MRR_CENTS.


CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ07A_CUSTOMER_NRR_MOVEMENT_2024 AS

-- Step 1: nrr_base_filtered keeps the customer-level NRR base columns from BQ06B.

-- BQ07 needs to explain what happened to each customer's recurring revenue across 2024. 
-- That information already lives in BQ06B at the right grain — one row per customer — 
-- So nrr_base_filtered starts there and reduces immediately to the four columns the movement calculation
-- needs: customer ID, paid signup cohort month, starting MRR, and ending MRR. 

-- This keeps the table focused because BQ07 is not rebuilding the NRR base. 
-- It is only preparing the customer-level input needed to calculate expansion, contraction, 
-- churn, and unchanged MRR.

WITH nrr_base_filtered AS
(
    -- Step 1: Keep customer-level NRR base columns from BQ05B
    SELECT
        CUSTOMER_ID,
        PAID_SIGNUP_COHORT_MONTH,
        STARTING_MRR_CENTS,
        ENDING_MRR_CENTS

    FROM LEDGERLY.ANALYTICS.BQ06B_CUSTOMER_NRR_BASE_2024
),


-- Step 2: nrr_base_movement_calculated calculates customer-level MRR movement amounts.

-- nrr_base_movement_calculated compares each customer's starting MRR against their ending MRR. 
-- A higher ending MRR produces expansion equal to the difference. 
-- A lower ending MRR that is still above zero produces contraction equal to the difference. 
-- A missing or zero ending MRR means the customer is gone, and the full starting MRR becomes churn. 
-- An equal ending MRR produces unchanged MRR. 

-- Net MRR change is ending MRR minus starting MRR, but ending MRR must be treated as zero when 
-- it is missing — otherwise a churned customer returns NULL for net change instead of 
-- a negative number, and the cohort-level sum in BQ07B silently drops their lost MRR.

nrr_base_movement_calculated AS
(
    -- Step 2: Calculate customer-level MRR movement amounts
    SELECT
        CUSTOMER_ID,
        PAID_SIGNUP_COHORT_MONTH,
        STARTING_MRR_CENTS,
        ENDING_MRR_CENTS,

        -- Expansion: ending MRR is higher than starting MRR
        CASE
            WHEN ENDING_MRR_CENTS > STARTING_MRR_CENTS
            THEN ENDING_MRR_CENTS - STARTING_MRR_CENTS
            ELSE 0
        END AS EXPANSION_MRR_CENTS,

        -- Contraction: ending MRR is lower than starting but still above zero
        CASE
            WHEN ENDING_MRR_CENTS < STARTING_MRR_CENTS
             AND ENDING_MRR_CENTS > 0
            THEN STARTING_MRR_CENTS - ENDING_MRR_CENTS
            ELSE 0
        END AS CONTRACTION_MRR_CENTS,

        -- Churn: ending MRR is missing or zero
        CASE
            WHEN ENDING_MRR_CENTS IS NULL
              OR ENDING_MRR_CENTS = 0
            THEN STARTING_MRR_CENTS
            ELSE 0
        END AS CHURN_MRR_CENTS,

        -- Unchanged: ending MRR equals starting MRR exactly
        CASE
            WHEN ENDING_MRR_CENTS = STARTING_MRR_CENTS
            THEN STARTING_MRR_CENTS
            ELSE 0
        END AS UNCHANGED_MRR_CENTS,

        -- Net MRR change: COALESCE required so churned customers
        -- contribute a negative amount instead of NULL
        COALESCE(ENDING_MRR_CENTS, 0) - STARTING_MRR_CENTS AS NET_MRR_CHANGE_CENTS

    FROM nrr_base_filtered
),



-- Step 3: nrr_base_movement_labeled labels each customer's movement type.

-- nrr_base_movement_labeled gives each customer one movement label after the dollar movement has been
-- calculated. 

-- Customers with higher ending MRR are labeled expanded. 
-- Customers with lower ending MRR above zero are labeled contracted. 
-- Customers with missing or zero ending MRR are labeled churned. 
-- Everyone else is labeled unchanged. 

-- The dollar fields ( _CENTS ) explain how much money moved. 
-- The movement label lets BQ07B count how many customers caused each type of movement, 
-- not just how many dollars moved.

-- Key columns:CUSTOMER_ID, PAID_SIGNUP_COHORT_MONTH, STARTING_MRR_CENTS, ENDING_MRR_CENTS,
-- EXPANSION_MRR_CENTS, CONTRACTION_MRR_CENTS, CHURN_MRR_CENTS, UNCHANGED_MRR_CENTS, 
-- NET_MRR_CHANGE_CENTS, CUSTOMER_MOVEMENT_TYPE.

nrr_base_movement_labeled AS
(
    -- Step 3: Label each customer's movement type
    SELECT
        CUSTOMER_ID,
        PAID_SIGNUP_COHORT_MONTH,
        STARTING_MRR_CENTS,
        ENDING_MRR_CENTS,
        EXPANSION_MRR_CENTS,
        CONTRACTION_MRR_CENTS,
        CHURN_MRR_CENTS,
        UNCHANGED_MRR_CENTS,
        NET_MRR_CHANGE_CENTS,

        CASE
            WHEN ENDING_MRR_CENTS > STARTING_MRR_CENTS  THEN 'expanded'
            WHEN ENDING_MRR_CENTS < STARTING_MRR_CENTS
             AND ENDING_MRR_CENTS > 0                   THEN 'contracted'
            WHEN ENDING_MRR_CENTS IS NULL
              OR ENDING_MRR_CENTS = 0                   THEN 'churned'
            ELSE                                              'unchanged'
        END AS CUSTOMER_MOVEMENT_TYPE

    FROM nrr_base_movement_calculated
)

SELECT * FROM nrr_base_movement_labeled;
