CREATE DATABASE machines_db;

USE machines_db;

ALTER TABLE dealers MODIFY dealer_id VARCHAR(10);
ALTER TABLE machines MODIFY machine_id VARCHAR(10);
ALTER TABLE customers MODIFY customer_id VARCHAR(10);
ALTER TABLE sales MODIFY sale_id VARCHAR(10);
ALTER TABLE amc MODIFY amc_id VARCHAR(10);

-- Fixed column Data Types
ALTER TABLE sales
MODIFY machine_id  VARCHAR(10),
MODIFY dealer_id   VARCHAR(10),
MODIFY customer_id VARCHAR(10),
MODIFY financier_name VARCHAR(50),
MODIFY payment_mode VARCHAR(10),
MODIFY amc_signed  VARCHAR(5);

ALTER TABLE amc
MODIFY sale_id VARCHAR(10),
MODIFY customer_id VARCHAR(10),
MODIFY dealer_id   VARCHAR(10),
MODIFY machine_id  VARCHAR(10),
MODIFY contract_type VARCHAR(20),
MODIFY status VARCHAR(20);

ALTER TABLE customers
MODIFY industry_type VARCHAR(50),
MODIFY city  VARCHAR(50),
MODIFY state VARCHAR(50),
MODIFY fleet_size_category VARCHAR(20),
MODIFY customer_type VARCHAR(20),
MODIFY customer_id VARCHAR(100);
    
ALTER TABLE dealers
MODIFY dealer_name  VARCHAR(100),
MODIFY city  VARCHAR(50),
MODIFY state VARCHAR(50),
MODIFY region VARCHAR(20),
MODIFY dealer_status  VARCHAR(20),
MODIFY dealer_id VARCHAR(100);

ALTER TABLE machines
MODIFY machine_name VARCHAR(100),
MODIFY category VARCHAR(50),
MODIFY machine_id VARCHAR(100);


ALTER TABLE dealers ADD PRIMARY KEY (dealer_id);
ALTER TABLE machines ADD PRIMARY KEY (machine_id);
ALTER TABLE customers ADD PRIMARY KEY (customer_id);
ALTER TABLE sales ADD PRIMARY KEY (sale_id);
ALTER TABLE amc ADD PRIMARY KEY (amc_id);

ALTER TABLE sales ADD CONSTRAINT fk_sale_machine FOREIGN KEY (machine_id) REFERENCES machines(machine_id),
ADD CONSTRAINT fk_sale_dealer FOREIGN KEY (dealer_id) REFERENCES dealers(dealer_id),
ADD CONSTRAINT fk_sale_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id);


ALTER TABLE amc ADD CONSTRAINT fk_amc_sale FOREIGN KEY (sale_id) REFERENCES sales(sale_id),
ADD CONSTRAINT fk_amc_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
ADD CONSTRAINT fk_amc_dealer FOREIGN KEY (dealer_id) REFERENCES dealers(dealer_id),
ADD CONSTRAINT fk_amc_machine FOREIGN KEY (machine_id) REFERENCES machines(machine_id);


-- Monthly Cumulative Sales Revenue
WITH monthly_data AS(    
SELECT 
	date_format(sale_date,'%Y-%m') AS sale_month, 
	SUM(sale_price_inr) AS monthly_revenue
    FROM sales
    GROUP BY date_format(sale_date,'%Y-%m')
    ORDER BY sale_month
)
SELECT 
	sale_month,
	ROUND(
	SUM(monthly_revenue)OVER(ORDER BY sale_month)/10000000,
	2) AS cummulative_revenue_in_cr
	FROM monthly_data
	ORDER BY sale_month;
		/*AHM Crossed INR 1400 crores in cumulative machine sales revenue over 12 months with 
		  Q4 FY 2023 showing growth accelaration.*/

-- Top 10 Dealers by Revenue Ranked Within State
WITH dealer_revenue AS(
SELECT 
	d.dealer_name, 
    d.state, 
    ROUND(SUM(s.sale_price_inr)/1e7,2) AS revenue_in_cr
FROM sales s
INNER JOIN dealers d ON s.dealer_id = d.dealer_id
GROUP BY d.dealer_id , d.dealer_name, d.state
)
SELECT
	dealer_name,
    state,
    revenue_in_cr,
    DENSE_RANK()OVER(PARTITION BY state ORDER BY revenue_in_cr DESC) AS state_rank
    FROM dealer_revenue
    ORDER BY state, state_rank;
	/* Maharashtra dominates with 42 active dealers , while Verma Heavy Machines leads Madhya Pradesh and 
    Mehta Heavy Machine Equipment Co tops Rajasthan suggesting strong regional competition outside Maharashtra. */


-- Machine Category Revenue Contribution & Percentage Share
WITH category_revenue AS (
SELECT
	m.category,
	ROUND(SUM(s.sale_price_inr)/1e7,2)   AS revenue_cr
    FROM sales s
    JOIN machines m ON s.machine_id = m.machine_id
    GROUP BY m.category
)
SELECT
    category,
    revenue_cr,
    ROUND(revenue_cr * 100 / SUM(revenue_cr) OVER(), 2) AS pct_share
	FROM category_revenue
	ORDER BY revenue_cr DESC;
    /* Excavators alone contribute 35% of total sales revenue (₹495 Cr), while Compactors and Motor Graders together 
    account for only 15% signaling a heavy revenue concentration in greater ticket categories. */
    

-- Finance Penetration by State
WITH state_payment as (
SELECT 
	c.state,
    COUNT(s.sale_id) AS total_sale,
    SUM(CASE WHEN s.financier_name IS NOT NULL AND s.financier_name != '' THEN 1 ELSE 0 END) AS financed_sales
    FROM sales s
    INNER JOIN customers c ON s.customer_id = c.customer_id
    GROUP BY c.state
    )
SELECT 
	state,
    total_sale,
    financed_sales,
    total_sale - financed_sales AS cash_sales,
    ROUND(financed_sales*100/total_sale,2) AS financed_penetration_pct
    FROM state_payment
    ORDER BY financed_penetration_pct DESC;
    /* Finance penetration is consistently high across all states (58% to 65%), aligning with our EDA finding that 62.3% of all machine 
    sales are financed confirming that credit driven purchase is a consistent behaviour of the overall market and not specific to a state. */
    
-- Top 10 Dealers by AMC Revenue at Risk (Churned AMC Value):  
    WITH churned_amc AS(
		SELECT 
		a.dealer_id,
		SUM(a.amc_value_inr) AS revenue_at_risk
		FROM amc a 
		WHERE a.churn = 'Y'
		GROUP BY a.dealer_id
    )
	SELECT 
    d.dealer_name,
    d.state,
    ROUND(c.revenue_at_risk/1e7,4) AS revenue_at_risk_cr
    FROM churned_amc c
    INNER JOIN dealers d ON c.dealer_id  = d.dealer_id
    ORDER BY revenue_at_risk_cr DESC
    LIMIT 10;
    /* Mehta Heavy Equipment Co leads highest churned AMC revenue at risk, It can be seen that Rajasthan alone
    contributes 4 of the top most at risk dealers which is connecting back to the EDA finding that small fleet size customers
    are likely concerntrated in these dealer networks.*/
    
-- AMC Attachment Rate by Industry
WITH industry_sale AS(
	SELECT 
    c.industry_type, 
    COUNT(s.sale_id) AS total_sold, SUM(CASE WHEN s.amc_signed = 'Y' THEN 1 ELSE 0 END) AS no_of_amc_signed
	FROM sales s 
    INNER JOIN customers c ON s.customer_id = c.customer_id
    GROUP BY c.industry_type
)    
    SELECT 
    industry_type,
    total_sold,
    no_of_amc_signed,
    ROUND(no_of_amc_signed *100 / total_sold,2) AS attachment_rate_pct
    FROM industry_sale
    ORDER BY attachment_rate_pct DESC;
    /* AMC attachment rates are consistent across all Industry nature suggesting that AMC adoption is not driven by
	   Industry Type but rather by fleet size and dealer effort, reinforcing the EDA findings where the overall attachment rate was 62.9%. */
    
    
-- State Wise AMC Renewal Rate vs Total Sales Revenue:
WITH state_amc AS (
	SELECT 
	c.state,
    COUNT(a.amc_id) AS total_renewals,
    SUM(CASE WHEN a.churn = 'N' THEN 1 ELSE 0 END) AS successful_renewals,
    ROUND(SUM(a.amc_value_inr)/1e7,2) AS amc_revenue_cr
    FROM amc a 
    INNER JOIN customers c ON a.customer_id = c.customer_id
    WHERE a.contract_type = 'Renewal'
    GROUP BY c.state
),
state_sale AS (
	SELECT 
    c.state,
    ROUND(SUM(s.sale_price_inr)/1e7,2) AS sales_revenue_cr
    FROM sales s
    INNER JOIN customers c ON s.customer_id = c.customer_id
    GROUP BY c.state
)
	SELECT
	s1.state,
    s1.total_renewals,
    s1.successful_renewals,
    ROUND(s1.successful_renewals*100/s1.total_renewals,2) AS renewal_rate_pct,
    s2.sales_revenue_cr
    FROM state_amc s1 INNER JOIN state_sale s2 ON s1.state = s2.state
    ORDER BY renewal_rate_pct DESC;
    /* Jharkhand leads with highest renewal rate - 85% despite being second smallest revenue generator market by sales revenue at INR 53 cr,
    while Goa has lowest sales revenue and lowest renewal rate which confirms the EDA finding that state geography is not
    a driver of AMC performance and small revenue generating markets can outperform larger ones in retention*/

-- Customer Lifetime Value by Customer Type New v/s Exisiting

WITH customer_sales AS(
	SELECT 
	s.customer_id,
    COUNT(s.sale_id) AS machines_purchased,
    ROUND(SUM(s.sale_price_inr)/1e7,2) AS total_sales_revenue_cr
    FROM sales s
    GROUP BY s.customer_id
),
customer_amc AS(
	SELECT
    a.customer_id,
    ROUND(SUM(a.amc_value_inr)/1e7,2) AS total_amc_revenue_cr
    FROM amc a
    GROUP BY a.customer_id
),
customer_clv AS (
	SELECT
    c.customer_id,
    c.customer_type,
    cs.machines_purchased,
    cs.total_sales_revenue_cr,
    COALESCE(ca.total_amc_revenue_cr,0) AS total_amc_revenue_cr,
    ROUND(cs.total_sales_revenue_cr + COALESCE(ca.total_amc_revenue_cr,0),4) AS clv_cr
    FROM customers c
    INNER JOIN customer_sales cs ON c.customer_id = cs.customer_id
    LEFT JOIN customer_amc ca ON c.customer_id = ca.customer_id
    )
SELECT   
	customer_type,
    COUNT(customer_id) AS total_customers,
    ROUND(AVG(machines_purchased),2) AS avg_machines_purchased,
    ROUND(AVG(total_sales_revenue_cr),4) AS avg_sales_revenue_cr,
    ROUND(AVG(total_amc_revenue_cr),2) AS avg_amc_revenue_cr,
    ROUND(AVG(clv_cr),4) AS avg_clv_cr,
	ROUND(AVG(clv_cr),2) AS total_clv_cr
    FROM customer_clv
    GROUP BY customer_type
    ORDER BY avg_clv_cr DESC;

/* New customers have higher CLV(1.88 Cr vs 1.78 Cr) likely larger fleet buyers onboarding recently.
AMC contribution is identical for both types, AMC conversion is a process problem not a loyalty problem.
Existing customers dominate total number of customers.
*/

-- Month-over-Month Churn Trend : Churned AMC Contracts per Month
SELECT
	DATE_FORMAT(a.amc_end_date,'%Y-%m') AS churn_month,
    COUNT(a.amc_id) AS churned_contracts,
    ROUND(SUM(a.amc_value_inr)/1e7,4) AS churned_revenue_cr
    FROM amc a
    WHERE a.churn = 'Y'
	GROUP BY DATE_FORMAT(a.amc_end_date,'%Y-%m')
	ORDER BY churn_month;
/* Churn is consistent month over month between 22-39 contracts each month with no spikes 
which requires active interaction to fix. */


--  Dealers with High Sales but Low AMC Conversion
WITH dealer_metrics AS(
SELECT 
	s.dealer_id,
    COUNT(s.sale_id) AS total_sales,
    SUM(CASE WHEN s.amc_signed = 'Y' THEN 1 ELSE 0 END) AS amc_signed,
    ROUND(SUM(s.sale_price_inr)/1e7,2) AS sales_revenue_cr
    FROM sales s
    GROUP BY s.dealer_id
)
SELECT 
	d.dealer_name,
    d.state,
    dm.total_sales,
    dm.amc_signed,
    ROUND(dm.amc_signed*100/dm.total_sales,2) AS  amc_conversion_pct,
    dm.sales_revenue_cr,
    ROUND((dm.total_sales - dm.amc_signed)*(SELECT AVG(amc_value_inr) FROM amc)/1e7,4) AS missed_amc_revenue_cr
    FROM dealer_metrics dm
    INNER JOIN dealers d ON dm.dealer_id = d.dealer_id
    WHERE dm.total_sales >= 20
    ORDER BY dm.sales_revenue_cr DESC, amc_conversion_pct ASC
    
    LIMIT 15;

/* Rao Heavy Machines and Mahajan Infra Machines have the highest missed AMC revenue INR 0.12 crores 
despite strong sales. Chattisgarh has 4 dealers with top sales revenue with low AMC conversion.*/    


