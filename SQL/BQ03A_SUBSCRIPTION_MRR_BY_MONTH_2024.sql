USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ03A_SUBSCRIPTION_MRR_BY_MONTH_2024 AS

-- create 13 month index rows for Dec 2023 through Dec 2024
WITH month_index_generated AS
(
    SELECT
        ROW_NUMBER() OVER
        (
            ORDER BY SEQ1()
        ) - 1 AS MONTH_INDEX

    FROM TABLE(GENERATOR(ROWCOUNT => 13))
),

-- create previous MRR month, current MRR month, and MRR cutoff
mrr_months AS
(
    SELECT
        DATEADD('month', MONTH_INDEX - 1, TO_DATE('2023-12-01')) AS PREV_MRR_MONTH,
        DATEADD('month', MONTH_INDEX,     TO_DATE('2023-12-01')) AS MRR_MONTH,
        DATEADD('month', MONTH_INDEX + 1, TO_DATE('2023-12-01')) AS MRR_CUTOFF

    FROM month_index_generated
),

-- keep subscription event rows before 2025
-- events in 2025 or later cannot affect Dec 2023 through Dec 2024 MRR
subscription_events_filtered AS
(
    SELECT
        SUBSCRIPTION_EVENT_ID,
        SUBSCRIPTION_ID,
        CUSTOMER_ID,
        SUBSCRIPTION_EVENT_TYPE,
        EVENT_EFFECTIVE_AT,
        PREVIOUS_PLAN_AMOUNT_CENTS,
        NEW_PLAN_AMOUNT_CENTS

    FROM LEDGERLY.STAGING.STG_SUBSCRIPTION_EVENTS
    WHERE EVENT_EFFECTIVE_AT < TO_TIMESTAMP_NTZ('2025-01-01')
),

-- for each subscription event, find the next event for the same subscription
-- this tells us when the current event stopped being the latest event
subscription_events_with_next_event AS
(
    SELECT
        SUBSCRIPTION_EVENT_ID,
        SUBSCRIPTION_ID,
        CUSTOMER_ID,
        SUBSCRIPTION_EVENT_TYPE,
        EVENT_EFFECTIVE_AT,
        PREVIOUS_PLAN_AMOUNT_CENTS,
        NEW_PLAN_AMOUNT_CENTS,

        LEAD(EVENT_EFFECTIVE_AT) OVER
        (
            PARTITION BY SUBSCRIPTION_ID
            ORDER BY
                EVENT_EFFECTIVE_AT,
                SUBSCRIPTION_EVENT_ID
        ) AS NEXT_EVENT_EFFECTIVE_AT

    FROM subscription_events_filtered
),

-- start from each MRR month
-- bring in the subscription event that was still the latest event before the MRR cutoff
mrr_months_subscription_events_join AS
(
    SELECT
        e.SUBSCRIPTION_ID,
        e.SUBSCRIPTION_EVENT_ID,
        e.CUSTOMER_ID,
        e.SUBSCRIPTION_EVENT_TYPE,

        m.PREV_MRR_MONTH,
        m.MRR_MONTH,
        m.MRR_CUTOFF,

        e.EVENT_EFFECTIVE_AT,
        e.NEXT_EVENT_EFFECTIVE_AT,

        e.PREVIOUS_PLAN_AMOUNT_CENTS,
        e.NEW_PLAN_AMOUNT_CENTS

    FROM mrr_months AS m
    LEFT JOIN subscription_events_with_next_event AS e
        ON e.EVENT_EFFECTIVE_AT < m.MRR_CUTOFF          -- this event happens BEFORE the cutoff date for this mrr month
       AND
       (
            e.NEXT_EVENT_EFFECTIVE_AT IS NULL           -- this event does not have any next event ( which means this event is the latest one )
            OR
            e.NEXT_EVENT_EFFECTIVE_AT >= m.MRR_CUTOFF   -- this event has a next event ( which means this event is not the last one ),
                                                        -- but its next event happens AFTER MRR_CUTOFF date.
                                                        -- we will reject all events whose next event happens before the cutoff date

                                                        -- an event that happens BEFORE cutoff date and it has next event that happens BEFORE cutoff date means
                                                        -- this event is no longer the active one for that month. It has already been replaced.

                                                        -- so basically this WHOLE filter wants to find either the latest event for a subscription,
                                                        -- or the latest event of a subscription that is still valid for a given mrr_month.
       )
),

-- remove subscriptions that were already canceled before the MRR month started
-- keep cancellations that happened inside the MRR month
mrr_months_subscription_relevant_event AS
(
    SELECT
        SUBSCRIPTION_ID,
        SUBSCRIPTION_EVENT_ID,
        CUSTOMER_ID,
        SUBSCRIPTION_EVENT_TYPE,

        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF,

        EVENT_EFFECTIVE_AT,
        NEXT_EVENT_EFFECTIVE_AT,

        PREVIOUS_PLAN_AMOUNT_CENTS,
        NEW_PLAN_AMOUNT_CENTS

    FROM mrr_months_subscription_events_join
    WHERE
        SUBSCRIPTION_EVENT_TYPE  <> 'canceled'     -- include all events that are not "canceled"
        OR
        EVENT_EFFECTIVE_AT       >= MRR_MONTH      -- for all "canceled" event, still include if it is effective on the same mrr month or after
),

-- decide which plan amount counts for that MRR month
mrr_months_subscription_plan_amount AS
(
    SELECT
        SUBSCRIPTION_ID,
        SUBSCRIPTION_EVENT_ID,
        CUSTOMER_ID,
        SUBSCRIPTION_EVENT_TYPE,

        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF,

        EVENT_EFFECTIVE_AT,

        CASE
            WHEN SUBSCRIPTION_EVENT_TYPE IN ('canceled', 'downgraded')
             AND EVENT_EFFECTIVE_AT >= MRR_MONTH
                THEN COALESCE(PREVIOUS_PLAN_AMOUNT_CENTS, 0)

            ELSE COALESCE(NEW_PLAN_AMOUNT_CENTS, 0)
        END AS MRR_PLAN_AMOUNT_CENTS

    FROM mrr_months_subscription_relevant_event
),

-- keep subscription interval so yearly plans can be converted into monthly MRR
subscriptions_filtered AS
(
    SELECT
        SUBSCRIPTION_ID,
        PLAN_INTERVAL

    FROM LEDGERLY.STAGING.STG_SUBSCRIPTIONS
),

-- add plan interval to each subscription-month row
mrr_months_subscriptions_join AS
(
    SELECT
        p.SUBSCRIPTION_ID,
        p.SUBSCRIPTION_EVENT_ID,
        p.CUSTOMER_ID,
        p.SUBSCRIPTION_EVENT_TYPE,

        p.PREV_MRR_MONTH,
        p.MRR_MONTH,
        p.MRR_CUTOFF,

        p.MRR_PLAN_AMOUNT_CENTS,
        s.PLAN_INTERVAL

    FROM mrr_months_subscription_plan_amount AS p
    LEFT JOIN subscriptions_filtered AS s
        ON p.SUBSCRIPTION_ID = s.SUBSCRIPTION_ID
),

-- convert each selected plan amount into monthly MRR
subscription_mrr_by_month AS
(
    SELECT
        SUBSCRIPTION_ID,
        SUBSCRIPTION_EVENT_ID,
        CUSTOMER_ID,
        SUBSCRIPTION_EVENT_TYPE,

        PREV_MRR_MONTH,
        MRR_MONTH,
        MRR_CUTOFF,

        PLAN_INTERVAL,

        CASE
            WHEN PLAN_INTERVAL = 'year'
                THEN ROUND(MRR_PLAN_AMOUNT_CENTS * 1.0 / 12, 0)

            WHEN PLAN_INTERVAL = 'month'
                THEN MRR_PLAN_AMOUNT_CENTS

            ELSE 0
        END AS MRR_CENTS

    FROM mrr_months_subscriptions_join
)

SELECT *
FROM subscription_mrr_by_month;
