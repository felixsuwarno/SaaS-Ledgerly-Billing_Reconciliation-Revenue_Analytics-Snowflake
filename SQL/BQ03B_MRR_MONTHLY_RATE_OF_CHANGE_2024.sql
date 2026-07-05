USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

-- CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ03B_MRR_MONTHLY_RATE_OF_CHANGE_2024 AS

-- Business question: how did total MRR change from one month to the next across 2024,
-- in dollars and as a rate?
--
-- The key term is MRR, and it already exists at the subscription level in
-- BQ03A_SUBSCRIPTION_MRR_BY_MONTH_2024, in the MRR_CENTS column, one row per
-- subscription per month. That's where this table starts, because the dollar figure
-- the question needs is already sitting there — it just isn't rolled up to the month
-- level yet, and there's no month-over-month comparison built on top of it. Getting
-- from "MRR per subscription per month" to "change in total MRR from month to month"
-- takes two more moves: roll the subscription-month rows straight up to one total per
-- month, then line each month up next to the month before it and calculate the
-- change and the rate.
--
-- This table assumes BQ03A already produces one row per subscription per month. If
-- that ever stops being true — for example, a subscription showing up more than
-- once in STG_SUBSCRIPTIONS — the fix belongs in BQ03A, not a defensive re-aggregation
-- bolted on here.

WITH subscription_mrr_base AS
(
    -- Step 1: Pull the subscription-month rows from BQ03A, keeping only the columns
    -- this table needs.
    --
    -- BQ03A carries columns that don't matter here — the event id, the event type,
    -- and the plan interval. Before any rollup happens, this step narrows the table
    -- down to the subscription and customer identifiers, the three calendar dates,
    -- and MRR_CENTS, since those are the only pieces the rest of this query touches.

    SELECT
        SUBSCRIPTION_ID,
        CUSTOMER_ID,
        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF,
        MRR_CENTS
    FROM LEDGERLY.ANALYTICS.BQ03A_SUBSCRIPTION_MRR_BY_MONTH_2024
),

mrr_by_month AS
(
    -- Step 2: Roll the subscription-month rows up to one row per calendar month.
    --
    -- The question asks about total MRR, not subscription-level MRR, so the rows
    -- from step 1 collapse straight to a single row per month. CUSTOMER_COUNT and
    -- SUBSCRIPTION_COUNT are counted distinctly here, and MRR_CENTS is summed. This
    -- is the one-row-per-month shape the month-over-month comparison in step 3
    -- needs before it can run.

    SELECT
        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF,
        COUNT(DISTINCT CUSTOMER_ID) AS CUSTOMER_COUNT,
        COUNT(DISTINCT SUBSCRIPTION_ID) AS SUBSCRIPTION_COUNT,
        SUM(MRR_CENTS) AS MRR_CENTS
    FROM subscription_mrr_base
    GROUP BY
        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF
),

mrr_by_month_with_change AS
(
    -- Step 3: Calculate the month-over-month MRR change, in dollars and as a rate.
    --
    -- With one total per month now in hand, answering "how did MRR change" means
    -- putting each month next to the month before it. LAG does that by looking back
    -- one month in the ordered sequence and pulling the prior month's total onto the
    -- current row. With both totals sitting side by side, NET_MRR_CHANGE_CENTS is
    -- the raw dollar difference, MRR_CHANGE_RATE is that difference divided by the
    -- prior month's MRR — expressed as a decimal, with NULLIF guarding against
    -- division by zero — and PREV_MRR_CENTS carries the prior month's total forward
    -- for reference. December 2023 is what makes January 2024's numbers possible:
    -- without it, LAG finds no prior row and returns null. December 2023 itself will
    -- show null change figures, which is expected — it's the anchor, not a reported
    -- month.

    SELECT
        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF,
        LAG(MRR_CENTS) OVER
        (
            ORDER BY MRR_MONTH
        ) AS PREV_MRR_CENTS,
        MRR_CENTS,
        MRR_CENTS
        -
        LAG(MRR_CENTS) OVER
        (
            ORDER BY MRR_MONTH
        ) AS NET_MRR_CHANGE_CENTS,
        (
            MRR_CENTS
            -
            LAG(MRR_CENTS) OVER
            (
                ORDER BY MRR_MONTH
            )
        )
        /
        NULLIF
        (
            LAG(MRR_CENTS) OVER
            (
                ORDER BY MRR_MONTH
            ),
            0
        ) AS MRR_CHANGE_RATE,
        CUSTOMER_COUNT,
        SUBSCRIPTION_COUNT
    FROM mrr_by_month
),

mrr_by_month_2024_only AS
(
    -- Step 4: Narrow the final output down to the 2024 calendar year.
    --
    -- December 2023 only exists in this table so LAG has something to sit behind
    -- when it calculates January 2024's change. Once that calculation is done,
    -- December 2023 isn't a month this report covers, so this step filters MRR_MONTH
    -- down to 2024-01-01 or later — after the LAG has already run. Filtering any
    -- earlier would strip December out before January had a prior month to compare
    -- against, breaking the exact calculation this table exists to produce. The
    -- upper bound, MRR_MONTH < 2025-01-01, exists for the same reason stated as a
    -- rule rather than left as an accident of BQ03A's row count: the business
    -- question is 2024 only, and stating that boundary explicitly here means this
    -- table still reports the correct year even if BQ03A's calendar ever changes.

    SELECT
        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF,
        PREV_MRR_CENTS,
        MRR_CENTS,
        NET_MRR_CHANGE_CENTS,
        MRR_CHANGE_RATE,
        CUSTOMER_COUNT,
        SUBSCRIPTION_COUNT
    FROM mrr_by_month_with_change
    WHERE MRR_MONTH >= TO_DATE('2024-01-01')
      AND MRR_MONTH <  TO_DATE('2025-01-01')
)

SELECT *
FROM mrr_by_month_2024_only;