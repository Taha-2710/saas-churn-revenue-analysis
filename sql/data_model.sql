-- Create dimension customer tabel
CREATE TABLE dim_customers(
customer_id VARCHAR(50) PRIMARY KEY,
gender VARCHAR(50),
senior_flag TINYINT,
partner_flag TINYINT,
dependent_flag TINYINT,
signup_date DATE,
customer_segment VARCHAR(20));

-- Create dimension plan table
CREATE TABLE dim_plan(
plan_id INT PRIMARY KEY AUTO_INCREMENT,
plan_name VARCHAR(20),
billing_cycle VARCHAR(20),
base_price DECIMAL(10,2));

