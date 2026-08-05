USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ01B_STRIPE_PAYMENT_2024_JUNE AS

-- BUSINESS QUESTION
-- For each June invoice the company billed automatically, how much did Stripe
-- actually collect, and what happened to the charge attempts along the way?
--
-- WHY THIS TABLE EXISTS
-- BQ01A already has one row per invoice: what the company believes it billed.
-- This table produces the matching side: one row per invoice, what Stripe shows.
-- BQ01C compares the two. Both sides must be one row per invoice or the
-- comparison silently multiplies.
--
-- WHERE TO START
-- STG_BALANCE_TRANSACTIONS. It is the only table holding money amounts, and it
-- records four event types against an invoice: charge, refund, dispute, and
-- dispute_reversal. One invoice can have several of these, one row each.
--
-- WHAT THE BALANCE TRANSACTION TABLE CANNOT ANSWER
-- It only records events where money actually moved. A charge that was declined,
-- or approved but never captured, never appears there at all. So it cannot say
-- how many charge attempts an invoice took, or what became of the ones that did
-- not collect. Those answers exist only in STG_CHARGES, read separately below.
--
-- THE SEQUENCE
--   1. balance_transactions_filtered      — scope every money row to a June invoice
--   2. charge_balance_aggregated          — how much was charged, per invoice
--   3. refund_dispute_aggregated          — how much went back out and came back
--   4. captured_charges_aggregated        — read 1 of STG_CHARGES: approved + captured
--   5. uncaptured_charges_aggregated      — read 2 of STG_CHARGES: approved, not captured
--   6. failed_charges_aggregated          — read 3 of STG_CHARGES: not approved
--   7. combined                           — one row per invoice, ready for BQ01C
--
-- WHY EACH STEP AGGREGATES BEFORE JOINING
-- Steps 2 and 4 read different tables and must never be joined at row level.
-- One invoice with 2 captured charges and 2 charge balance rows, joined on
-- INVOICE_ID alone, produces 4 rows: SUM doubles to $200 when the real total
-- is $100, while COUNT(DISTINCT CHARGE_ID) still reads 2 and looks correct.
-- Aggregating each side to invoice grain first removes the fan-out, and keeps
-- an invoice present even when one side has no matching row — which is exactly
-- the missing-data case reconciliation is supposed to surface, not delete.


-- STEP 1 of 7 — Question: which money rows belong to a June invoice at all?
-- INNER JOIN to BQ01A scopes everything downstream to the same invoice cohort
-- the company side uses. Four categories are kept; anything else on this table
-- is Stripe's own accounting, not money owed against this invoice.

WITH balance_transactions_filtered AS
(
    SELECT
        bt.INVOICE_ID,
        bt.BALANCE_TRANSACTION_ID,
        bt.BALANCE_REPORTING_CATEGORY,
        bt.BALANCE_AMOUNT_CENTS,
        CAST(bt.BALANCE_AVAILABLE_ON AS DATE) AS BALANCE_AVAILABLE_DATE
    FROM LEDGERLY.STAGING.STG_BALANCE_TRANSACTIONS bt

    INNER JOIN LEDGERLY.ANALYTICS.BQ01A_STRIPE_INVOICE_2024_JUNE fi
        ON bt.INVOICE_ID = fi.INVOICE_ID

    WHERE bt.BALANCE_REPORTING_CATEGORY IN ('charge', 'refund', 'dispute', 'dispute_reversal')

    -- dispute_reversal is included deliberately. When the company wins a dispute,
    -- Stripe returns the disputed amount as a separate positive adjustment row.
    -- Excluding it leaves the original negative dispute row unanswered, so a won
    -- dispute reads as a permanent loss and the invoice lands in the final report
    -- as a gap when the money was in fact recovered.
    --
    -- Scope note: no filter on BALANCE_AVAILABLE_DATE. A June invoice can be
    -- refunded in July, and that refund still belongs to the June invoice.
    -- So "June" here means the invoice cohort, not the transaction date.
),


-- STEP 2 of 7 — Question: how much did Stripe charge against this invoice?
-- Charge rows only. Reads balance transactions and nothing else, so an invoice
-- keeps its amount even when STG_CHARGES has no matching row.

charge_balance_aggregated AS
(
    SELECT
        INVOICE_ID,
        SUM(BALANCE_AMOUNT_CENTS)      AS CHARGE_AMOUNT_CENTS,
        MIN(BALANCE_AVAILABLE_DATE)    AS FIRST_CHARGE_AVAILABLE_DATE,
        MAX(BALANCE_AVAILABLE_DATE)    AS LAST_CHARGE_AVAILABLE_DATE
    FROM balance_transactions_filtered
    WHERE BALANCE_REPORTING_CATEGORY = 'charge'
    GROUP BY INVOICE_ID
),


-- STEP 3 of 7 — Question: how much went back out, and did any of it come back?
-- Refunds, disputes and dispute reversals are all rows in this same table.
--
-- How a dispute actually behaves across rows:
--   customer disputes  -> a 'dispute' row is written, NEGATIVE. Stripe pulls the
--                         money from the balance immediately, before any outcome.
--   company wins       -> a SECOND row is written, 'dispute_reversal', POSITIVE,
--                         equal to the disputed amount. Stripe returns the money.
--   company loses      -> no second row is ever written.
--
-- The original dispute row never changes. It stays negative permanently, win or
-- lose. A win is not a correction to that row, it is an additional offsetting
-- row. So the only way to read the outcome is to sum the two categories together:
-- cancelling out means the money came back, still negative means it was lost.
--
-- A refund behaves differently. It happens once against a charge and never
-- reverses, so its existence alone tells the whole story. That is why refund
-- carries a flag here while charge attempts carry counts.

refund_dispute_aggregated AS
(
    SELECT
        INVOICE_ID,

        SUM(CASE WHEN BALANCE_REPORTING_CATEGORY IN ('refund', 'dispute', 'dispute_reversal')
                 THEN BALANCE_AMOUNT_CENTS ELSE 0 END)            AS REFUND_DISPUTE_AMOUNT_CENTS,

        MAX(CASE WHEN BALANCE_REPORTING_CATEGORY = 'refund'
                 THEN 1 ELSE 0 END)                                AS HAS_REFUND_ACTIVITY,

        -- net dispute position: the negative dispute row plus any positive reversal.
        -- flagged only when that net is still negative, so a won dispute that was
        -- returned in full does not read the same as a dispute that was lost.
        CASE WHEN SUM(CASE WHEN BALANCE_REPORTING_CATEGORY IN ('dispute', 'dispute_reversal')
                           THEN BALANCE_AMOUNT_CENTS ELSE 0 END) < 0
             THEN 1 ELSE 0 END                                     AS HAS_DISPUTE_ACTIVITY,

        -- a dispute was raised at all, won or lost. kept separate because the fact
        -- that a customer disputed is worth knowing even when the money came back.
        MAX(CASE WHEN BALANCE_REPORTING_CATEGORY = 'dispute'
                 THEN 1 ELSE 0 END)                                AS HAS_DISPUTE_RAISED,

        -- the reversal itself, so a won dispute is directly identifiable
        MAX(CASE WHEN BALANCE_REPORTING_CATEGORY = 'dispute_reversal'
                 THEN 1 ELSE 0 END)                                AS HAS_DISPUTE_REVERSAL

    FROM balance_transactions_filtered
    GROUP BY INVOICE_ID
),


-- STEP 4 of 7 — READ 1 of STG_CHARGES: charges that collected money.
-- A charge counts only when BOTH conditions hold, because they are two separate
-- events. CHARGE_STATUS = 'succeeded' means the card issuer approved the charge.
-- CHARGE_CAPTURED = TRUE means the funds were then actually taken. Approval
-- without capture collects nothing, so either condition alone would overstate
-- what was collected.
-- Aggregated here and joined at step 7, never joined to balance rows directly.

captured_charges_aggregated AS
(
    SELECT
        c.INVOICE_ID,
        COUNT(DISTINCT c.CHARGE_ID) AS PROCESSOR_CAPTURED_CHARGE_COUNT
    FROM LEDGERLY.STAGING.STG_CHARGES c

    INNER JOIN LEDGERLY.ANALYTICS.BQ01A_STRIPE_INVOICE_2024_JUNE fi
        ON c.INVOICE_ID = fi.INVOICE_ID

    WHERE c.CHARGE_STATUS   = 'succeeded'
      AND c.CHARGE_CAPTURED = TRUE

    GROUP BY c.INVOICE_ID
),


-- STEP 5 of 7 — READ 2 of STG_CHARGES: approved, but nothing was collected.
-- Step 4 filters these out on purpose, since no money moved. But excluded is not
-- the same as invisible: this is money the company expected and did not receive.
-- It produces no balance transaction row at all, so STG_CHARGES is the only place
-- it can be found. Counted separately, outside the collected total.

uncaptured_charges_aggregated AS
(
    SELECT
        c.INVOICE_ID,
        COUNT(DISTINCT c.CHARGE_ID) AS PROCESSOR_UNCAPTURED_CHARGE_COUNT
    FROM LEDGERLY.STAGING.STG_CHARGES c

    INNER JOIN LEDGERLY.ANALYTICS.BQ01A_STRIPE_INVOICE_2024_JUNE fi
        ON c.INVOICE_ID = fi.INVOICE_ID

    WHERE c.CHARGE_STATUS   = 'succeeded'
      AND c.CHARGE_CAPTURED = FALSE

    GROUP BY c.INVOICE_ID
),


-- STEP 6 of 7 — READ 3 of STG_CHARGES: attempts the card issuer declined.
-- A declined charge never moves money, so it leaves no balance transaction row.
-- Without this read, an invoice that took three attempts before one succeeded
-- looks identical to an invoice that succeeded on the first try.

failed_charges_aggregated AS
(
    SELECT
        c.INVOICE_ID,
        COUNT(DISTINCT c.CHARGE_ID) AS PROCESSOR_FAILED_CHARGE_COUNT
    FROM LEDGERLY.STAGING.STG_CHARGES c

    INNER JOIN LEDGERLY.ANALYTICS.BQ01A_STRIPE_INVOICE_2024_JUNE fi
        ON c.INVOICE_ID = fi.INVOICE_ID

    WHERE c.CHARGE_STATUS <> 'succeeded'

    GROUP BY c.INVOICE_ID
),


-- STEP 7 of 7 — Question: what does Stripe show for this invoice, all in one row?
-- Five inputs, each already one row per invoice, so joining on INVOICE_ID cannot
-- fan out. FULL OUTER JOIN throughout: an invoice appearing on only one side is
-- a finding, not a row to drop.
--
-- The two mismatch flags are computed here because this is the only point where
-- both sources meet. Once this table is handed to BQ01C, a charge count of 1 with
-- an amount of 0 is indistinguishable from any other zero, so the direction of a
-- disagreement between Stripe's own two tables has to be captured now or it is lost.

combined AS
(
    SELECT
        COALESCE(cb.INVOICE_ID, rd.INVOICE_ID, cc.INVOICE_ID,
                 uc.INVOICE_ID, fc.INVOICE_ID)                                  AS INVOICE_ID,

        -- money collected, from the balance transaction table only
        COALESCE(cb.CHARGE_AMOUNT_CENTS, 0)
          + COALESCE(rd.REFUND_DISPUTE_AMOUNT_CENTS, 0)                         AS PROCESSOR_BALANCE_AMOUNT_CENTS,

        -- charge attempt outcomes, from STG_CHARGES only
        COALESCE(cc.PROCESSOR_CAPTURED_CHARGE_COUNT, 0)                         AS PROCESSOR_CAPTURED_CHARGE_COUNT,
        COALESCE(uc.PROCESSOR_UNCAPTURED_CHARGE_COUNT, 0)                       AS PROCESSOR_UNCAPTURED_CHARGE_COUNT,
        COALESCE(fc.PROCESSOR_FAILED_CHARGE_COUNT, 0)                           AS PROCESSOR_FAILED_CHARGE_COUNT,

        -- refund and dispute outcomes, from the balance transaction table
        COALESCE(rd.HAS_REFUND_ACTIVITY, 0)                                     AS HAS_REFUND_ACTIVITY,
        COALESCE(rd.HAS_DISPUTE_ACTIVITY, 0)                                    AS HAS_DISPUTE_ACTIVITY,
        COALESCE(rd.HAS_DISPUTE_RAISED, 0)                                      AS HAS_DISPUTE_RAISED,
        COALESCE(rd.HAS_DISPUTE_REVERSAL, 0)                                    AS HAS_DISPUTE_REVERSAL,

        -- captured charge recorded in STG_CHARGES, but no charge balance row:
        -- money that should have been recorded and was not.
        CASE WHEN COALESCE(cc.PROCESSOR_CAPTURED_CHARGE_COUNT, 0) > 0
              AND cb.INVOICE_ID IS NULL
             THEN 1 ELSE 0 END                                                  AS HAS_CHARGE_WITHOUT_BALANCE,

        -- charge balance row exists, but no captured charge in STG_CHARGES:
        -- money recorded that no charge row accounts for.
        CASE WHEN cb.INVOICE_ID IS NOT NULL
              AND COALESCE(cc.PROCESSOR_CAPTURED_CHARGE_COUNT, 0) = 0
             THEN 1 ELSE 0 END                                                  AS HAS_BALANCE_WITHOUT_CHARGE,

        cb.FIRST_CHARGE_AVAILABLE_DATE,
        cb.LAST_CHARGE_AVAILABLE_DATE

    FROM charge_balance_aggregated cb

    FULL OUTER JOIN refund_dispute_aggregated rd
        ON cb.INVOICE_ID = rd.INVOICE_ID

    FULL OUTER JOIN captured_charges_aggregated cc
        ON COALESCE(cb.INVOICE_ID, rd.INVOICE_ID) = cc.INVOICE_ID

    FULL OUTER JOIN uncaptured_charges_aggregated uc
        ON COALESCE(cb.INVOICE_ID, rd.INVOICE_ID, cc.INVOICE_ID) = uc.INVOICE_ID

    FULL OUTER JOIN failed_charges_aggregated fc
        ON COALESCE(cb.INVOICE_ID, rd.INVOICE_ID, cc.INVOICE_ID, uc.INVOICE_ID) = fc.INVOICE_ID
)


SELECT *
FROM combined;
