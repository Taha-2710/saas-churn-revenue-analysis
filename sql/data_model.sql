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

