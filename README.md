WIP : June 29th 2026

# Ledgerly — SaaS Billing Reconciliation & Revenue Analytics
Billing Reconciliation, MRR Movement, Net Revenue Retention, Cohort Analysis, and Processor Settlement Analytics

<br>

End-to-end SaaS billing analytics project analyzing synthetic Stripe-style billing data from a B2B subscription business. The analysis covers processor settlement reconciliation, chargeback restatements, MRR movement, and net revenue retention by paid signup cohort — built entirely in Snowflake using a RAW → STAGING → ANALYTICS architecture.

<br><br>

➤ Executive Summary :<br>
**What the project was trying to find out**

- Does what Stripe settled in June 2024 match what the billing system recorded — and where are the gaps?
- Which prior-period invoices had their net revenue restated by chargebacks that landed in June 2024?
- Is recurring revenue growing, and what's driving the movement each month?
- Which paid signup cohorts retained and expanded revenue through 2024, and which didn't?

**What the data showed**

- [To be completed after running BQ01–BQ06 outputs]

**What the key numbers are**

- 25,000 customers · 26,250 subscriptions · 321,114 invoices · 359,466 charges
- 4,158 refunds · 288 disputes · 324,306 balance transactions · 156 payouts
- Dataset spans 2022–2024, with analytics scoped to 2024 reporting windows

**What actions should follow**

- [To be completed after running BQ01–BQ06 outputs]

<br><br>

➤ Project Scope:<br>

This project evaluates how a simulated B2B SaaS billing system generates, collects, and reconciles recurring revenue — examining whether the processor settlement matches internal billing records, whether chargebacks are distorting prior-period revenue, whether recurring revenue growth is healthy, and whether existing customers are expanding or contracting over time.

The reconciliation layer compares Stripe-side balance transactions against invoice-side billing records to surface gaps and classify them by cause. The revenue analytics layer tracks MRR movement month over month and decomposes it into new, expansion, contraction, churn, and reactivation drivers. The cohort layer measures net revenue retention by paid signup cohort and identifies which movement types — expansion, contraction, or churn — drove each cohort's 2024 outcome.

The project is built entirely in Snowflake using a RAW → STAGING → ANALYTICS three-layer architecture. Raw CSV files load into the RAW schema without transformation. STAGING cleans and types the data. ANALYTICS holds all business logic — reconciliation tables, MRR tables, cohort outputs, and lost-revenue summaries. Every analytics object documents its grain.

➤ A Note on Synthetic Data:<br>

Real Stripe exports contain PII and are proprietary. This dataset was generated from scratch using published Stripe API schemas, real SaaS churn and dispute benchmarks, and intentionally seeded edge cases that appear in production billing systems — including timing gaps, partial refunds, chargeback restatements of prior periods, and retry-exhausted uncollectible invoices. The goal was a dataset realistic enough that every business question produces a defensible answer, not a convenient one.

➤ The Dataset :<br>
The raw dataset spans 2022 through 2024, and all reporting and conclusions in this project are intentionally scoped to 2024 reporting windows, with 2022–2023 history used as the baseline for cohort anchoring and MRR movement calculations.

The analysis uses nine core tables modeled on the Stripe API, covering customers, subscriptions, subscription lifecycle events, invoices, charges, refunds, disputes, processor balance transactions, and bank payouts.

➤ Skills Demonstrated:

(SQL • Snowflake • Python • Billing Reconciliation • MRR Movement Analytics • Net Revenue Retention • Cohort Analysis • Window Functions • Data Quality Validation)

<br><br>

➤ Core Business Questions :<br>

**BILLING RECONCILIATION**<br>
1- Which June 2024 Stripe-processed invoices have a gap between what the billing system recorded and what Stripe settled — and what caused each gap?<br>
2- Which prior-period invoices had their net revenue restated by chargebacks that landed in June 2024, and how much was lost by dispute reason?

<br>

**REVENUE ANALYTICS**<br>
3- What was month-by-month subscription MRR from December 2023 through December 2024, and how did the rate of change shift over the year?<br>
4- What drove each month's MRR movement — how much came from new subscriptions, expansion, contraction, churn, and reactivation?

<br>

**COHORT & RETENTION ANALYTICS**<br>
5- Which paid signup cohorts had the strongest and weakest 2024 year-end NRR, and how did individual customers rank within each cohort?<br>
6- For each paid signup cohort, how much of the 2024 NRR outcome was driven by expansion, contraction, and churn — and which cohorts were net positive vs. net negative?

<br>

**COLLECTIONS & LOST REVENUE**<br>
7- How much recurring revenue was permanently lost each month in 2024 after all payment retries were exhausted?
