USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ01B_STRIPE_PAYMENT_2024_JUNE AS

-- how it works :
-- this query is about how to prepare data from the processor side
-- it starts by all captured charges pertaining to invoices generated in june -> use CHARGES table
-- of all those captured charges, we need to see how much money it captured ( the transaction amount ) -> use balance transaction table
-- once these two tables are joined :
-- they need to be aggregated to one invoice per row grain


-- get charges whose id match what we have at business side june 2024 invoice table
-- filter to rows of data where the charge is
-- a success ( charge_status = succeeded ), and captured ( charge_captured = TRUE )
WITH charges_join_invoices AS
(
    SELECT
        charges.INVOICE_ID,
        charges.CHARGE_ID
    FROM LEDGERLY.STAGING.STG_CHARGES AS charges

    INNER JOIN LEDGERLY.ANALYTICS.BQ01A_STRIPE_INVOICE_2024_JUNE fi
        ON charges.INVOICE_ID = fi.INVOICE_ID

    WHERE charges.CHARGE_STATUS   = 'succeeded'
      AND charges.CHARGE_CAPTURED = TRUE
),

-- aggregate charges to one row per invoice before joining balance transactions
-- this prevents fan-out when an invoice has multiple charge rows
-- count distinct charge_id catches double charge scenarios
charges_aggregated AS
(
    SELECT
        INVOICE_ID,
        COUNT(DISTINCT CHARGE_ID)           AS PROCESSOR_CHARGE_COUNT
    FROM charges_join_invoices
    GROUP BY
        INVOICE_ID
),

-- fetch all balance transaction records linked to these invoices
-- charge rows: the gross amount stripe received from the customer
-- refund rows: money returned to the customer after the charge
-- dispute rows: money stripe clawed back due to a chargeback
-- joining on invoice_id because refund and dispute bt rows use re_ and dp_ as source_id
-- not ch_, so they cannot be joined via charge_id
balance_transactions_join_charges_aggregated AS
(
    SELECT
        bt.INVOICE_ID,
        bt.BALANCE_TRANSACTION_ID,
        bt.BALANCE_REPORTING_CATEGORY,
        bt.BALANCE_AMOUNT_CENTS,
        CAST(bt.BALANCE_AVAILABLE_ON AS DATE) AS BALANCE_AVAILABLE_DATE
    FROM LEDGERLY.STAGING.STG_BALANCE_TRANSACTIONS bt

    INNER JOIN charges_aggregated ca
        ON bt.INVOICE_ID = ca.INVOICE_ID

    WHERE bt.BALANCE_REPORTING_CATEGORY IN ('charge', 'refund', 'dispute')
),

-- aggregate balance transactions to one row per invoice
-- sum all balance transaction amounts across charge, refund, and dispute rows
-- charge rows are positive, refund and dispute rows are negative
-- result: gross charge amount reduced by any refunds or disputes
-- timing is not filtered here — it is a classification in bq02, not an amount filter
balance_transactions_aggregated AS
(
    SELECT
        INVOICE_ID,

        SUM(BALANCE_AMOUNT_CENTS)               AS PROCESSOR_BALANCE_AMOUNT_CENTS,

        -- does any refund BT exist for this invoice?
        MAX
        (
            CASE
                WHEN BALANCE_REPORTING_CATEGORY = 'refund'
                THEN 1
                ELSE 0
            END
        )                                       AS HAS_REFUND_ACTIVITY,

        -- does any dispute deduction BT exist for this invoice?
        MAX
        (
            CASE
                WHEN BALANCE_REPORTING_CATEGORY = 'dispute'
                 AND BALANCE_AMOUNT_CENTS < 0
                THEN 1 ELSE 0
            END
        )                                       AS HAS_DISPUTE_ACTIVITY,

        MIN(BALANCE_AVAILABLE_DATE)             AS FIRST_BALANCE_AVAILABLE_DATE,
        MAX(BALANCE_AVAILABLE_DATE)             AS LAST_BALANCE_AVAILABLE_DATE

    FROM balance_transactions_join_charges_aggregated
    GROUP BY
        INVOICE_ID
),

-- join charge count and balance transaction aggregates together
-- one row per invoice with both charge count and payment activity
charges_aggregated_join_balance_transactions_aggregated AS
(
    SELECT
        ca.INVOICE_ID,
        ca.PROCESSOR_CHARGE_COUNT,
        bta.PROCESSOR_BALANCE_AMOUNT_CENTS,
        bta.HAS_REFUND_ACTIVITY,
        bta.HAS_DISPUTE_ACTIVITY,
        bta.FIRST_BALANCE_AVAILABLE_DATE,
        bta.LAST_BALANCE_AVAILABLE_DATE
    FROM charges_aggregated ca

    LEFT JOIN balance_transactions_aggregated bta
        ON ca.INVOICE_ID = bta.INVOICE_ID
)

SELECT *
FROM charges_aggregated_join_balance_transactions_aggregated;