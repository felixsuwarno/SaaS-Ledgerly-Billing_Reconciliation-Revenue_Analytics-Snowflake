USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ01C_INVOICE_PROCESSOR_RECON_2024_JUNE AS

-- this query is the reconciliation steps where we compare company's side invoice against
-- processor's side processed payments
-- output: gap invoices only
-- gap = invoice_amount_paid_cents - processor_balance_amount_cents
-- where processor_balance_amount_cents = sum of charge + refund + dispute bt rows
-- a gap means stripe processed a different amount than what billing recorded
-- refunds and disputes are classified in this query

-- get the company's side
WITH invoice_filtered AS
(
    SELECT
        INVOICE_ID,
        CUSTOMER_ID,
        INVOICE_AMOUNT_PAID_CENTS
    FROM LEDGERLY.ANALYTICS.BQ01A_STRIPE_INVOICE_2024_JUNE
),

-- get the processor's side
processor_filtered AS
(
    SELECT
        INVOICE_ID,
        PROCESSOR_CHARGE_COUNT,
        PROCESSOR_BALANCE_AMOUNT_CENTS,
        HAS_REFUND_ACTIVITY,
        HAS_DISPUTE_ACTIVITY
    FROM LEDGERLY.ANALYTICS.BQ01B_STRIPE_PAYMENT_2024_JUNE
),

-- join both sides
-- LEFT JOIN: invoices with no processor match appear as gaps, not disappear
-- COALESCE: ensures gap calculation works when processor side is null
invoice_join_processor AS
(
    SELECT
        i.INVOICE_ID,
        i.CUSTOMER_ID,
        i.INVOICE_AMOUNT_PAID_CENTS,
        COALESCE(p.PROCESSOR_CHARGE_COUNT, 0)         AS PROCESSOR_CHARGE_COUNT,
        COALESCE(p.PROCESSOR_BALANCE_AMOUNT_CENTS, 0) AS PROCESSOR_BALANCE_AMOUNT_CENTS,
        COALESCE(p.HAS_REFUND_ACTIVITY, 0)            AS HAS_REFUND_ACTIVITY,
        COALESCE(p.HAS_DISPUTE_ACTIVITY, 0)           AS HAS_DISPUTE_ACTIVITY
    FROM invoice_filtered i

    LEFT JOIN processor_filtered p
        ON i.INVOICE_ID = p.INVOICE_ID
),

-- calculate the gap and filter to gap invoices only
-- gap positive: billing recorded more than stripe processed
-- gap negative: stripe processed more than billing recorded
-- full refund/dispute: processor balance became 0
-- partial refund/dispute: processor balance is still above 0 but below invoice paid amount
invoice_join_processor_recon AS
(
    SELECT
        INVOICE_ID,
        CUSTOMER_ID,
        INVOICE_AMOUNT_PAID_CENTS,
        PROCESSOR_CHARGE_COUNT,
        PROCESSOR_BALANCE_AMOUNT_CENTS,
        INVOICE_AMOUNT_PAID_CENTS - PROCESSOR_BALANCE_AMOUNT_CENTS AS RECON_GAP_CENTS,
        HAS_REFUND_ACTIVITY AS IS_REFUND,
        HAS_DISPUTE_ACTIVITY AS IS_DISPUTE,

        CASE
            WHEN HAS_REFUND_ACTIVITY = 1
             AND HAS_DISPUTE_ACTIVITY = 1
                THEN 1
            ELSE 0
        END AS IS_BOTH,

        CASE
            WHEN PROCESSOR_CHARGE_COUNT = 0
                THEN 'NO PROCESSOR CHARGE'

            WHEN PROCESSOR_CHARGE_COUNT > 1
                THEN 'MULTIPLE PROCESSOR CHARGES'

            WHEN HAS_REFUND_ACTIVITY = 1
             AND HAS_DISPUTE_ACTIVITY = 1
                THEN 'REFUND AND DISPUTE'

            WHEN HAS_REFUND_ACTIVITY = 1
             AND PROCESSOR_BALANCE_AMOUNT_CENTS = 0
                THEN 'FULL REFUND'

            WHEN HAS_REFUND_ACTIVITY = 1
             AND PROCESSOR_BALANCE_AMOUNT_CENTS > 0
             AND PROCESSOR_BALANCE_AMOUNT_CENTS < INVOICE_AMOUNT_PAID_CENTS
                THEN 'PARTIAL REFUND'

            WHEN HAS_DISPUTE_ACTIVITY = 1
             AND PROCESSOR_BALANCE_AMOUNT_CENTS = 0
                THEN 'FULL DISPUTE'

            WHEN HAS_DISPUTE_ACTIVITY = 1
             AND PROCESSOR_BALANCE_AMOUNT_CENTS > 0
             AND PROCESSOR_BALANCE_AMOUNT_CENTS < INVOICE_AMOUNT_PAID_CENTS
                THEN 'PARTIAL DISPUTE'

            WHEN PROCESSOR_BALANCE_AMOUNT_CENTS > INVOICE_AMOUNT_PAID_CENTS
                THEN 'STRIPE PROCESSED MORE THAN BILLING'

            ELSE 'UNKNOWN'
        END AS GAP_REASON
    FROM invoice_join_processor
    WHERE INVOICE_AMOUNT_PAID_CENTS <> PROCESSOR_BALANCE_AMOUNT_CENTS
)

SELECT *
FROM invoice_join_processor_recon;