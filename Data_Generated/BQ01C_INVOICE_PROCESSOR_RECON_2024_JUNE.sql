USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ01C_INVOICE_PROCESSOR_RECON_2024_JUNE AS

-- BUSINESS QUESTION
-- Which June invoices did Stripe collect a different amount for than billing
-- recorded, and what evidence explains each one?
--
-- WHY THIS TABLE EXISTS
-- BQ01A holds what the company billed. BQ01B holds what Stripe collected, plus
-- everything that happened to the charge attempts, refunds, and disputes along
-- the way. Both are already one row per invoice. This table is where they meet.
-- Nobody watches automatic billing in real time, so this comparison is the only
-- point where a mismatch gets caught at all.
--
-- WHAT COMES OUT
-- Gap invoices only. An invoice where billing and processor amounts agree is
-- settled — it is dropped here, no matter what happened along the way. A won
-- dispute that returned in full, or a retry that eventually succeeded, is not
-- worth a reviewer's time if the customer was ultimately charged correctly.
--
-- THE SEQUENCE
--   1. invoice_filtered              — the company side, from BQ01A
--   2. processor_filtered            — the Stripe side, from BQ01B
--   3. invoice_join_processor        — line the two up, keep every invoice
--   4. invoice_join_processor_recon  — measure the gap, attach the evidence, drop the matches


-- STEP 1 of 4 — Question: what did the company believe it collected?
-- BQ01A is already scoped to June invoices billed automatically and marked paid.
-- No further filtering needed here; this is the full company-side cohort.

WITH invoice_filtered AS
(
    SELECT
        INVOICE_ID,
        CUSTOMER_ID,
        INVOICE_AMOUNT_PAID_CENTS
    FROM LEDGERLY.ANALYTICS.BQ01A_STRIPE_INVOICE_2024_JUNE
),


-- STEP 2 of 4 — Question: what does Stripe show for those same invoices?
-- BQ01B is one row per invoice: the net amount collected, three separate charge
-- attempt counts, and four flags covering refunds and disputes.
--
-- Three charge counts, not one, because a single count would hide which kind of
-- attempt happened:
--   PROCESSOR_CAPTURED_CHARGE_COUNT     — actually collected money
--   PROCESSOR_UNCAPTURED_CHARGE_COUNT   — approved, but the money was never taken
--   PROCESSOR_FAILED_CHARGE_COUNT       — the card issuer declined it outright
--
-- HAS_DISPUTE_ACTIVITY means money was actually lost, net of any reversal.
-- HAS_DISPUTE_RAISED means a dispute happened at all, win or lose.
-- HAS_DISPUTE_REVERSAL means the company won and the money came back — carried
-- through so a won dispute is identifiable on its own, not just inferred from
-- HAS_DISPUTE_ACTIVITY being 0.
--
-- HAS_CHARGE_WITHOUT_BALANCE and HAS_BALANCE_WITHOUT_CHARGE compare Stripe's own
-- two tables against each other, a different problem from billing vs Stripe.

processor_filtered AS
(
    SELECT
        INVOICE_ID,
        PROCESSOR_BALANCE_AMOUNT_CENTS,
        PROCESSOR_CAPTURED_CHARGE_COUNT,
        PROCESSOR_UNCAPTURED_CHARGE_COUNT,
        PROCESSOR_FAILED_CHARGE_COUNT,
        HAS_REFUND_ACTIVITY,
        HAS_DISPUTE_ACTIVITY,
        HAS_DISPUTE_RAISED,
        HAS_DISPUTE_REVERSAL,
        HAS_CHARGE_WITHOUT_BALANCE,
        HAS_BALANCE_WITHOUT_CHARGE
    FROM LEDGERLY.ANALYTICS.BQ01B_STRIPE_PAYMENT_2024_JUNE
),


-- STEP 3 of 4 — Question: how do the two sides line up, invoice by invoice?
-- LEFT JOIN from the company side, not INNER JOIN: an invoice the company billed
-- with nothing at all on Stripe's side is the most serious finding in the whole
-- report, and an INNER JOIN would delete exactly those rows.
-- COALESCE turns a missing processor row into zeros rather than nulls, so the
-- gap calculation in step 4 returns the full invoice amount instead of null.

invoice_join_processor AS
(
    SELECT
        i.INVOICE_ID,
        i.CUSTOMER_ID,
        i.INVOICE_AMOUNT_PAID_CENTS,

        COALESCE(p.PROCESSOR_BALANCE_AMOUNT_CENTS, 0)      AS PROCESSOR_BALANCE_AMOUNT_CENTS,
        COALESCE(p.PROCESSOR_CAPTURED_CHARGE_COUNT, 0)     AS PROCESSOR_CAPTURED_CHARGE_COUNT,
        COALESCE(p.PROCESSOR_UNCAPTURED_CHARGE_COUNT, 0)   AS PROCESSOR_UNCAPTURED_CHARGE_COUNT,
        COALESCE(p.PROCESSOR_FAILED_CHARGE_COUNT, 0)       AS PROCESSOR_FAILED_CHARGE_COUNT,

        COALESCE(p.HAS_REFUND_ACTIVITY, 0)                 AS HAS_REFUND_ACTIVITY,
        COALESCE(p.HAS_DISPUTE_ACTIVITY, 0)                AS HAS_DISPUTE_ACTIVITY,
        COALESCE(p.HAS_DISPUTE_RAISED, 0)                  AS HAS_DISPUTE_RAISED,
        COALESCE(p.HAS_DISPUTE_REVERSAL, 0)                AS HAS_DISPUTE_REVERSAL,

        COALESCE(p.HAS_CHARGE_WITHOUT_BALANCE, 0)          AS HAS_CHARGE_WITHOUT_BALANCE,
        COALESCE(p.HAS_BALANCE_WITHOUT_CHARGE, 0)          AS HAS_BALANCE_WITHOUT_CHARGE

    FROM invoice_filtered i

    LEFT JOIN processor_filtered p
        ON i.INVOICE_ID = p.INVOICE_ID
),


-- STEP 4 of 4 — Question: how big is the gap, and what explains it?
-- The gap alone says something is wrong, never why. Two invoices can have an
-- identical gap for completely different reasons, so each one leaves here with
-- evidence attached and a reviewer knows where to start.
--
-- RECON_GAP_CENTS                    — billed minus collected
-- GAP_DIRECTION                      — which side is higher
-- HAS_NO_PROCESSOR_CHARGE            — zero captured charges
-- HAS_MULTIPLE_PROCESSOR_CHARGES     — more than one captured charge
-- HAS_REFUND / HAS_DISPUTE           — carried from BQ01B. HAS_DISPUTE means
--                                      money was actually lost, after reversal.
-- HAS_DISPUTE_RAISED / HAS_DISPUTE_REVERSAL — carried from BQ01B
-- PROCESSOR_UNCAPTURED_CHARGE_COUNT  — approved, never collected
-- PROCESSOR_FAILED_CHARGE_COUNT      — declined outright
-- HAS_CHARGE_WITHOUT_BALANCE / HAS_BALANCE_WITHOUT_CHARGE — Stripe's own two
--                                      tables disagree with each other
-- BALANCE_REDUCTION_SEVERITY         — how much of the balance is left vs billed
--
-- The WHERE clause is deliberately amount-only. An invoice whose amounts agree
-- is settled and gets dropped, even if a flag is set on it. Flags explain gaps;
-- they do not create them.

invoice_join_processor_recon AS
(
    SELECT
        INVOICE_ID,
        CUSTOMER_ID,
        INVOICE_AMOUNT_PAID_CENTS,
        PROCESSOR_BALANCE_AMOUNT_CENTS,

        INVOICE_AMOUNT_PAID_CENTS - PROCESSOR_BALANCE_AMOUNT_CENTS AS RECON_GAP_CENTS,

        CASE WHEN PROCESSOR_CAPTURED_CHARGE_COUNT = 0 THEN 1 ELSE 0 END AS HAS_NO_PROCESSOR_CHARGE,
        CASE WHEN PROCESSOR_CAPTURED_CHARGE_COUNT > 1 THEN 1 ELSE 0 END AS HAS_MULTIPLE_PROCESSOR_CHARGES,

        PROCESSOR_UNCAPTURED_CHARGE_COUNT,
        PROCESSOR_FAILED_CHARGE_COUNT,

        HAS_REFUND_ACTIVITY         AS HAS_REFUND,
        HAS_DISPUTE_ACTIVITY        AS HAS_DISPUTE,
        HAS_DISPUTE_RAISED,
        HAS_DISPUTE_REVERSAL,
        HAS_CHARGE_WITHOUT_BALANCE,
        HAS_BALANCE_WITHOUT_CHARGE,

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
FROM invoice_join_processor_recon;