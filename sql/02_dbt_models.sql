-- ============================================================
-- PEOPLEPULSE AI — dbt MODEL STUBS
-- Bronze → Silver → Gold transformation pipeline
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- BRONZE LAYER
-- models/bronze/bronze_workday_employees.sql
-- ─────────────────────────────────────────────────────────────
{{ config(materialized='incremental', unique_key='worker_id', on_schema_change='sync_all_columns') }}

SELECT
    worker_id::VARCHAR(20)                              AS employee_id,
    NULLIF(TRIM(first_name), '')::VARCHAR(100)          AS first_name,
    NULLIF(TRIM(last_name), '')::VARCHAR(100)           AS last_name,
    NULLIF(TRIM(email_primary), '')::VARCHAR(200)       AS email_work,
    TRY_TO_DATE(hire_date, 'YYYY-MM-DD')                AS hire_date,
    TRY_TO_DATE(termination_date, 'YYYY-MM-DD')         AS termination_date,
    UPPER(TRIM(worker_status))::VARCHAR(20)             AS employment_status_raw,
    UPPER(TRIM(employee_type))::VARCHAR(20)             AS employee_type_raw,
    fte_percentage::DECIMAL(5,2)                        AS fte_value,
    TRY_TO_DATE(birth_date, 'YYYY-MM-DD')               AS birth_date,
    NULLIF(TRIM(gender), '')                            AS gender_raw,
    NULLIF(TRIM(ethnicity), '')                         AS ethnicity_raw,
    NULLIF(TRIM(nationality_iso), '')                   AS nationality_code,
    'WORKDAY'                                           AS source_system_code,
    _airbyte_extracted_at                               AS ingestion_timestamp,
    CURRENT_TIMESTAMP()                                 AS bronze_loaded_at
FROM {{ source('workday_raw', 'workers') }}
{% if is_incremental() %}
WHERE _airbyte_extracted_at > (SELECT MAX(ingestion_timestamp) FROM {{ this }})
{% endif %}


-- ─────────────────────────────────────────────────────────────
-- SILVER LAYER
-- models/silver/silver_employees.sql
-- ─────────────────────────────────────────────────────────────
{{ config(materialized='incremental', unique_key='employee_id', on_schema_change='sync_all_columns') }}

WITH source AS (
    SELECT * FROM {{ ref('bronze_workday_employees') }}
),
standardized AS (
    SELECT
        employee_id,
        first_name,
        last_name,
        CONCAT(first_name, ' ', last_name)              AS full_name,
        email_work,
        hire_date,
        termination_date,
        birth_date,
        -- Standardize status codes
        CASE UPPER(TRIM(employment_status_raw))
            WHEN 'ACTIVE'      THEN 'Active'
            WHEN 'TERMINATED'  THEN 'Terminated'
            WHEN 'LEAVE'       THEN 'LOA'
            WHEN 'LOA'         THEN 'LOA'
            WHEN 'INACTIVE'    THEN 'Inactive'
            ELSE 'Unknown'
        END                                             AS employment_status_code,
        -- Standardize employee type
        CASE UPPER(TRIM(employee_type_raw))
            WHEN 'FULL TIME' THEN 'Full-Time'
            WHEN 'FULL-TIME' THEN 'Full-Time'
            WHEN 'FT'        THEN 'Full-Time'
            WHEN 'PART TIME' THEN 'Part-Time'
            WHEN 'PART-TIME' THEN 'Part-Time'
            WHEN 'PT'        THEN 'Part-Time'
            WHEN 'CONTRACTOR' THEN 'Contract'
            WHEN 'CONTRACT'   THEN 'Contract'
            WHEN 'INTERN'     THEN 'Intern'
            ELSE 'Full-Time'
        END                                             AS employee_type_code,
        -- Standardize gender codes
        CASE UPPER(TRIM(gender_raw))
            WHEN 'M'      THEN 'Male'
            WHEN 'MALE'   THEN 'Male'
            WHEN 'F'      THEN 'Female'
            WHEN 'FEMALE' THEN 'Female'
            WHEN 'NB'     THEN 'Non-binary'
            WHEN 'NON-BINARY' THEN 'Non-binary'
            WHEN 'X'      THEN 'Non-binary'
            ELSE 'Prefer-not-to-say'
        END                                             AS gender_code,
        -- Age band derived from birth_date
        CASE
            WHEN DATEDIFF('year', birth_date, CURRENT_DATE()) < 25  THEN '<25'
            WHEN DATEDIFF('year', birth_date, CURRENT_DATE()) < 35  THEN '25-34'
            WHEN DATEDIFF('year', birth_date, CURRENT_DATE()) < 45  THEN '35-44'
            WHEN DATEDIFF('year', birth_date, CURRENT_DATE()) < 55  THEN '45-54'
            WHEN DATEDIFF('year', birth_date, CURRENT_DATE()) < 65  THEN '55-64'
            ELSE '65+'
        END                                             AS age_band_code,
        NULLIF(TRIM(ethnicity_raw), '')                 AS ethnicity_code,
        nationality_code,
        COALESCE(fte_value, 1.0)                        AS fte_value,
        source_system_code,
        ingestion_timestamp
    FROM source
    WHERE employee_id IS NOT NULL
      AND first_name IS NOT NULL
)
SELECT
    employee_id,
    first_name,
    last_name,
    full_name,
    email_work,
    hire_date,
    termination_date,
    birth_date,
    age_band_code,
    employment_status_code,
    employee_type_code,
    gender_code,
    ethnicity_code,
    nationality_code,
    fte_value,
    source_system_code,
    ingestion_timestamp,
    CURRENT_TIMESTAMP() AS silver_loaded_at
FROM standardized
-- Deduplicate: keep the most recent record per employee
QUALIFY ROW_NUMBER() OVER (PARTITION BY employee_id ORDER BY ingestion_timestamp DESC) = 1


-- ─────────────────────────────────────────────────────────────
-- GOLD LAYER — SCD2 MERGE
-- models/gold/dim_employee.sql
-- ─────────────────────────────────────────────────────────────
-- Note: In dbt, SCD2 is handled via the dbt_utils snapshots feature
-- This is the snapshot config that generates the SCD2 table

-- snapshots/snap_dim_employee.sql
{% snapshot snap_dim_employee %}
    {{
        config(
            target_schema = 'GOLD',
            target_table  = 'DIM_EMPLOYEE',
            unique_key    = 'employee_id',
            strategy      = 'check',
            check_cols    = [
                'employment_status_code',
                'employee_type_code',
                'full_name',
                'email_work',
                'gender_code',
                'age_band_code',
                'fte_value'
            ],
            invalidate_hard_deletes = True
        )
    }}
    SELECT
        {{ generate_surrogate_key(['employee_id']) }}    AS employee_global_id,
        employee_id,
        first_name,
        last_name,
        full_name,
        email_work,
        hire_date,
        termination_date,
        birth_date,
        age_band_code,
        gender_code,
        ethnicity_code,
        nationality_code,
        employment_status_code,
        employee_type_code,
        fte_value,
        source_system_code
    FROM {{ ref('silver_employees') }}
{% endsnapshot %}


-- ─────────────────────────────────────────────────────────────
-- GOLD LAYER — FACT_EMPLOYEE_SNAPSHOT
-- models/gold/fact_employee_snapshot.sql
-- ─────────────────────────────────────────────────────────────
{{ config(
    materialized = 'incremental',
    unique_key   = ['employee_id', 'date_key'],
    cluster_by   = ['date_key', 'department_key'],
    on_schema_change = 'append_new_columns'
) }}

WITH
employees AS (
    SELECT * FROM {{ ref('snap_dim_employee') }}
    WHERE is_current_flag = TRUE
),
departments AS (
    SELECT * FROM {{ ref('dim_department') }}
    WHERE is_active_flag = TRUE
),
locations AS (
    SELECT * FROM {{ ref('dim_location') }}
    WHERE is_active_flag = TRUE
),
roles AS (
    SELECT * FROM {{ ref('snap_dim_role') }}
    WHERE is_current_flag = TRUE
),
compensation AS (
    SELECT DISTINCT ON (employee_id)
        employee_id,
        compa_ratio,
        base_salary_new_usd AS total_comp_usd
    FROM {{ ref('silver_compensation_events') }}
    WHERE end_date_key IS NULL
    ORDER BY employee_id, effective_date DESC
),
engagement AS (
    SELECT DISTINCT ON (employee_id)
        employee_id,
        score AS engagement_score
    FROM {{ ref('silver_engagement_scores') }}
    ORDER BY employee_id, survey_date DESC
),
flight_risk AS (
    SELECT employee_id, risk_score AS flight_risk_score
    FROM {{ ref('ml_flight_risk_predictions') }}  -- ML write-back table
    WHERE prediction_date = DATEADD('day', -7, CURRENT_DATE())
),
month_ends AS (
    SELECT date_key, full_date
    FROM {{ ref('dim_date') }}
    WHERE is_month_end_flag = TRUE
    {% if is_incremental() %}
      AND full_date > (SELECT MAX(d.full_date) FROM {{ this }} t JOIN {{ ref('dim_date') }} d ON t.date_key = d.date_key)
    {% endif %}
)

SELECT
    e.employee_key,
    e.employee_id,
    me.date_key,
    COALESCE(dept.department_key, -1)   AS department_key,
    COALESCE(loc.location_key, -1)      AS location_key,
    dr.role_key,
    c.compa_ratio,
    c.total_comp_usd,
    -- Tenure calculation
    DATEDIFF('month', e.hire_date, me.full_date)            AS tenure_months,
    CASE
        WHEN DATEDIFF('month', e.hire_date, me.full_date) < 6   THEN '<6m'
        WHEN DATEDIFF('month', e.hire_date, me.full_date) < 12  THEN '6-12m'
        WHEN DATEDIFF('month', e.hire_date, me.full_date) < 24  THEN '1-2y'
        WHEN DATEDIFF('month', e.hire_date, me.full_date) < 60  THEN '2-5y'
        WHEN DATEDIFF('month', e.hire_date, me.full_date) < 120 THEN '5-10y'
        ELSE '10y+'
    END                                                     AS tenure_band_code,
    e.employment_status_code,
    e.employee_type_code,
    COALESCE(e.fte_value, 1.0)                              AS fte_value,
    CASE WHEN e.employment_status_code = 'Active' THEN TRUE ELSE FALSE END AS is_active_flag,
    eng.engagement_score,
    fr.flight_risk_score,
    CURRENT_TIMESTAMP()                                     AS created_at,
    CURRENT_TIMESTAMP()                                     AS updated_at
FROM employees e
CROSS JOIN month_ends me
LEFT JOIN departments dept USING (department_id)   -- assumes silver_employees has current dept_id
LEFT JOIN locations    loc  USING (location_id)
LEFT JOIN roles        dr   USING (role_id)
LEFT JOIN compensation c    USING (employee_id)
LEFT JOIN engagement   eng  USING (employee_id)
LEFT JOIN flight_risk  fr   USING (employee_id)
WHERE e.employment_status_code != 'Terminated'
   OR (e.termination_date >= DATE_TRUNC('month', me.full_date))


-- ─────────────────────────────────────────────────────────────
-- GOLD LAYER — DIM_DATE seed + generator
-- models/gold/dim_date.sql  (uses dbt_date package)
-- ─────────────────────────────────────────────────────────────
{{ config(materialized='table') }}

{{ dbt_date.get_date_dimension(
    start_date  = "2018-01-01",
    end_date    = "2030-12-31"
) }}

-- Extended fiscal calendar columns added via dbt macros
-- (configure fiscal_year_start in dbt_project.yml vars)


-- ─────────────────────────────────────────────────────────────
-- dbt_project.yml
-- ─────────────────────────────────────────────────────────────

# dbt_project.yml
name: peoplepulse_transforms
version: '1.0.0'
profile: peoplepulse_snowflake

vars:
  fiscal_year_start_month: 4    # April fiscal year start
  currency_base: 'USD'
  flight_risk_threshold_high: 70
  flight_risk_threshold_med: 40

models:
  peoplepulse_transforms:
    bronze:
      +materialized: incremental
      +schema: BRONZE
      +on_schema_change: sync_all_columns
    silver:
      +materialized: incremental
      +schema: SILVER
      +on_schema_change: sync_all_columns
    gold:
      +materialized: incremental
      +schema: GOLD
      +post-hook:
        - "CALL refresh_materialized_views()"
    aggregations:
      +materialized: incremental
      +schema: AGGREGATIONS
      +on_schema_change: append_new_columns

seeds:
  peoplepulse_transforms:
    +schema: GOLD
    dim_date:
      +column_types:
        date_key: int

packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.0.0", "<2.0.0"]
  - package: calogica/dbt_date
    version: [">=0.9.0", "<1.0.0"]
  - package: dbt-labs/codegen
    version: [">=0.9.0"]


-- ─────────────────────────────────────────────────────────────
-- Power BI Relationship Map (documentation)
-- ─────────────────────────────────────────────────────────────

-- POWER BI MODEL RELATIONSHIPS (all Many-to-One, single direction)
-- ──────────────────────────────────────────────────────────────
-- FACT TABLE                   FK Column              → DIMENSION TABLE        PK
-- FACT_EMPLOYEE_SNAPSHOT.employee_key               → DIM_EMPLOYEE.employee_key
-- FACT_EMPLOYEE_SNAPSHOT.date_key                   → DIM_DATE.date_key
-- FACT_EMPLOYEE_SNAPSHOT.department_key             → DIM_DEPARTMENT.department_key
-- FACT_EMPLOYEE_SNAPSHOT.location_key               → DIM_LOCATION.location_key
-- FACT_EMPLOYEE_SNAPSHOT.manager_key                → DIM_MANAGER.manager_key
-- FACT_EMPLOYEE_SNAPSHOT.role_key                   → DIM_ROLE.role_key
--
-- FACT_ATTENDANCE.employee_key                      → DIM_EMPLOYEE.employee_key
-- FACT_ATTENDANCE.date_key                          → DIM_DATE.date_key  (INACTIVE — use DIM_DATE[Attendance Date])
-- FACT_ATTENDANCE.department_key                    → DIM_DEPARTMENT.department_key
--
-- FACT_PERFORMANCE.employee_key                     → DIM_EMPLOYEE.employee_key
-- FACT_PERFORMANCE.manager_key                      → DIM_MANAGER.manager_key
-- FACT_PERFORMANCE.review_date_key                  → DIM_DATE.date_key  (INACTIVE — use DIM_DATE[Review Date])
-- FACT_PERFORMANCE.department_key                   → DIM_DEPARTMENT.department_key
-- FACT_PERFORMANCE.role_key                         → DIM_ROLE.role_key
--
-- FACT_RECRUITMENT.department_key                   → DIM_DEPARTMENT.department_key
-- FACT_RECRUITMENT.role_key                         → DIM_ROLE.role_key
-- FACT_RECRUITMENT.manager_key                      → DIM_MANAGER.manager_key
-- FACT_RECRUITMENT.open_date_key                    → DIM_DATE.date_key  (INACTIVE — use DIM_DATE[Open Date])
-- FACT_RECRUITMENT.location_key                     → DIM_LOCATION.location_key
--
-- FACT_COMPENSATION.employee_key                    → DIM_EMPLOYEE.employee_key
-- FACT_COMPENSATION.effective_date_key              → DIM_DATE.date_key  (INACTIVE — use DIM_DATE[Effective Date])
-- FACT_COMPENSATION.department_key                  → DIM_DEPARTMENT.department_key
-- FACT_COMPENSATION.role_key                        → DIM_ROLE.role_key
--
-- FACT_TRAINING.employee_key                        → DIM_EMPLOYEE.employee_key
-- FACT_TRAINING.enrollment_date_key                 → DIM_DATE.date_key  (INACTIVE — use DIM_DATE[Enrollment Date])
-- FACT_TRAINING.department_key                      → DIM_DEPARTMENT.department_key
-- FACT_TRAINING.role_key                            → DIM_ROLE.role_key
--
-- DIM_MANAGER.employee_key                          → DIM_EMPLOYEE.employee_key
-- DIM_DEPARTMENT.parent_department_key              → DIM_DEPARTMENT.department_key (self-ref hierarchy)
--
-- NOTE: Multiple fact tables share DIM_DATE — Power BI handles this via
-- INACTIVE relationships. Use USERELATIONSHIP() in DAX measures.
-- Example: Attrition Date = CALCULATE([Attrition Count],
--   USERELATIONSHIP(FACT_EMPLOYEE_SNAPSHOT[date_key], DIM_DATE[date_key]))

-- ============================================================
-- END OF dbt MODEL STUBS
-- PeoplePulse AI | Phase 2 Data Engineering
-- ============================================================
