USE DATABASE LEDGERLY;
USE SCHEMA ANALYTICS;

CREATE OR REPLACE TABLE LEDGERLY.ANALYTICS.BQ01A_STRIPE_INVOICE_2024_JUNE AS

-- company side: june 2024 invoices processed through stripe
-- grain: one row per invoice
-- excludes send_invoice — those are paid outside stripe and have no balance transaction rows
WITH invoices_filtered AS
(
    SELECT
        INVOICE_ID,
        CUSTOMER_ID,
        INVOICE_AMOUNT_PAID_CENTS
    FROM LEDGERLY.STAGING.STG_INVOICES
    WHERE INVOICE_CREATED              >= '2024-06-01'
      AND INVOICE_CREATED              <  '2024-07-01'
      AND INVOICE_PAID                 = TRUE
      AND INVOICE_COLLECTION_METHOD    = 'charge_automatically'
)

SELECT *
FROM invoices_filtered;