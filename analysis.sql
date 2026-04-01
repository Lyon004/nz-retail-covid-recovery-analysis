-- =============================================
-- NZ Retail Sector: COVID-19 Recovery Analysis
-- Author: [Your Name]
-- Data Source: Stats NZ Retail Trade Survey
-- =============================================

-- STEP 1: Create table
CREATE TABLE retail_survey (
    series_reference    TEXT,
    period              TEXT,
    data_value          NUMERIC,
    suppressed          TEXT,
    status              TEXT,
    units               TEXT,
    magnitude           INTEGER,
    subject             TEXT,
    series_group        TEXT,
    industry            TEXT,
    measure             TEXT,
    price_type          TEXT,
    adjustment          TEXT,
    series_title_5      TEXT
);

-- STEP 2: Explore the data
SELECT DISTINCT industry
FROM retail_survey
WHERE industry NOT IN (
    'Current',
    'Deflated, at September 2010 quarter prices'
)
ORDER BY industry;

SELECT DISTINCT adjustment, COUNT(*) AS row_count
FROM retail_survey
GROUP BY adjustment
ORDER BY row_count DESC;

-- STEP 3: Core working dataset
SELECT period, industry, data_value
FROM retail_survey
WHERE
    measure     = 'Sales (operating income)'
    AND price_type  = 'Current'
    AND adjustment  = 'Seasonally adjusted'
    AND industry NOT IN (
        'Current',
        'Deflated, at September 2010 quarter prices'
    )
    AND data_value IS NOT NULL
ORDER BY industry, period
LIMIT 30;

-- STEP 4: Pre-COVID vs COVID trough vs latest
WITH pre_covid AS (
    SELECT
        industry,
        ROUND(AVG(data_value), 1) AS avg_sales_2019
    FROM retail_survey
    WHERE
        measure     = 'Sales (operating income)'
        AND price_type  = 'Current'
        AND adjustment  = 'Seasonally adjusted'
        AND period LIKE '2019%'
        AND industry NOT IN (
            'Current',
            'Deflated, at September 2010 quarter prices',
            'All industries total',
            'Core industries total'
        )
        AND data_value IS NOT NULL
    GROUP BY industry
),
covid_trough AS (
    SELECT
        industry,
        MIN(data_value) AS worst_quarter_2020,
        MIN(period)     AS trough_quarter
    FROM retail_survey
    WHERE
        measure     = 'Sales (operating income)'
        AND price_type  = 'Current'
        AND adjustment  = 'Seasonally adjusted'
        AND period LIKE '2020%'
        AND industry NOT IN (
            'Current',
            'Deflated, at September 2010 quarter prices',
            'All industries total',
            'Core industries total'
        )
        AND data_value IS NOT NULL
    GROUP BY industry
),
latest AS (
    SELECT
        industry,
        data_value AS sales_dec_2024
    FROM retail_survey
    WHERE
        measure     = 'Sales (operating income)'
        AND price_type  = 'Current'
        AND adjustment  = 'Seasonally adjusted'
        AND period      = '2024.12'
        AND industry NOT IN (
            'Current',
            'Deflated, at September 2010 quarter prices',
            'All industries total',
            'Core industries total'
        )
        AND data_value IS NOT NULL
)
SELECT
    p.industry,
    p.avg_sales_2019,
    c.worst_quarter_2020,
    l.sales_dec_2024,
    ROUND((c.worst_quarter_2020 - p.avg_sales_2019)
        / p.avg_sales_2019 * 100, 1) AS covid_drop_pct,
    ROUND((l.sales_dec_2024 - p.avg_sales_2019)
        / p.avg_sales_2019 * 100, 1) AS recovery_pct
FROM pre_covid p
JOIN covid_trough c ON p.industry = c.industry
JOIN latest      l ON p.industry = l.industry
ORDER BY recovery_pct DESC;

-- STEP 5: Final recovery ranking with classification
CREATE VIEW vw_retail_recovery AS
WITH pre_covid AS (
    SELECT
        industry,
        ROUND(AVG(data_value), 1) AS avg_sales_2019
    FROM retail_survey
    WHERE
        measure     = 'Sales (operating income)'
        AND price_type  = 'Current'
        AND adjustment  = 'Seasonally adjusted'
        AND period LIKE '2019%'
        AND industry NOT IN (
            'Current',
            'Deflated, at September 2010 quarter prices',
            'All industries total',
            'Core industries total'
        )
        AND data_value IS NOT NULL
    GROUP BY industry
),
covid_trough AS (
    SELECT
        industry,
        MIN(data_value) AS worst_quarter_2020,
        MIN(period)     AS trough_quarter
    FROM retail_survey
    WHERE
        measure     = 'Sales (operating income)'
        AND price_type  = 'Current'
        AND adjustment  = 'Seasonally adjusted'
        AND period LIKE '2020%'
        AND industry NOT IN (
            'Current',
            'Deflated, at September 2010 quarter prices',
            'All industries total',
            'Core industries total'
        )
        AND data_value IS NOT NULL
    GROUP BY industry
),
latest AS (
    SELECT
        industry,
        data_value AS sales_dec_2024
    FROM retail_survey
    WHERE
        measure     = 'Sales (operating income)'
        AND price_type  = 'Current'
        AND adjustment  = 'Seasonally adjusted'
        AND period      = '2024.12'
        AND industry NOT IN (
            'Current',
            'Deflated, at September 2010 quarter prices',
            'All industries total',
            'Core industries total'
        )
        AND data_value IS NOT NULL
),
summary AS (
    SELECT
        p.industry,
        p.avg_sales_2019,
        c.worst_quarter_2020,
        c.trough_quarter,
        l.sales_dec_2024,
        ROUND((c.worst_quarter_2020 - p.avg_sales_2019)
            / p.avg_sales_2019 * 100, 1) AS covid_drop_pct,
        ROUND((l.sales_dec_2024 - p.avg_sales_2019)
            / p.avg_sales_2019 * 100, 1) AS recovery_pct
    FROM pre_covid p
    JOIN covid_trough c ON p.industry = c.industry
    JOIN latest      l ON p.industry = l.industry
)
SELECT
    RANK() OVER (ORDER BY recovery_pct DESC) AS recovery_rank,
    industry,
    avg_sales_2019     AS baseline_2019_m,
    worst_quarter_2020 AS trough_2020_m,
    sales_dec_2024     AS current_2024_m,
    covid_drop_pct     AS drop_pct,
    recovery_pct,
    CASE
        WHEN recovery_pct >= 20  THEN 'Booming'
        WHEN recovery_pct >= 5   THEN 'Strong recovery'
        WHEN recovery_pct >= 0   THEN 'Fully recovered'
        WHEN recovery_pct >= -10 THEN 'Soft recovery'
        ELSE                          'Still struggling'
    END AS recovery_status
FROM summary
ORDER BY recovery_rank;

-- STEP 6: Time series view for Power BI
CREATE VIEW vw_retail_timeseries AS
SELECT
    period,
    industry,
    data_value AS sales_m
FROM retail_survey
WHERE
    measure     = 'Sales (operating income)'
    AND price_type  = 'Current'
    AND adjustment  = 'Seasonally adjusted'
    AND period  >= '2017.03'
    AND industry NOT IN (
        'Current',
        'Deflated, at September 2010 quarter prices',
        'Core industries total',
        'All industries total'
    )
    AND data_value IS NOT NULL
ORDER BY industry, period;