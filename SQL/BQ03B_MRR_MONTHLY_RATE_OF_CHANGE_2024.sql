USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ03B_MRR_MONTHLY_RATE_OF_CHANGE_2024 AS

-- get subscription MRR rows from BQ03A
WITH subscription_mrr_base AS
(
    SELECT
        SUBSCRIPTION_ID,
        CUSTOMER_ID,

        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF,

        MRR_CENTS

    FROM LEDGERLY.ANALYTICS.BQ03A_SUBSCRIPTION_MRR_BY_MONTH_2024
),

-- group to one row per subscription per MRR month
subscription_mrr_by_month AS
(
    SELECT
        SUBSCRIPTION_ID,
        CUSTOMER_ID,

        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF,

        SUM(MRR_CENTS) AS MRR_CENTS

    FROM subscription_mrr_base
    GROUP BY
        SUBSCRIPTION_ID,
        CUSTOMER_ID,
        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF
),

-- group subscription MRR into one row per MRR month
mrr_by_month AS
(
    SELECT
        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF,

        COUNT(DISTINCT CUSTOMER_ID) AS CUSTOMER_COUNT,
        COUNT(DISTINCT SUBSCRIPTION_ID) AS SUBSCRIPTION_COUNT,
        SUM(MRR_CENTS) AS MRR_CENTS

    FROM subscription_mrr_by_month
    GROUP BY
        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF
),

-- calculate month-over-month MRR change
mrr_by_month_with_change AS
(
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
)

SELECT *
FROM mrr_by_month_with_change;