USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ05_RETRY_EXHAUSTED_REVENUE_LOST_2024 AS

-- Table 1: BQ05_RETRY_EXHAUSTED_REVENUE_LOST_2024

-- Step 1: Pull the MRR history for every subscription from December 2023 through December 2024.
-- We are looking for how much MRR each subscription was generating before it disappeared. 
-- That value lives in BQ03A — specifically in MRR_CENTS, one row per subscription per active month. 
-- We start here because BQ03A is the only table in the project that already has 
-- subscription-level MRR calculated and ready to use. 
-- We pull from December 2023 through December 2024 — December 2023 is not an output month but 
-- we need it so January 2024 churn has a previous month to compare against.

WITH subscription_mrr_base AS
(
    SELECT
        SUBSCRIPTION_ID,
        CUSTOMER_ID,
        MRR_MONTH,
        MRR_CENTS
    FROM LEDGERLY.ANALYTICS.BQ03A_SUBSCRIPTION_MRR_BY_MONTH_2024
    WHERE MRR_MONTH >= TO_DATE('2023-12-01')
      AND MRR_MONTH <= TO_DATE('2024-12-01')
),


-- Step 2: Place each subscription's current month MRR and previous month MRR side by side.
-- BQ03A only stores months where a subscription was active — there is no row for the month a subscription churned 
-- because once a subscription churns, it stops generating MRR and BQ03A stops recording it entirely. 
-- To find the churn month, we self-join BQ03A against itself: one copy represents the current month, 
-- the other represents the previous month, matched on SUBSCRIPTION_ID and a one-month date offset. 
-- We pull December 2023 through December 2024 — December 2023 is not an output month, 
-- but January 2024 churn needs it as a previous month reference. 
-- When a subscription has a row in March but no row in April, the FULL OUTER JOIN produces an April row with 
-- a NULL current MRM, which we COALESCE to zero.

subscription_mrr_comparison AS
(
    SELECT
        COALESCE(curr.SUBSCRIPTION_ID, prev.SUBSCRIPTION_ID) AS SUBSCRIPTION_ID,
        COALESCE(curr.CUSTOMER_ID,     prev.CUSTOMER_ID)     AS CUSTOMER_ID,
        COALESCE
        (
            curr.MRR_MONTH,
            DATEADD('month', 1, prev.MRR_MONTH)
        )                                                     AS MRR_MONTH,
        COALESCE(prev.MRR_CENTS, 0)                          AS PREV_MRR_CENTS,
        COALESCE(curr.MRR_CENTS, 0)                          AS MRR_CENTS
    FROM subscription_mrr_base AS prev
    FULL OUTER JOIN subscription_mrr_base AS curr
        ON  prev.SUBSCRIPTION_ID = curr.SUBSCRIPTION_ID
        AND DATEADD('month', 1, prev.MRR_MONTH) = curr.MRR_MONTH
),

-- Step 3: Filter to churned subscriptions in 2024 only.
-- From the comparison produced in Step 2, a subscription is churned when its current month MRR is zero and 
-- its previous month MRR was above zero — it was active last month and gone this month. 
-- We filter to those rows, then drop December 2023 from the output by restricting churn month to 2024 only. 
-- December 2023 has served its purpose as a lookback reference and drops out here. 
-- What remains is one row per churned subscription per churn month, 
-- carrying PREV_MRR_CENTS — the MRR the company will no longer collect from that subscription.

subscriptions_churned AS
(
    SELECT
        SUBSCRIPTION_ID,
        CUSTOMER_ID,
        MRR_MONTH,
        PREV_MRR_CENTS
    FROM subscription_mrr_comparison
    WHERE MRR_CENTS      = 0
      AND PREV_MRR_CENTS > 0
      AND MRR_MONTH >= TO_DATE('2024-01-01')
      AND MRR_MONTH <= TO_DATE('2024-12-01')
),


-- Step 4: Isolate uncollectible invoices from STG_INVOICES and reduce to one row per subscription per MRR lost month.

-- We now know which subscriptions churned, but not why. The reason lives in STG_INVOICES — in INVOICE_STATUS,
-- which is set to 'uncollectible' when the billing system attempted collection, failed every retry, and gave up.

-- We filter STG_INVOICES to INVOICE_STATUS = 'uncollectible'.
-- INVOICE_PERIOD_END tells us the failed billing period end date.

-- But BQ03A shows MRR disappearing in the month after that period ends.

-- So we create MRR_LOST_MONTH by taking the invoice period end month and adding one month.
-- A subscription can have more than one uncollectible invoice tied to the same MRR lost month,
-- so we group by SUBSCRIPTION_ID and MRR_LOST_MONTH.

-- Without this grouping, a subscription with two uncollectible invoices tied to the same lost month would
-- produce two matching rows in the next join and double its lost MRR in the final sum

invoices_uncollectible_deduped AS
(
    SELECT
        SUBSCRIPTION_ID,
        DATEADD('month', 1, DATE_TRUNC('month', TO_DATE(INVOICE_PERIOD_END))) AS MRR_LOST_MONTH
    FROM LEDGERLY.STAGING.STG_INVOICES
    WHERE INVOICE_STATUS = 'uncollectible'
      AND DATE_TRUNC('month', TO_DATE(INVOICE_PERIOD_END)) >= TO_DATE('2024-01-01')
      AND DATE_TRUNC('month', TO_DATE(INVOICE_PERIOD_END)) <= TO_DATE('2024-12-01')
    GROUP BY
        SUBSCRIPTION_ID,
        DATE_TRUNC('month', TO_DATE(INVOICE_PERIOD_END))
),



-- Step 5: Join churned subscriptions to uncollectible invoices on SUBSCRIPTION_ID and MRR lost month.

-- We join the churned subscriptions from Step 3 to the deduped uncollectible invoices from Step 4 on two conditions.

-- First, SUBSCRIPTION_ID must match —
-- confirming the uncollectible invoice belongs to the same subscription that churned.

-- Second, MRR_MONTH must equal MRR_LOST_MONTH.
-- MRR_LOST_MONTH is calculated as the month after INVOICE_PERIOD_END.

-- We use that because BQ03A shows the subscription still had MRR in the invoice period end month,
-- then disappeared in the following month.

-- Without this second condition, the join would match a churned subscription to any uncollectible invoice that
-- subscription ever had, producing false matches.

churned_retry_exhausted AS
(
    SELECT
        s.SUBSCRIPTION_ID,
        s.CUSTOMER_ID,
        s.MRR_MONTH,
        s.PREV_MRR_CENTS
    FROM subscriptions_churned         AS s
    JOIN invoices_uncollectible_deduped AS i
        ON  s.SUBSCRIPTION_ID = i.SUBSCRIPTION_ID
        AND s.MRR_MONTH = i.MRR_LOST_MONTH
),


-- Step 6: Aggregate by churn month to produce the final answer.

-- With retry-exhausted churned subscriptions confirmed, 
-- we group by MRR_MONTH and sum PREV_MRR_CENTS once per subscription. 

-- That dollar total is the recurring revenue the company will never collect again because 
-- the billing system ran out of retries. 

-- We also count distinct subscriptions lost per month so the reader can see both 
-- how many customers were affected and 
-- how much revenue walked out with them.

mrr_lost_by_month AS
(
    SELECT
        MRR_MONTH,
        COUNT(DISTINCT SUBSCRIPTION_ID)  AS SUBSCRIPTIONS_LOST,
        SUM(PREV_MRR_CENTS)              AS RETRY_EXHAUSTED_MRR_LOST_CENTS
    FROM churned_retry_exhausted
    GROUP BY MRR_MONTH
)

SELECT *
FROM mrr_lost_by_month
ORDER BY MRR_MONTH;