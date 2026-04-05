-- CREATING DIMENSION CUSTOMERS TABLE
CREATE TABLE dim_customers(
customer_id VARCHAR(50) PRIMARY KEY,
gender VARCHAR(50),
senior_flag TINYINT,
partner_flag TINYINT,
dependent_flag TINYINT,
signup_date DATE,
customer_segment VARCHAR(20));

--CREATING DIMENSION PLAN TABLE
CREATE TABLE dim_plan(
plan_id INT PRIMARY KEY AUTO_INCREMENT,
plan_name VARCHAR(20),
billing_cycle VARCHAR(20),
base_price DECIMAL(10,2));

-- INSERTING VALUES IN DIM_CUSTOMERS TABLE
INSERT INTO dim_customers
SELECT 
customerID,
gender,
SeniorCitizen,
CASE WHEN Partner='Yes' THEN 1 ELSE 0 END,
CASE WHEN Dependents= 'Yes' THEN 1 ELSE 0 END,
DATE_SUB(CURDATE(),INTERVAL tenure MONTH),
CASE WHEN tenure>24 THEN 'Enterprise'
     WHEN tenure BETWEEN 12 AND 24 THEN 'Mid-Market'
     ELSE 'SMB' END
FROM raw_telco_data;
select * from raw_telco_data;

-- INSERTING VALUES IN DIMENSION PLAN TABLE
INSERT INTO dim_plan(plan_name,billing_cycle,base_price)
SELECT 
CASE WHEN MonthlyCharges <40 THEN 'Basic'
WHEN MonthlyCharges BETWEEN 40 AND 80 THEN 'Pro'
ELSE 'Enterprise' END,
Contract,
ROUND(MonthlyCharges,2)
FROM raw_telco_data;
SELECT * FROM dim_plan;
select * from fact_subscriptions;

-- CREATING TENURE BUCKET TABLE
SELECT 
    CASE 
        WHEN tenure_months <= 6 THEN '0-6 Months'
        WHEN tenure_months <= 12 THEN '6-12 Months'
        WHEN tenure_months <= 24 THEN '12-24 Months'
        ELSE '24+ Months'
    END AS tenure_bucket,

    COUNT(*) AS total_customers,
    SUM(churn_flag) AS churned_customers,

    ROUND(
        SUM(churn_flag)  / COUNT(*),
        2
    ) AS churn_rate_percentage,

    ROUND(SUM(CASE WHEN churn_flag = 1 THEN mrr_value ELSE 0 END),2) AS lost_mrr,

    ROUND(SUM(CASE WHEN churn_flag = 1 THEN mrr_value ELSE 0 END) * 12 ,2)
        AS annual_revenue_lost

FROM (
    SELECT 
        customer_id,
        mrr_value,
        churn_flag,

        TIMESTAMPDIFF(
            MONTH,
            STR_TO_DATE(start_date, '%d/%m/%Y'),
            COALESCE(
                STR_TO_DATE(end_date, '%d/%m/%Y'),
                CURDATE()
            )
        ) AS tenure_months

    FROM fact_subscriptions
) t

GROUP BY tenure_bucket
ORDER BY churn_rate_percentage desc;

-- QUICK 80/20 SUMMARY
-- TO SUMMARIZE TOP 20%
WITH revenue_ranked AS (
    SELECT 
        customer_id,
        SUM(mrr_value) * 12 AS annual_revenue
    FROM fact_subscriptions
    GROUP BY customer_id
),
ranked AS (
    SELECT 
        *,
        NTILE(5) OVER (ORDER BY annual_revenue DESC) AS revenue_quintile
    FROM revenue_ranked
)

SELECT 
    revenue_quintile,
    COUNT(*) AS customers,
    ROUND(SUM(annual_revenue),2) AS total_revenue,
    ROUND(
        SUM(annual_revenue) * 100 /
        (SELECT SUM(annual_revenue) FROM revenue_ranked),
        2
    ) AS revenue_percentage
FROM ranked
GROUP BY revenue_quintile
ORDER BY revenue_quintile;

-- 🔎 Now Add Risk Layer

-- We combine concentration with churn.

-- If top 20% also have rising churn risk → danger.

WITH revenue_ranked AS (
SELECT 
	customer_id,
    SUM(mrr_value)*12 AS annual_revenue
FROM fact_subscriptions
GROUP BY 1),
ranked AS (
SELECT 
	r.*,
    NTILE(5) OVER(ORDER BY r.annual_revenue DESC) AS revenue_quintile,
    f.churn_flag
    FROM revenue_ranked r
    JOIN fact_subscriptions f ON f.customer_id=r.customer_id
    )
SELECT 
    revenue_quintile,
    COUNT(*) AS customers,
    SUM(churn_flag) AS churned_customers,
    ROUND(SUM(churn_flag)/COUNT(*),2) AS churn_rate
FROM ranked 
GROUP BY revenue_quintile
ORDER BY revenue_quintile;


-- 🔎 Hypothesis 1: Add-On Impact
-- Your dataset has:
-- OnlineSecurity
-- TechSupport
-- Possibly other add-ons
-- Let’s check if high-value churners lack add-on adoption.
-- SQL: Add-On vs Churn in Top Revenue Quintile
WITH revenue_ranked AS (
SELECT 
	customer_id,
    SUM(mrr_value)*12 AS annual_revenue
    FROM fact_subscriptions
    GROUP BY customer_id),
ranked AS (
SELECT 
    *,
    NTILE(5) OVER(ORDER BY annual_revenue DESC) AS revenue_quintile
    FROM revenue_ranked),
top_segment AS (
SELECT 
    rs.customer_id,
    r.InternetService,
    r.TechSupport,
    fs.churn_flag
    FROM ranked rs
    JOIN raw_telco_data r ON r.customerID=rs.customer_id
    JOIN fact_subscriptions fs ON fs.customer_id=rs.customer_id
    WHERE rs.revenue_quintile=1)
SELECT 
InternetService,
TechSupport,
COUNT(*) AS customers,
SUM(churn_flag) AS churned,
ROUND(SUM(churn_flag)*100/COUNT(*),2) AS churn_rate
FROM top_segment
GROUP BY InternetService,TechSupport
ORDER BY customers DESC;

-- FINDING ACTIVE REVENUE AND REVENUE RETENTION PERCENTAGE
SELECT 
    SUM(CASE WHEN churn_flag = 0 THEN mrr_value ELSE 0 END) 
        AS active_mrr,
    SUM(mrr_value) AS total_mrr,
    ROUND(
        SUM(CASE WHEN churn_flag = 0 THEN mrr_value ELSE 0 END) 
        / SUM(mrr_value) * 100,
        2
    ) AS revenue_retention_percentage
FROM fact_subscriptions;

-- FINDING OUT HOW MUCH REVENUE IS CONTRIBUTED PER PLAN CATEGORY PER YEAR
SELECT
Year(str_to_date(start_date,'%d/%m/%Y')) as YEAR,
p.plan_name,
ROUND(SUM(f.mrr_value),2) AS revenue_per_plan
FROM fact_subscriptions f
JOIN dim_plan p ON p.plan_id=f.plan_id
GROUP BY 1,p.plan_name
ORDER BY 1;

-- FINDING OUT HOW MUCH REVENUE IS CONTRIBUTED PER CONTRACT PER YEAR
SELECT 
YEAR(STR_TO_DATE(start_date,'%d/%m/%Y')) AS YEAR,
p.billing_cycle AS contract,
ROUND(SUM(f.mrr_value),2) AS revenue_per_contract
FROM fact_subscriptions f
JOIN dim_plan p ON p.plan_id=f.plan_id
GROUP BY 1,2
ORDER BY 1;

-- FINDING OUT HOW MUCH CUSTOMER CHURNED PER CONTRACT CATEGORY PER YEAR
SELECT 
YEAR(STR_TO_DATE(start_date,'%d/%m/%Y')) AS YEAR,
Contract,
COUNT(*) AS total_customers,
SUM(churn_flag) AS churned_customers,
ROUND(SUM(churn_flag)/COUNT(*),2) AS churn_rate
FROM fact_subscriptions
GROUP BY 1,2
ORDER BY 1;

-- FINDING THAT HOW MUCH REVENUE IS CONCENTRATED IN TOP (REVENUE QUINTILE)---> IT MEANS HOW MUCH REVENUE IS CONTRIBUTED BY TOP 20% CUSTOMERS
SELECT 
revenue_quintile,
COUNT(*) AS total_customers,
ROUND(SUM(annual_revenue),2) AS total_annual_revenue,
ROUND(SUM(annual_revenue)/(SELECT SUM(annual_revenue) FROM revenue),2) AS revenue_rate
FROM quintile
GROUP BY 1
ORDER BY 1;

-- FINDING OUT HOW MANY CUSTOMER ( ACTIVE AND TOTAL CUSTOMERS) PRESENT PER CUSTOMER SEGMENT PER YEAR
SELECT 
revenue_quintile,
COUNT(*) AS total_customers,
ROUND(SUM(annual_revenue),2) AS total_annual_revenue,
ROUND(SUM(annual_revenue)/(SELECT SUM(annual_revenue) FROM revenue),2) AS revenue_rate
FROM quintile
GROUP BY 1
ORDER BY 1;

-- FINDING OUT HOW MANY CUSTOMERS CHURNED PER YEAR IF THEY GET TECH SUPPORT OR NOT
SELECT 
	YEAR(STR_TO_DATE(start_date,'%d/%m/%Y')) AS YEAR,
    r.TechSupport,
    COUNT(DISTINCT f.customer_id) AS total_customers,
    SUM(f.churn_flag) AS churned_customers,
    ROUND(SUM(f.churn_flag) / COUNT(f.customer_id),
            2) AS churn_rate
FROM
    raw_telco_data r
        JOIN
    fact_subscriptions f ON f.customer_id = r.customerID
    WHERE TechSupport !='No internet service'
GROUP BY 1,2
ORDER BY 1;

-- FINDING OUT HOW MANY CUSTOMERS CHURNED PER YEAR PER INTERNET SERVICE PROVIDED BY THE TELECOM COMPANY
select 
year(str_to_date(start_date,'%d/%m/%Y')) as year,
r.InternetService,
count(f.customer_id) as total_customers,
sum(f.churn_flag) as churned_customers,
round(sum(f.churn_flag)/count(f.customer_id),2) as churn_rate
from raw_telco_data r
join fact_subscriptions f on f.customer_id=r.customerID
where InternetService in('DSL','Fiber optic')
group by 1,2
order by 1;

-- FINDING OUT HOW MUCH REVENUE CONTRIBUTED BY CONTRACT TYPE PER YEAR
SELECT 
YEAR(STR_TO_DATE(start_date,'%d/%m/%Y')) AS YEAR,
p.billing_cycle AS contract,
ROUND(SUM(f.mrr_value),2) AS revenue_per_contract
FROM fact_subscriptions f
JOIN dim_plan p ON p.plan_id=f.plan_id
GROUP BY 1,2
ORDER BY 1;

-- 

