USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

-- CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ04_MRR_MOVEMENT_DRIVERS_2024 AS

-- get subscription MRR rows from BQ03A
WITH subscription_mrr_base AS
(
    SELECT
        SUBSCRIPTION_ID,
        CUSTOMER_ID,
        SUBSCRIPTION_EVENT_TYPE,

        MRR_MONTH,

        MRR_CENTS

    FROM LEDGERLY.ANALYTICS.BQ03A_SUBSCRIPTION_MRR_BY_MONTH_2024
),

-- compare each subscription's current month MRR against its previous month MRR
subscription_mrr_comparison AS
(
    SELECT
        COALESCE(curr.SUBSCRIPTION_ID,          prev.SUBSCRIPTION_ID)            AS SUBSCRIPTION_ID,
        COALESCE(curr.CUSTOMER_ID,              prev.CUSTOMER_ID)                AS CUSTOMER_ID,
        COALESCE(curr.SUBSCRIPTION_EVENT_TYPE,  prev.SUBSCRIPTION_EVENT_TYPE)    AS SUBSCRIPTION_EVENT_TYPE,

        COALESCE
        (
            curr.MRR_MONTH,
            DATEADD('month', 1, prev.MRR_MONTH)
        ) AS MRR_MONTH,

        COALESCE(prev.MRR_CENTS, 0) AS PREV_MRR_CENTS,
        COALESCE(curr.MRR_CENTS, 0) AS MRR_CENTS

    FROM subscription_mrr_base AS prev
    FULL OUTER JOIN subscription_mrr_base AS curr
        ON prev.SUBSCRIPTION_ID = curr.SUBSCRIPTION_ID
       AND DATEADD('month', 1, prev.MRR_MONTH) = curr.MRR_MONTH
),

-- classify what drove each subscription's MRR movement
subscription_mrr_driver_classified AS
(
    SELECT
        SUBSCRIPTION_ID,
        CUSTOMER_ID,
        SUBSCRIPTION_EVENT_TYPE,

        MRR_MONTH,

        PREV_MRR_CENTS,
        MRR_CENTS,
        MRR_CENTS - PREV_MRR_CENTS AS NET_MRR_CHANGE_CENTS,

        CASE
            WHEN MRR_CENTS > 0
             AND PREV_MRR_CENTS = 0
             AND SUBSCRIPTION_EVENT_TYPE = 'reactivated'
                THEN 'reactivation'

            WHEN MRR_CENTS > 0
             AND PREV_MRR_CENTS = 0
                THEN 'new'

            WHEN MRR_CENTS = 0
             AND PREV_MRR_CENTS > 0
                THEN 'churn'

            WHEN MRR_CENTS > PREV_MRR_CENTS
             AND PREV_MRR_CENTS > 0
                THEN 'expansion'

            WHEN MRR_CENTS < PREV_MRR_CENTS
             AND MRR_CENTS > 0
                THEN 'contraction'

            WHEN MRR_CENTS = PREV_MRR_CENTS
             AND MRR_CENTS > 0
                THEN 'flat'

            ELSE 'no_mrr'
        END AS MRR_MOVEMENT_DRIVER

    FROM subscription_mrr_comparison
    WHERE MRR_MONTH >= TO_DATE('2024-01-01')
      AND MRR_MONTH <  TO_DATE('2025-01-01')
),

-- group subscription movement drivers into one row per MRR month
mrr_movement_drivers_by_month AS
(
    SELECT
        MRR_MONTH,

        SUM(NET_MRR_CHANGE_CENTS) AS NET_MRR_CHANGE_CENTS,

        SUM
        (
            CASE
                WHEN MRR_MOVEMENT_DRIVER = 'new'
                    THEN NET_MRR_CHANGE_CENTS
                ELSE 0
            END
        ) AS NEW_MRR_CENTS,

        SUM
        (
            CASE
                WHEN MRR_MOVEMENT_DRIVER = 'reactivation'
                    THEN NET_MRR_CHANGE_CENTS
                ELSE 0
            END
        ) AS REACTIVATION_MRR_CENTS,

        SUM
        (
            CASE
                WHEN MRR_MOVEMENT_DRIVER = 'expansion'
                    THEN NET_MRR_CHANGE_CENTS
                ELSE 0
            END
        ) AS EXPANSION_MRR_CENTS,

        SUM
        (
            CASE
                WHEN MRR_MOVEMENT_DRIVER = 'contraction'
                    THEN ABS(NET_MRR_CHANGE_CENTS)
                ELSE 0
            END
        ) AS CONTRACTION_MRR_CENTS,

        SUM
        (
            CASE
                WHEN MRR_MOVEMENT_DRIVER = 'churn'
                    THEN ABS(NET_MRR_CHANGE_CENTS)
                ELSE 0
            END
        ) AS CHURN_MRR_CENTS

    FROM subscription_mrr_driver_classified
    GROUP BY MRR_MONTH
)

SELECT *
FROM mrr_movement_drivers_by_month;