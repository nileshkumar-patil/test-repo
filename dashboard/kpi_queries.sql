-- =========================================================================
-- TSNPDCL Smart Grid Analytics Platform - Lakeview Dashboard Queries
-- =========================================================================
-- Instructions: Copy and paste these queries into Databricks SQL to create 
-- datasets for your Lakeview dashboard visualizations.
-- =========================================================================

-- KPI 1: Seasonal Consumption Variance
-- Visualization: Bar Chart (X: Season, Y: Total Units, Color/Group: extraction_year)
SELECT 
    Season,
    extraction_year,
    SUM(Units) AS Total_Units_Consumed
FROM tsnpdcl_prod.silver.consumption
GROUP BY Season, extraction_year
ORDER BY extraction_year, Total_Units_Consumed DESC;


-- KPI 2: District Efficiency Ranking
-- Visualization: Horizontal Bar Chart (X: avg_efficiency, Y: Circle)
-- Data is already pre-aggregated in the Gold layer
SELECT 
    Circle AS District,
    Units_Billed_per_Service AS Avg_Units_Per_Billed_Service,
    Service_Gap AS Unbilled_Services
FROM tsnpdcl_prod.gold.district_performance
ORDER BY Avg_Units_Per_Billed_Service DESC
LIMIT 15;


-- KPI 3: Growth Trend Analysis (Month-over-Month)
-- Visualization: Line Chart (X: Month_Year, Y: Total_Connections) with MoM Growth Tooltip
-- Using LPAD to format month for chronological sorting
SELECT 
    Circle,
    CONCAT(CAST(extraction_year AS STRING), '-', LPAD(CAST(extraction_month AS STRING), 2, '0')) AS Month_Year,
    Total_Connections,
    MoM_Growth_Rate * 100 AS MoM_Growth_Percentage
FROM tsnpdcl_prod.gold.growth_trends
ORDER BY Circle, Month_Year;


-- KPI 4: Revenue Protection (High-Loss Sections)
-- Visualization: Scatter Plot (X: Section, Y: Service_Gap)
-- Identifying Sections where the most services went unbilled
SELECT 
    Section,
    Service_Gap
FROM tsnpdcl_prod.gold.revenue_protection
WHERE Service_Gap > 7000 -- Adjusted threshold based on visual
ORDER BY Service_Gap DESC;


-- KPI 5: Load Hotspots (Maintenance Guide)
-- Visualization: Heatmap or Tree Map (Hierarchy: Circle -> Division -> Section, Value: Total_Load)
SELECT 
    Circle,
    Division,
    Section,
    SUM(Load) AS Total_Load_kW
FROM tsnpdcl_prod.silver.consumption
WHERE extraction_year = (SELECT MAX(extraction_year) FROM tsnpdcl_prod.silver.consumption)
  AND extraction_month = (SELECT MAX(extraction_month) FROM tsnpdcl_prod.silver.consumption 
                          WHERE extraction_year = (SELECT MAX(extraction_year) FROM tsnpdcl_prod.silver.consumption))
GROUP BY Circle, Division, Section
ORDER BY Total_Load_kW DESC
LIMIT 20;


-- KPI 6: Post-Pandemic Recovery
-- Visualization: Gauge Chart or Bullet Chart (Value: Recovery_Index_Pct)
-- Shows if 2022-2023 consumption exceeded the 2019 baseline (100% means full recovery)
SELECT 
    Circle,
    Baseline_2019 AS Avg_Units_2019,
    Post_Pandemic_22_23 AS Avg_Units_22_23,
    Recovery_Index_Pct
FROM tsnpdcl_prod.gold.recovery_summary
ORDER BY Recovery_Index_Pct DESC;
