

BQ02_JUNE_CHARGEBACK_REVENUE_LOST.sql
File

BQ03A_SUBSCRIPTION_MRR_BY_MONTH_2024.sql
File

BQ01A_STRIPE_INVOICE_2024_JUNE.sql
File

Panel 14.png
need to fix this, panel 14.

the resulting of what is shown in panel 13 ( processing and aggregating charge tables and see what happens to charges for one single invoice ), is then joined back to the balance transaction table. so we dont just start with "after the join".

that does not explain what being joined in the first place.

tell readers what was joined, and what happened after they are joined.

Panel 14(1).png
this was panel 14. make a prompt for panel 14 using the new script using this same illustration ideas and same color scheme.

Create a 1080 × 1080 LinkedIn carousel panel using the supplied existing P14 as the direct composition reference.

Preserve the same illustration idea, visual structure, icon colors, and pale-yellow Stripe-side background. Use the exact solid background color #FFF4C7.

Use Comic Sans MS. All text must be regular, not bold. Use large black text with comfortable line spacing. Do not show a panel number.

Panel text must appear exactly as written:

Each of the three charge-table results has one row per invoice. They are joined by invoice ID with the balance-transaction result, which also has one row per invoice.

After the join, each invoice has one summary row showing:

how much money was collected, from the balance transaction table

how many charges succeeded and were captured

how many charges succeeded but were not captured

how many charges failed

Visual concept:

Reuse the original P14 idea of four separate inputs flowing into one large final summary document.

Show four small, vertically stacked input cards:

A green dollar sign representing the money collected from the balance-transaction result.

A green check representing charges that succeeded and were captured.

A purple check inside a purple circle representing charges that succeeded but were not captured.

A burnt-orange X representing failed charges.

Connect all four input cards with thick black arrows to one large document on the right. The document represents the single summary row created for each invoice.

Make the join itself visible. Place a small simple label, “JOIN BY INVOICE ID,” near the arrows where the four inputs flow into the final document. Use regular black Comic Sans MS.

The illustration must clearly show that the balance-transaction result and the three charge-table results are the four things being joined. It must also show that they become one combined invoice summary after the join.

Layout:

Use the left half for the complete panel text. Use the right half for the four input cards, joining arrows, and final summary document.

Keep the illustration close to the original P14 composition:

four vertically stacked input cards in the center-right

black arrows flowing from the cards

one large outlined document on the far right

simple thick black outlines

flat office-comic appearance

plenty of space for readable text

If needed, make the illustration slightly smaller than the original so the longer revised text remains large and readable. Do not shorten or rewrite the text to create space.

Avoid:

changing, trimming, or reordering any panel text

starting the explanation with only “After the join”

hiding what was joined

showing the three charge results as a UNION or vertical stack of database rows

suggesting that the four results remain separate after the join

tiny text

bold body text

any font other than Comic Sans MS

gradients, textures, shadows, glow, or realistic rendering

blue elements

red text

logos or watermarks

visible panel numbers

decorative office objects

changing or approximating the background color #FFF4C7


gen

Generated the revised P14 using the new script and original illustration concept.

Generated image: Four inputs, one invoice summary


Edit


Generated image: Four inputs, one invoice summary
Generated image: Four inputs, one invoice summary
Generated image: Four inputs, one invoice summary

Generated image: Invoice ID workflow on pale yellow
Generated image: Invoice ID workflow on pale yellow
Generated image: Invoice ID workflow on pale yellow

p12. each read are joined. then the result is joined to balance transaction table. t or f

Cannot verify yet.

What is confirmed:

The three charge reads are aggregated separately.

They are joined horizontally by INVOICE_ID.

The balance-transaction result is also joined by INVOICE_ID.

What is not confirmed is the sequence: whether the three charge results are joined first and that completed result is then joined to the balance-transaction result, or whether all four results are joined inside the same combined CTE.

We need BQ01B_STRIPE_PAYMENT_2024_JUNE.sql to answer T or F.


go read it

False.

The three charge-table results are not joined together first and then joined to the balance-transaction result.

Inside the combined CTE, the joins happen sequentially:

charge_balance_aggregated

joins refund_dispute_aggregated

joins captured_charges_aggregated

joins uncaptured_charges_aggregated

joins failed_charges_aggregated

joins dispute_status_aggregated

All six inputs are already one row per invoice. They are joined horizontally using INVOICE_ID.

So P14’s meaning is correct: the three charge results and balance-transaction results are brought together into one invoice summary. But saying, “the three reads are joined first, then their result is joined to the balance-transaction table,” would be technically wrong.



BQ01B_STRIPE_PAYMENT_2024_JUNE.sql
File

BQ01C_INVOICE_PROCESSOR_RECON_2024_JUNE.sql
File

BQ01A_STRIPE_INVOICE_2024_JUNE(1).sql
File

Under your meaning, yes: each count column signals whether that type of charge happened.

But check whether it is greater than zero, not whether it is nonempty:

Captured count > 0   → captured charge happened
Uncaptured count > 0 → uncaptured charge happened
Failed count > 0     → failed charge happened
After the join, COALESCE changes missing values to 0. Therefore, every column is nonempty:

0 = did not happen
1 or more = happened, and shows how many times
Technically these are count columns being used like flags, rather than true Boolean columns.


i dont understand why we need to do it in 3 reads. why cant we do it once and create 3 columns at the same time on the same cte

You can do it once and create all three columns in one CTE. Three reads are not technically necessary.

Use conditional aggregation:

charges_aggregated AS
(
    SELECT
        c.INVOICE_ID,

        COUNT(DISTINCT CASE
            WHEN c.CHARGE_STATUS = 'succeeded'
             AND c.CHARGE_CAPTURED = TRUE
            THEN c.CHARGE_ID
        END) AS PROCESSOR_CAPTURED_CHARGE_COUNT,

        COUNT(DISTINCT CASE
            WHEN c.CHARGE_STATUS = 'succeeded'
             AND c.CHARGE_CAPTURED = FALSE
            THEN c.CHARGE_ID
        END) AS PROCESSOR_UNCAPTURED_CHARGE_COUNT,

        COUNT(DISTINCT CASE
            WHEN c.CHARGE_STATUS = 'failed'
            THEN c.CHARGE_ID
        END) AS PROCESSOR_FAILED_CHARGE_COUNT

    FROM LEDGERLY.STAGING.STG_CHARGES AS c

    INNER JOIN LEDGERLY.ANALYTICS.BQ01A_STRIPE_INVOICE_2024_JUNE AS i
        ON c.INVOICE_ID = i.INVOICE_ID

    GROUP BY c.INVOICE_ID
)
This reads the charges table once and produces one row per invoice with all three count columns.

The current three-CTE design separates each condition for readability, but it creates more SQL and requires three extra joins in combined. I see no business requirement that requires three separate CTEs.

For this query, one CTE with three conditional counts is cleaner. P13’s “three reads” explanation exists only because of how the current SQL was written, not because the analysis requires three reads.


redo bq01b using that then

Updated BQ01B_STRIPE_PAYMENT_2024_JUNE.sql.

Changes:

Replaced three charge CTEs with one charges_aggregated CTE.

Created captured, uncaptured, and failed counts using conditional aggregation.

Reduced the pipeline from seven steps to five.

combined now joins one charge result instead of three.

Changed failed-charge logic to CHARGE_STATUS = 'failed'.


BQ01B_STRIPE_PAYMENT_2024_JUNE.sql
Code


Library
/
Linkedin carousel
/
BQ01B_STRIPE_PAYMENT_2024_JUNE.sql


ALTER WAREHOUSE COMPUTE_WH SET AUTO_SUSPEND = 5;
USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

-- CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ01B_STRIPE_PAYMENT_2024_JUNE AS

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
--   4. charges_aggregated                 — one read of STG_CHARGES, three attempt counts
--   5. combined                           — one row per invoice, ready for BQ01C
--
-- WHY EACH STEP AGGREGATES BEFORE JOINING
-- Steps 2 and 4 read different tables and must never be joined at row level.
-- One invoice with 2 captured charges and 2 charge balance rows, joined on
-- INVOICE_ID alone, produces 4 rows: SUM doubles to $200 when the real total
-- is $100, while COUNT(DISTINCT CHARGE_ID) still reads 2 and looks correct.
-- Aggregating each side to invoice grain first removes the fan-out, and keeps
-- an invoice present even when one side has no matching row — which is exactly
-- the missing-data case reconciliation is supposed to surface, not delete.


-- STEP 1 of 5 — Question: which money rows belong to a June invoice at all?
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


-- STEP 2 of 5 — Question: how much did Stripe charge against this invoice?
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


-- STEP 3 of 5 — Question: how much went back out, and did any of it come back?
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


-- STEP 4 of 5 — Question: what happened to the charge attempts for this invoice?
-- Read STG_CHARGES once and create three counts with conditional aggregation.
--
-- Captured: CHARGE_STATUS = 'succeeded' and CHARGE_CAPTURED = TRUE.
-- The issuer approved the charge and the funds were taken.
--
-- Uncaptured: CHARGE_STATUS = 'succeeded' and CHARGE_CAPTURED = FALSE.
-- The issuer approved the charge, but the funds were never taken.
--
-- Failed: CHARGE_STATUS = 'failed'. The attempt collected no money and created
-- no balance transaction row.
--
-- The result is one row per invoice with all three charge-attempt counts.

charges_aggregated AS
(
    SELECT
        c.INVOICE_ID,

        COUNT(DISTINCT CASE
            WHEN c.CHARGE_STATUS   = 'succeeded'
             AND c.CHARGE_CAPTURED = TRUE
            THEN c.CHARGE_ID
        END) AS PROCESSOR_CAPTURED_CHARGE_COUNT,

        COUNT(DISTINCT CASE
            WHEN c.CHARGE_STATUS   = 'succeeded'
             AND c.CHARGE_CAPTURED = FALSE
            THEN c.CHARGE_ID
        END) AS PROCESSOR_UNCAPTURED_CHARGE_COUNT,

        COUNT(DISTINCT CASE
            WHEN c.CHARGE_STATUS = 'failed'
            THEN c.CHARGE_ID
        END) AS PROCESSOR_FAILED_CHARGE_COUNT

    FROM LEDGERLY.STAGING.STG_CHARGES c

    INNER JOIN LEDGERLY.ANALYTICS.BQ01A_STRIPE_INVOICE_2024_JUNE fi
        ON c.INVOICE_ID = fi.INVOICE_ID

    GROUP BY c.INVOICE_ID
),


-- STEP 5 of 5 — Question: what does Stripe show for this invoice, all in one row?
-- Three inputs, each already one row per invoice, so joining on INVOICE_ID cannot
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
        COALESCE(cb.INVOICE_ID, rd.INVOICE_ID, ca.INVOICE_ID)                   AS INVOICE_ID,

        -- money collected, from the balance transaction table only
        COALESCE(cb.CHARGE_AMOUNT_CENTS, 0)
          + COALESCE(rd.REFUND_DISPUTE_AMOUNT_CENTS, 0)                         AS PROCESSOR_BALANCE_AMOUNT_CENTS,

        -- charge attempt outcomes, from STG_CHARGES only
        COALESCE(ca.PROCESSOR_CAPTURED_CHARGE_COUNT  , 0)                       AS PROCESSOR_CAPTURED_CHARGE_COUNT,
        COALESCE(ca.PROCESSOR_UNCAPTURED_CHARGE_COUNT, 0)                       AS PROCESSOR_UNCAPTURED_CHARGE_COUNT,
        COALESCE(ca.PROCESSOR_FAILED_CHARGE_COUNT    , 0)                       AS PROCESSOR_FAILED_CHARGE_COUNT,

        -- refund and dispute outcomes, from the balance transaction table
        COALESCE(  rd.HAS_REFUND_ACTIVITY, 0)                                   AS HAS_REFUND_ACTIVITY,
        COALESCE( rd.HAS_DISPUTE_ACTIVITY, 0)                                   AS HAS_DISPUTE_ACTIVITY,
        COALESCE(   rd.HAS_DISPUTE_RAISED, 0)                                   AS HAS_DISPUTE_RAISED,
        COALESCE( rd.HAS_DISPUTE_REVERSAL, 0)                                   AS HAS_DISPUTE_REVERSAL,

        -- captured charge recorded in STG_CHARGES, but no charge balance row:
        -- money that should have been recorded and was not.
        CASE WHEN COALESCE(ca.PROCESSOR_CAPTURED_CHARGE_COUNT, 0) > 0
              AND cb.INVOICE_ID IS NULL
             THEN 1 ELSE 0 END                                                  AS HAS_CHARGE_WITHOUT_BALANCE,

        -- charge balance row exists, but no captured charge in STG_CHARGES:
        -- money recorded that no charge row accounts for.
        CASE WHEN cb.INVOICE_ID IS NOT NULL
              AND COALESCE(ca.PROCESSOR_CAPTURED_CHARGE_COUNT, 0) = 0
             THEN 1 ELSE 0 END                                                  AS HAS_BALANCE_WITHOUT_CHARGE,

        cb.FIRST_CHARGE_AVAILABLE_DATE,
        cb.LAST_CHARGE_AVAILABLE_DATE

    FROM charge_balance_aggregated cb

    FULL OUTER JOIN refund_dispute_aggregated rd
        ON cb.INVOICE_ID = rd.INVOICE_ID

    FULL OUTER JOIN charges_aggregated ca
        ON COALESCE(cb.INVOICE_ID, rd.INVOICE_ID) = ca.INVOICE_ID
)


SELECT *
FROM combined;
