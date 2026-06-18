-- ============================================================
-- PEOPLEPULSE AI — POSTGRESQL SCHEMA
-- Compatible with: PostgreSQL 13+
-- Adapted from sql/03_sql_library.sql (originally T-SQL/Snowflake)
-- ============================================================
-- This file is the PRIMARY schema for local development since
-- PostgreSQL is free, runs everywhere, and is the default DB_ENGINE
-- in .env.example. MySQL and SQL Server variants are provided in
-- sql/mysql_schema.sql and sql/mssql_schema.sql respectively.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS hr;
CREATE SCHEMA IF NOT EXISTS rpt;
CREATE SCHEMA IF NOT EXISTS audit;

-- ============================================================
-- REFERENCE TABLES
-- ============================================================

CREATE TABLE hr.ref_department (
    department_id       SMALLSERIAL PRIMARY KEY,
    department_name     VARCHAR(100) NOT NULL UNIQUE,
    pay_multiplier       NUMERIC(5,4) NOT NULL DEFAULT 1.0000
                          CHECK (pay_multiplier BETWEEN 0.5 AND 2.5),
    base_attrition_rate  NUMERIC(5,4) NOT NULL DEFAULT 0.1500
                          CHECK (base_attrition_rate BETWEEN 0 AND 1),
    is_active            BOOLEAN NOT NULL DEFAULT TRUE,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE hr.ref_job_level (
    level_code      CHAR(2) PRIMARY KEY,
    level_name      VARCHAR(50) NOT NULL,
    salary_band_min INTEGER NOT NULL,
    salary_band_max INTEGER NOT NULL,
    career_track    VARCHAR(30) NOT NULL
                     CHECK (career_track IN ('Individual-Contributor','Manager','Executive')),
    sort_order      SMALLINT NOT NULL,
    CHECK (salary_band_min < salary_band_max)
);

CREATE TABLE hr.ref_location (
    location_id    SMALLSERIAL PRIMARY KEY,
    location_name  VARCHAR(100) NOT NULL UNIQUE,
    city           VARCHAR(100) NOT NULL,
    country        VARCHAR(60) NOT NULL,
    region         VARCHAR(20) NOT NULL
                    CHECK (region IN ('Northeast','South','West','Midwest','Remote','EMEA','Canada')),
    geo_multiplier NUMERIC(5,4) NOT NULL DEFAULT 1.0000,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE hr.ref_recruitment_source (
    source_id    SMALLSERIAL PRIMARY KEY,
    source_name  VARCHAR(60) NOT NULL UNIQUE,
    source_type  VARCHAR(30) NOT NULL
                  CHECK (source_type IN ('Digital','Referral','Agency','Campus','Internal','Direct')),
    is_active    BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE hr.ref_performance_rating (
    rating_value      SMALLINT PRIMARY KEY CHECK (rating_value BETWEEN 1 AND 5),
    rating_label      VARCHAR(30) NOT NULL,
    is_high_performer BOOLEAN NOT NULL DEFAULT FALSE
);

-- ============================================================
-- CORE EMPLOYEE TABLE
-- ============================================================

CREATE TABLE hr.employee (
    employee_id          VARCHAR(10) PRIMARY KEY,
    employee_name        VARCHAR(200) NOT NULL,
    age                  SMALLINT NOT NULL CHECK (age BETWEEN 16 AND 80),
    gender               VARCHAR(20) NOT NULL CHECK (gender IN ('Male','Female','Non-binary')),

    department_id        SMALLINT NOT NULL REFERENCES hr.ref_department(department_id),
    job_role              VARCHAR(100) NOT NULL,
    job_level             CHAR(2) NOT NULL REFERENCES hr.ref_job_level(level_code),
    manager_id            VARCHAR(10) REFERENCES hr.employee(employee_id),
    location_id           SMALLINT NOT NULL REFERENCES hr.ref_location(location_id),

    work_mode             VARCHAR(20) NOT NULL CHECK (work_mode IN ('On-site','Hybrid','Remote')),
    years_at_company      NUMERIC(5,2) NOT NULL CHECK (years_at_company >= 0),
    salary                INTEGER NOT NULL CHECK (salary BETWEEN 30000 AND 2000000),
    bonus                 INTEGER NOT NULL DEFAULT 0 CHECK (bonus >= 0),
    recruitment_source_id SMALLINT NOT NULL REFERENCES hr.ref_recruitment_source(source_id),

    performance_rating    SMALLINT NOT NULL REFERENCES hr.ref_performance_rating(rating_value),
    performance_label     VARCHAR(30) NOT NULL,
    attendance_pct        NUMERIC(5,2) NOT NULL CHECK (attendance_pct BETWEEN 0 AND 100),
    training_hours        NUMERIC(6,2) NOT NULL CHECK (training_hours >= 0),
    engagement_score      NUMERIC(6,2) NOT NULL CHECK (engagement_score BETWEEN 0 AND 100),
    satisfaction_score    NUMERIC(6,2) NOT NULL CHECK (satisfaction_score BETWEEN 0 AND 100),

    promotions            SMALLINT NOT NULL DEFAULT 0 CHECK (promotions >= 0),
    leave_count           SMALLINT NOT NULL DEFAULT 0 CHECK (leave_count BETWEEN 0 AND 365),

    attrition             VARCHAR(3) NOT NULL CHECK (attrition IN ('Yes','No')),
    exit_reason           VARCHAR(60),

    loaded_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_employee_department ON hr.employee (department_id);
CREATE INDEX ix_employee_attrition  ON hr.employee (attrition);
CREATE INDEX ix_employee_job_level  ON hr.employee (job_level);
CREATE INDEX ix_employee_manager    ON hr.employee (manager_id);
CREATE INDEX ix_employee_location   ON hr.employee (location_id);
CREATE INDEX ix_employee_active     ON hr.employee (department_id, job_level, salary, engagement_score)
    WHERE attrition = 'No';

-- ============================================================
-- FLIGHT RISK SCORES (Phase 8 ML output)
-- ============================================================

CREATE TABLE hr.flight_risk_score (
    score_id           BIGSERIAL PRIMARY KEY,
    employee_id        VARCHAR(10) NOT NULL REFERENCES hr.employee(employee_id),
    scoring_date       DATE NOT NULL DEFAULT CURRENT_DATE,
    risk_score         NUMERIC(5,2) NOT NULL CHECK (risk_score BETWEEN 0 AND 100),
    risk_tier          VARCHAR(20) NOT NULL CHECK (risk_tier IN ('Critical','High','Medium','Low')),
    model_probability  NUMERIC(8,6) NOT NULL,
    top_driver_1       VARCHAR(150),
    top_driver_2       VARCHAR(150),
    top_driver_3       VARCHAR(150),
    recommended_action VARCHAR(250),
    model_version      VARCHAR(20) NOT NULL DEFAULT 'v1.0',
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (employee_id, scoring_date)
);

CREATE INDEX ix_frs_employee_date ON hr.flight_risk_score (employee_id, scoring_date DESC);
CREATE INDEX ix_frs_tier          ON hr.flight_risk_score (risk_tier);

-- ============================================================
-- AUDIT LOG
-- ============================================================

CREATE TABLE audit.employee_change_log (
    change_id      BIGSERIAL PRIMARY KEY,
    employee_id    VARCHAR(10) NOT NULL,
    changed_column VARCHAR(100) NOT NULL,
    old_value      TEXT,
    new_value      TEXT,
    changed_by     VARCHAR(100) NOT NULL DEFAULT current_user,
    changed_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    change_reason  VARCHAR(200)
);

CREATE INDEX ix_audit_emp_date ON audit.employee_change_log (employee_id, changed_at DESC);

-- ============================================================
-- USERS TABLE (for non-demo authentication mode)
-- ============================================================

CREATE TABLE hr.app_user (
    user_id        SERIAL PRIMARY KEY,
    email          VARCHAR(200) NOT NULL UNIQUE,
    full_name      VARCHAR(200) NOT NULL,
    password_hash  VARCHAR(64) NOT NULL,   -- SHA-256 hex digest
    role           VARCHAR(30) NOT NULL
                   CHECK (role IN ('CEO/CHRO','HR Director','HRBP','Total Rewards','Admin')),
    department_id  SMALLINT REFERENCES hr.ref_department(department_id),  -- NULL = all departments
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================
-- REFERENCE DATA SEED
-- ============================================================

INSERT INTO hr.ref_department (department_name, pay_multiplier, base_attrition_rate) VALUES
    ('Engineering',        1.3500, 0.1400),
    ('Product',            1.4000, 0.1300),
    ('Sales',              1.1000, 0.2000),
    ('Marketing',          1.0500, 0.1600),
    ('Finance',            1.1500, 0.0900),
    ('Human Resources',    0.9500, 0.1200),
    ('Operations',         0.9000, 0.1700),
    ('Customer Success',   0.8800, 0.2200),
    ('Legal & Compliance', 1.3000, 0.0700),
    ('Data & Analytics',   1.3800, 0.1300),
    ('IT Infrastructure',  1.1000, 0.1100);

INSERT INTO hr.ref_job_level (level_code, level_name, salary_band_min, salary_band_max, career_track, sort_order) VALUES
    ('L2','Associate',         55000,  85000, 'Individual-Contributor', 1),
    ('L3','Specialist',        85000, 110000, 'Individual-Contributor', 2),
    ('L4','Senior Specialist', 110000,140000, 'Individual-Contributor', 3),
    ('L5','Staff / Principal', 140000,175000, 'Manager',               4),
    ('L6','Director',          175000,230000, 'Manager',               5),
    ('L7','Vice President',    230000,320000, 'Executive',             6),
    ('L8','C-Suite',           320000,500000, 'Executive',             7);

INSERT INTO hr.ref_location (location_name, city, country, region, geo_multiplier) VALUES
    ('New York, NY',     'New York',     'USA',    'Northeast', 1.2800),
    ('San Francisco, CA','San Francisco','USA',    'West',      1.3000),
    ('Austin, TX',       'Austin',       'USA',    'South',     1.0500),
    ('Seattle, WA',      'Seattle',      'USA',    'West',      1.2200),
    ('Chicago, IL',      'Chicago',      'USA',    'Midwest',   1.0800),
    ('Boston, MA',       'Boston',       'USA',    'Northeast', 1.1800),
    ('Denver, CO',       'Denver',       'USA',    'West',      1.0200),
    ('Atlanta, GA',      'Atlanta',      'USA',    'South',     0.9700),
    ('Remote - US',      'Remote',       'USA',    'Remote',    0.9500),
    ('London, UK',       'London',       'UK',     'EMEA',      1.1500),
    ('Toronto, Canada',  'Toronto',      'Canada', 'Canada',    0.8800);

INSERT INTO hr.ref_recruitment_source (source_name, source_type) VALUES
    ('LinkedIn',          'Digital'),
    ('Employee Referral', 'Referral'),
    ('Company Website',   'Direct'),
    ('Indeed',            'Digital'),
    ('Recruiter/Agency',  'Agency'),
    ('University Campus', 'Campus'),
    ('Glassdoor',         'Digital'),
    ('Internal Transfer', 'Internal');

INSERT INTO hr.ref_performance_rating (rating_value, rating_label, is_high_performer) VALUES
    (1, 'Unacceptable',         FALSE),
    (2, 'Below Expectations',   FALSE),
    (3, 'Meets Expectations',   FALSE),
    (4, 'Exceeds Expectations', TRUE),
    (5, 'Distinguished',        TRUE);

-- Seed users for non-demo authentication mode.
-- Password hashes below are verified SHA-256 hex digests of the demo
-- passwords (generated via scripts/generate_password_hashes.py — re-run
-- that script if you change any password). These match the credentials
-- documented in streamlit_app/utils/helpers.py USER_DIRECTORY.

INSERT INTO hr.app_user (email, full_name, password_hash, role, department_id) VALUES
    ('ceo@peoplepulse.ai',          'Victoria Chen',   '240be518fabd2724ddb6f04eeb1da5967448d7e831c08c8fa822809f74c720a9', 'CEO/CHRO',      NULL),
    ('hrdirector@peoplepulse.ai',   'Marcus Williams', 'd695c36cbf5ef7f0e855d7b894cba8886acd9a5854876614929294613e2ab310', 'HR Director',   NULL),
    ('totalrewards@peoplepulse.ai', 'David Osei',      '2373d5e4645f099f0e3087207f9151c8afecc42e6e067c071f71ced4ebfeff41', 'Total Rewards', NULL),
    ('admin@peoplepulse.ai',        'System Admin',    '4e4c56e4a15f89f05c2f4c72613da2a18c9665d4f0d6acce16415eb06f9be776', 'Admin',         NULL);

-- HRBP users require a department FK — resolved via lookup against ref_department
INSERT INTO hr.app_user (email, full_name, password_hash, role, department_id)
SELECT 'hrbp.cs@peoplepulse.ai', 'Priya Nair', '1ed33b3edce2ec4132d281f1ef7239adf36a9b6e91d18cead3b57dc775cec2c8',
       'HRBP', department_id FROM hr.ref_department WHERE department_name='Customer Success';

INSERT INTO hr.app_user (email, full_name, password_hash, role, department_id)
SELECT 'hrbp.eng@peoplepulse.ai', 'Rachel Kim', '1ed33b3edce2ec4132d281f1ef7239adf36a9b6e91d18cead3b57dc775cec2c8',
       'HRBP', department_id FROM hr.ref_department WHERE department_name='Engineering';

-- ============================================================
-- VIEWS
-- ============================================================

CREATE OR REPLACE VIEW rpt.vw_employee_full AS
SELECT
    e.employee_id,
    e.employee_name,
    e.age,
    e.gender,
    CASE
        WHEN e.age < 25 THEN 'Under 25'
        WHEN e.age < 35 THEN '25-34'
        WHEN e.age < 45 THEN '35-44'
        WHEN e.age < 55 THEN '45-54'
        WHEN e.age < 65 THEN '55-64'
        ELSE '65+'
    END AS age_band,
    d.department_name AS department,
    e.job_role,
    e.job_level,
    jl.level_name,
    jl.career_track,
    l.location_name AS location,
    l.region,
    e.work_mode,
    e.manager_id,
    e.years_at_company,
    CASE
        WHEN e.years_at_company < 1  THEN '< 1 Year'
        WHEN e.years_at_company < 2  THEN '1-2 Years'
        WHEN e.years_at_company < 3  THEN '2-3 Years'
        WHEN e.years_at_company < 5  THEN '3-5 Years'
        WHEN e.years_at_company < 8  THEN '5-8 Years'
        WHEN e.years_at_company < 12 THEN '8-12 Years'
        ELSE '12+ Years'
    END AS tenure_band,
    e.salary,
    e.bonus,
    e.salary + e.bonus AS total_comp,
    ROUND(e.salary::NUMERIC / NULLIF(jl.salary_band_min + (jl.salary_band_max-jl.salary_band_min)/2, 0), 4) AS compa_ratio,
    rs.source_name AS recruitment_source,
    e.performance_rating,
    e.performance_label,
    pr.is_high_performer,
    e.attendance_pct,
    e.training_hours,
    e.engagement_score,
    e.satisfaction_score,
    CASE
        WHEN e.engagement_score >= 75 THEN 'Engaged'
        WHEN e.engagement_score >= 60 THEN 'Low Risk'
        WHEN e.engagement_score >= 40 THEN 'Medium Risk'
        ELSE 'High Risk'
    END AS engagement_tier,
    e.promotions,
    e.leave_count,
    ROUND(e.years_at_company/2.8 - e.promotions, 2) AS promotion_gap,
    e.attrition,
    CASE e.attrition WHEN 'Yes' THEN 1 ELSE 0 END AS attrition_flag,
    e.exit_reason,
    CASE WHEN e.attrition='Yes' AND pr.is_high_performer THEN 1 ELSE 0 END AS is_regrettable_exit
FROM hr.employee e
JOIN hr.ref_department d ON e.department_id = d.department_id
JOIN hr.ref_job_level jl ON e.job_level = jl.level_code
JOIN hr.ref_location l ON e.location_id = l.location_id
JOIN hr.ref_recruitment_source rs ON e.recruitment_source_id = rs.source_id
JOIN hr.ref_performance_rating pr ON e.performance_rating = pr.rating_value;

CREATE OR REPLACE VIEW rpt.vw_department_kpis AS
SELECT
    d.department_name,
    COUNT(*) AS total_headcount,
    SUM(CASE WHEN e.attrition='No' THEN 1 ELSE 0 END) AS active_headcount,
    SUM(CASE WHEN e.attrition='Yes' THEN 1 ELSE 0 END) AS attrition_count,
    ROUND(100.0 * SUM(CASE WHEN e.attrition='Yes' THEN 1 ELSE 0 END) / COUNT(*), 2) AS attrition_rate_pct,
    ROUND(AVG(e.salary)) AS avg_salary,
    ROUND(AVG(e.engagement_score), 2) AS avg_engagement_score,
    ROUND(AVG(e.satisfaction_score), 2) AS avg_satisfaction_score,
    ROUND(AVG(e.performance_rating), 3) AS avg_performance_rating,
    ROUND(AVG(e.attendance_pct), 2) AS avg_attendance_pct,
    ROUND(AVG(e.training_hours), 2) AS avg_training_hours,
    ROUND(AVG(e.years_at_company), 2) AS avg_tenure_years,
    SUM(CASE WHEN e.performance_rating >= 4 THEN 1 ELSE 0 END) AS high_performer_count,
    ROUND(100.0 * SUM(CASE WHEN e.performance_rating >= 4 THEN 1 ELSE 0 END) / COUNT(*), 2) AS high_performer_pct,
    SUM(CASE WHEN e.engagement_score < 40 THEN 1 ELSE 0 END) AS high_flight_risk_count,
    ROUND(100.0 * SUM(CASE WHEN e.attrition='Yes' AND e.performance_rating>=4 THEN 1 ELSE 0 END) / COUNT(*), 2) AS regrettable_attrition_pct
FROM hr.employee e
JOIN hr.ref_department d ON e.department_id = d.department_id
GROUP BY d.department_id, d.department_name;

CREATE OR REPLACE VIEW rpt.vw_pay_equity AS
WITH level_stats AS (
    SELECT
        job_level,
        gender,
        COUNT(*) AS employee_count,
        AVG(salary) AS avg_salary,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) OVER (PARTITION BY job_level) AS level_median,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary) OVER (PARTITION BY job_level, gender) AS gender_median
    FROM hr.employee
)
SELECT DISTINCT
    job_level, gender, employee_count,
    ROUND(avg_salary) AS avg_salary,
    ROUND(level_median) AS level_median,
    ROUND(gender_median) AS gender_median,
    ROUND(100.0 * (gender_median - level_median) / NULLIF(level_median,0), 2) AS pay_gap_vs_median_pct
FROM level_stats;

-- ============================================================
-- END OF POSTGRESQL SCHEMA
-- ============================================================
