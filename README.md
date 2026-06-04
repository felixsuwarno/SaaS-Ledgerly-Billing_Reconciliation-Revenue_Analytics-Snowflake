# SaaS-Ledgerly-Billing_Reconciliation-Revenue_Analytics-Snowflake

Payment Processor Reconciliation, Chargeback Restatement Tracking, Failed-Payment Loss, MRR Movement, and Net Revenue Retention by Cohort

<br>

A Snowflake analytics project using synthetic SaaS billing data generated from Stripe’s public documentation as the reference model for invoices, subscriptions, charges, balance transactions, payouts, refunds, and disputes. The project reconciles Ledgerly’s subscription billing against Stripe-style processor activity, explains reconciliation differences, flags prior-period chargebacks, and builds SaaS revenue analysis on top of a trusted billing base.

<br><br>


## ➤ Executive Summary : <br>
**What the project was trying to find out**

- Does Ledgerly’s billing system agree with the payment processor?
- Can the June reconciliation gap be explained clearly enough for month-end close?
- Which chargebacks landed in June but restated earlier closed periods?
- How much June revenue was permanently lost after retries failed?
- How did June MRR move compared with May?
- Which signup cohorts are helping or hurting Net Revenue Retention?

**What the data showed**

- Pending — to be written after the analytics layer is completed

**What the key numbers are**

- Pending — to be written after the analytics layer is completed

**What actions should follow**

- Pending — to be written after the analytics layer is completed

<br><br>
  
## ➤ Project Scope:<br>

This project evaluates how a simulated B2B SaaS company reconciles subscription billing records against Stripe-style payment processor records.

The analysis focuses on two areas: billing reconciliation and revenue analytics.

At the billing reconciliation level, the project compares invoices, charges, balance transactions, payouts, refunds, and disputes. The goal is to determine whether invoices marked as collected are supported by processor-side activity, and whether differences can be explained by timing, fees, duplicate charges, refunds, disputes, or invalid test-mode records.

At the revenue analytics level, the project measures failed-payment loss, MRR movement, and Net Revenue Retention by signup cohort. The goal is to show whether recurring revenue is growing cleanly after the billing and payment data has been reconciled.

The project uses Snowflake as the warehouse layer. Raw CSV files are loaded into Snowflake, organized into RAW, STAGING, and ANALYTICS schemas, and transformed into reporting-ready views.

The dataset is synthetic, not actual company production data. It was generated from Stripe’s public documentation as the reference model for invoices, subscriptions, charges, balance transactions, payouts, refunds, and disputes, so the project can demonstrate realistic billing reconciliation logic without pretending to use private company records.

## ➤ The Dataset :<br>

The dataset is synthetic and covers the 2024 calendar year.

It was generated to mirror the structure, relationships, and operational messiness of Stripe-style billing and processor data. The schema follows a SaaS billing workflow: customers subscribe to plans, invoices are created, charges attempt collection, balance transactions record processor-side money movement, payouts batch many transactions into bank deposits, and refunds or disputes create later adjustments.

The analysis uses eight core tables covering customers, subscriptions, invoices, charges, balance transactions, payouts, disputes, and refunds.

| Table | Rows | Grain |
|---|---:|---|
| customers | 486 | one row per customer |
| subscriptions | 543 | one row per subscription plan-period |
| invoices | 4,882 | one row per subscription per billing month |
| charges | 5,594 | one row per charge attempt, including retries |
| balance_transactions | 4,823 | one row per processor money-movement event |
| payouts | 253 | one row per bank settlement batch |
| disputes | 23 | one row per chargeback |
| refunds | 5 | one row per customer-service refund |

The dirty-data cases are deliberate.

- Retried charges create multiple charge rows for the same billing event.
- A duplicate successful charge can inflate revenue if not caught.
- Month-end charges can settle in the next month’s payout.
- Chargebacks can land after the original invoice period has already closed.
- A processor hold can delay payout timing.
- Test-mode charges with no customer must be excluded.
- Processor fee rates can drift and need to be measured, not assumed.

All final analytical figures will be produced directly by the project’s own queries against the included synthetic dataset.

## ➤ Skills Demonstrated:

**Light Data Engineering**

- Warehouse Setup
- Database Setup
- Schema Setup
- Stage Setup
- CSV File Format Setup
- COPY INTO Data Loading
- RAW / STAGING / ANALYTICS Structure
- RAW-to-STAGING View Setup

**Business Analytics**

- Billing Reconciliation
- Payment Processor Settlement Logic
- Chargeback Restatement Analysis
- Failed-Payment Analysis
- MRR Movement
- Net Revenue Retention
- Cohort Analysis

<br><br>

## ➤ Core Business Questions :<br>

**1. BILLING RECONCILIATION**
   
  1. Does total settled by the processor in June match what our invoices show as collected?
  2. For every dollar of gap, what is the specific reason?
  3. Which closed periods were restated by chargebacks that landed in June?

**2. REVENUE ANALYTICS**
   
  1. How much June revenue was permanently lost after all retries exhausted?
  2. What is MRR for June, and how did it move versus May?
  3. What is NRR by signup cohort?

<br><br>



<br>

---

<br>
"""

path = Path("/mnt/data/ledgerly_github_readme_following_sample.txt")
path.write_text(content, encoding="utf-8")
print(str(path))

path = Path("/mnt/data/ledgerly_github_readme_draft.txt")
path.write_text(content, encoding="utf-8")
print(str(path))
