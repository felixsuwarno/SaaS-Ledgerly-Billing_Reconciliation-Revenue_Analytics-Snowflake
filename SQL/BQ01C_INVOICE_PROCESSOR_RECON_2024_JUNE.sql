USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

-- CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ01C_INVOICE_PROCESSOR_RECON_2024_JUNE AS

-- this query is the reconciliation steps where we compare company's side invoice against
-- processor's side processed payments
-- output: gap invoices only
-- gap = invoice_amount_paid_cents - processor_balance_amount_cents
-- where processor_balance_amount_cents = sum of charge + refund + dispute bt rows
-- a gap means stripe processed a different amount than what billing recorded
-- refunds and disputes are classified in this query


-- get the company's side
-- Step 1: Pull company side from BQ01A.
-- BQ01A contains what the billing system recorded — one row per June invoice with the amount the company expects to have collected through Stripe. 
-- It feeds the company side of the comparison.

WITH invoice_filtered AS
(
    SELECT
        INVOICE_ID,
        CUSTOMER_ID,
        INVOICE_AMOUNT_PAID_CENTS
    FROM LEDGERLY.ANALYTICS.BQ01A_STRIPE_INVOICE_2024_JUNE
),


-- get the processor's side
-- Step 2: Pull processor side from BQ01B.
-- BQ01B contains what Stripe recorded — one row per June invoice with the net balance transaction activity after charges, refunds, and disputes. 
-- It feeds the processor side of the comparison.

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


-- Step 3: LEFT JOIN company side to processor side on invoice ID, with COALESCE on processor columns.
-- Both tables are already at the same grain so the join is straightforward. A LEFT JOIN is used, not INNER JOIN, 
-- because an invoice with no processor match must still appear as a gap in the output. 
-- COALESCE converts null processor values to zero so the gap calculation always produces a number rather than null.

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

-- Filters — keeps only invoices where the billing amount and processor balance don't match. 
-- Matching invoices are excluded here.

-- RECON_GAP_CENTS 			— billing minus processor balance
-- GAP_DIRECTION 			— which side is higher
-- HAS_NO_PROCESSOR_CHARGE 		— true if charge count is 0
-- HAS_MULTIPLE_PROCESSOR_CHARGES 	— true if charge count is more than 1
-- HAS_REFUND / HAS_DISPUTE 		— carried over from the input table

-- BALANCE_REDUCTION_SEVERITY — full, partial, or none, 
-- based on how much of the processor balance is left versus what billing recorded

invoice_join_processor_recon AS
(
    SELECT
        INVOICE_ID,
        CUSTOMER_ID,
        INVOICE_AMOUNT_PAID_CENTS,
        PROCESSOR_CHARGE_COUNT,
        PROCESSOR_BALANCE_AMOUNT_CENTS,
        INVOICE_AMOUNT_PAID_CENTS - PROCESSOR_BALANCE_AMOUNT_CENTS AS RECON_GAP_CENTS,
        CASE WHEN PROCESSOR_CHARGE_COUNT = 0 THEN 1 ELSE 0 END AS HAS_NO_PROCESSOR_CHARGE,
        CASE WHEN PROCESSOR_CHARGE_COUNT > 1 THEN 1 ELSE 0 END AS HAS_MULTIPLE_PROCESSOR_CHARGES,
        HAS_REFUND_ACTIVITY  AS HAS_REFUND,
        HAS_DISPUTE_ACTIVITY AS HAS_DISPUTE,
        CASE
            WHEN PROCESSOR_BALANCE_AMOUNT_CENTS = 0 THEN 'FULL'
            WHEN PROCESSOR_BALANCE_AMOUNT_CENTS > 0
             AND PROCESSOR_BALANCE_AMOUNT_CENTS < INVOICE_AMOUNT_PAID_CENTS THEN 'PARTIAL'
            ELSE 'NONE'
        END AS BALANCE_REDUCTION_SEVERITY,
        CASE
            WHEN INVOICE_AMOUNT_PAID_CENTS > PROCESSOR_BALANCE_AMOUNT_CENTS THEN 'BILLING_HIGHER'
            WHEN INVOICE_AMOUNT_PAID_CENTS < PROCESSOR_BALANCE_AMOUNT_CENTS THEN 'PROCESSOR_HIGHER'
            ELSE 'MATCHED'
        END AS GAP_DIRECTION
    FROM invoice_join_processor
    WHERE INVOICE_AMOUNT_PAID_CENTS <> PROCESSOR_BALANCE_AMOUNT_CENTS
)


SELECT *
FROM invoice_join_processor_recon;SELECT *
FROM invoice_join_processor_recon;