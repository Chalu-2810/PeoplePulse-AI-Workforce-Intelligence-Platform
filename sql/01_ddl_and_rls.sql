-- ============================================================
-- PEOPLEPULSE AI — SNOWFLAKE DDL SCRIPTS (PRODUCTION)
-- Phase 2: Data Engineering & Data Modeling
-- Warehouse: Snowflake | Schema: ANALYTICS | Layer: GOLD
-- ============================================================

-- ============================================================
-- 0. DATABASE & SCHEMA SETUP
-- ============================================================

CREATE DATABASE IF NOT EXISTS PEOPLEPULSE_DWH
  DATA_RETENTION_TIME_IN_DAYS = 14
  COMMENT = 'PeoplePulse AI Enterprise Data Warehouse';

CREATE SCHEMA IF NOT EXISTS PEOPLEPULSE_DWH.GOLD
  DATA_RETENTION_TIME_IN_DAYS = 14
  COMMENT = 'Semantic / business-ready layer — served to Power BI and APIs';

CREATE SCHEMA IF NOT EXISTS PEOPLEPULSE_DWH.SILVER
  DATA_RETENTION_TIME_IN_DAYS = 7
  COMMENT = 'Standardized, deduplicated, USD-normalized layer';

CREATE SCHEMA IF NOT EXISTS PEOPLEPULSE_DWH.BRONZE
  DATA_RETENTION_TIME_IN_DAYS = 3
  COMMENT = 'Raw typed data — source system schemas preserved';

CREATE SCHEMA IF NOT EXISTS PEOPLEPULSE_DWH.AGGREGATIONS
  DATA_RETENTION_TIME_IN_DAYS = 3
  COMMENT = 'Pre-computed summary tables for Power BI sub-second response';

USE DATABASE PEOPLEPULSE_DWH;
USE SCHEMA GOLD;

-- ============================================================
-- 1. DIMENSION TABLES
-- ============================================================

-- ─────────────────────────────────────────
-- DIM_DATE  (static, pre-populated via dbt seed)
-- ─────────────────────────────────────────
CREATE OR REPLACE TABLE DIM_DATE (
    date_key                INT             NOT NULL        COMMENT 'YYYYMMDD integer PK (e.g. 20240315)',
    full_date               DATE            NOT NULL        COMMENT 'Actual date — mark as Date Table in Power BI',
    day_of_week_num         TINYINT         NOT NULL        COMMENT '1=Monday through 7=Sunday',
    day_of_week_name        VARCHAR(10)     NOT NULL,
    day_of_week_short       CHAR(3)         NOT NULL,
    day_of_month            TINYINT         NOT NULL,
    day_of_year             SMALLINT        NOT NULL,
    week_of_year            TINYINT         NOT NULL,
    iso_year_week           VARCHAR(8)      NOT NULL        COMMENT '2024-W12',
    month_num               TINYINT         NOT NULL,
    month_name              VARCHAR(10)     NOT NULL,
    month_short             CHAR(3)         NOT NULL,
    month_year              VARCHAR(8)      NOT NULL        COMMENT 'Jan-2024',
    quarter_num             TINYINT         NOT NULL,
    quarter_label           VARCHAR(2)      NOT NULL        COMMENT 'Q1..Q4',
    year_num                SMALLINT        NOT NULL,
    year_quarter            VARCHAR(7)      NOT NULL        COMMENT '2024-Q1',
    is_weekday_flag         BOOLEAN         NOT NULL,
    is_weekend_flag         BOOLEAN         NOT NULL,
    is_company_holiday_flag BOOLEAN         NOT NULL        DEFAULT FALSE,
    is_us_federal_holiday_flag BOOLEAN      NOT NULL        DEFAULT FALSE,
    is_month_end_flag       BOOLEAN         NOT NULL,
    is_quarter_end_flag     BOOLEAN         NOT NULL,
    is_year_end_flag        BOOLEAN         NOT NULL,
    fiscal_year             SMALLINT        NOT NULL,
    fiscal_quarter_num      TINYINT         NOT NULL,
    fiscal_quarter_label    VARCHAR(8)      NOT NULL        COMMENT 'FY24-Q1',
    fiscal_month_num        TINYINT         NOT NULL,
    fiscal_period_label     VARCHAR(8)      NOT NULL        COMMENT 'FY24-P03',
    days_in_month           TINYINT         NOT NULL,
    relative_day_offset     INT             NOT NULL        COMMENT 'Days from today (negative=past)',
    relative_month_offset   INT             NOT NULL,
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key)
)
COMMENT = 'Standard time dimension — 10-year pre-populated calendar. Mark as Date Table in Power BI.'
DATA_RETENTION_TIME_IN_DAYS = 0;  -- Static table, no time-travel needed


-- ─────────────────────────────────────────
-- DIM_EMPLOYEE  (SCD Type 2)
-- ─────────────────────────────────────────
CREATE OR REPLACE TABLE DIM_EMPLOYEE (
    employee_key            INT             NOT NULL AUTOINCREMENT COMMENT 'Surrogate key — new row per SCD2 version',
    employee_id             VARCHAR(20)     NOT NULL        COMMENT 'Natural key from HRIS (stable across versions)',
    employee_global_id      VARCHAR(36)     NOT NULL        COMMENT 'UUID for cross-system identity',
    scd_version             SMALLINT        NOT NULL        DEFAULT 1,
    effective_start_date    DATE            NOT NULL,
    effective_end_date      DATE                            COMMENT 'NULL = current active version',
    is_current_flag         BOOLEAN         NOT NULL        DEFAULT TRUE,
    first_name              VARCHAR(100)    NOT NULL,
    last_name               VARCHAR(100)    NOT NULL,
    full_name               VARCHAR(200)    NOT NULL,
    preferred_name          VARCHAR(100),
    email_work              VARCHAR(200)    NOT NULL,
    hire_date               DATE            NOT NULL        COMMENT 'Never changes across SCD2 versions',
    rehire_date             DATE,
    termination_date        DATE,
    birth_date              DATE                            COMMENT 'PII — masked for ANALYST role',
    age_band_code           VARCHAR(20)                     COMMENT '<25 / 25-34 / 35-44 / 45-54 / 55-64 / 65+',
    gender_code             VARCHAR(20)                     COMMENT 'PII — masked for most roles',
    ethnicity_code          VARCHAR(30)                     COMMENT 'PII — EEOC categories',
    nationality_code        CHAR(2)                         COMMENT 'ISO 3166 alpha-2',
    highest_education_code  VARCHAR(30),
    years_experience_prior  DECIMAL(4,1),
    employment_status_code  VARCHAR(20)     NOT NULL        COMMENT 'Active / Terminated / LOA / Inactive',
    employee_type_code      VARCHAR(20)     NOT NULL        COMMENT 'Full-Time / Part-Time / Contract / Intern',
    flsa_status_code        VARCHAR(20)                     COMMENT 'Exempt / Non-Exempt (US)',
    remote_work_type_code   VARCHAR(20)                     COMMENT 'On-site / Hybrid / Fully-Remote',
    source_system_code      VARCHAR(30)     NOT NULL        COMMENT 'Workday / BambooHR / SAP / ADP',
    created_at              TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    updated_at              TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_dim_employee PRIMARY KEY (employee_key)
)
CLUSTER BY (employee_id, is_current_flag)
COMMENT = 'Master employee dimension — SCD Type 2. New row inserted on every attribute change.';

-- Index on natural key for SCD2 merge operations
CREATE OR REPLACE INDEX idx_dim_employee_natural
    ON DIM_EMPLOYEE (employee_id, is_current_flag);


-- ─────────────────────────────────────────
-- DIM_DEPARTMENT  (SCD Type 1 with self-referencing hierarchy)
-- ─────────────────────────────────────────
CREATE OR REPLACE TABLE DIM_DEPARTMENT (
    department_key              INT             NOT NULL AUTOINCREMENT,
    department_id               VARCHAR(30)     NOT NULL        COMMENT 'Natural key from HRIS',
    department_name             VARCHAR(100)    NOT NULL,
    department_code             VARCHAR(20)     NOT NULL,
    cost_center_code            VARCHAR(30)     NOT NULL,
    company_code                VARCHAR(20)     NOT NULL,
    division_name               VARCHAR(100)    NOT NULL,
    division_code               VARCHAR(20)     NOT NULL,
    function_name               VARCHAR(100)    NOT NULL,
    function_code               VARCHAR(20)     NOT NULL,
    sub_function_name           VARCHAR(100),
    department_head_employee_key INT                             COMMENT 'FK → DIM_EMPLOYEE',
    parent_department_key       INT                             COMMENT 'FK → DIM_DEPARTMENT (self-ref)',
    hierarchy_level             TINYINT         NOT NULL        COMMENT '1=Company 2=Division 3=Function 4=Dept 5=Team',
    hierarchy_path              VARCHAR(500)    NOT NULL        COMMENT 'Full path: Org/Tech/Engineering/Platform',
    headcount_budget            INT,
    opex_budget_usd             DECIMAL(18,2),
    is_active_flag              BOOLEAN         NOT NULL        DEFAULT TRUE,
    effective_start_date        DATE            NOT NULL,
    effective_end_date          DATE,
    created_at                  TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_dim_department PRIMARY KEY (department_key),
    CONSTRAINT fk_dept_parent FOREIGN KEY (parent_department_key) REFERENCES DIM_DEPARTMENT(department_key)
)
COMMENT = 'Organizational hierarchy — 5 levels. SCD Type 1 (overwrite on change). Self-referencing for drill-down.';


-- ─────────────────────────────────────────
-- DIM_LOCATION
-- ─────────────────────────────────────────
CREATE OR REPLACE TABLE DIM_LOCATION (
    location_key                INT             NOT NULL AUTOINCREMENT,
    location_id                 VARCHAR(30)     NOT NULL,
    location_name               VARCHAR(100)    NOT NULL,
    location_type_code          VARCHAR(30)     NOT NULL        COMMENT 'Headquarters / Regional / Satellite / Home / Remote',
    address_line_1              VARCHAR(200),
    city_name                   VARCHAR(100)    NOT NULL,
    state_province_code         VARCHAR(10),
    state_province_name         VARCHAR(100),
    country_code                CHAR(2)         NOT NULL        COMMENT 'ISO 3166-1 alpha-2',
    country_name                VARCHAR(100)    NOT NULL,
    region_code                 VARCHAR(20)     NOT NULL        COMMENT 'AMER / EMEA / APAC / LATAM',
    region_name                 VARCHAR(50)     NOT NULL,
    metro_area_code             VARCHAR(30),
    timezone_code               VARCHAR(50)     NOT NULL        COMMENT 'IANA timezone',
    geo_differential_factor     DECIMAL(6,4)                    COMMENT 'Cost-of-living multiplier for comp benchmarking',
    is_remote_eligible_flag     BOOLEAN         NOT NULL        DEFAULT FALSE,
    latitude                    DECIMAL(10,7)                   COMMENT 'For Power BI map visuals',
    longitude                   DECIMAL(10,7),
    is_active_flag              BOOLEAN         NOT NULL        DEFAULT TRUE,
    created_at                  TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_dim_location PRIMARY KEY (location_key)
)
COMMENT = 'Work location dimension with geo coordinates for map visuals. SCD Type 1.';


-- ─────────────────────────────────────────
-- DIM_ROLE  (SCD Type 2)
-- ─────────────────────────────────────────
CREATE OR REPLACE TABLE DIM_ROLE (
    role_key                INT             NOT NULL AUTOINCREMENT,
    role_id                 VARCHAR(30)     NOT NULL        COMMENT 'Natural key — job code from HRIS',
    scd_version             SMALLINT        NOT NULL        DEFAULT 1,
    effective_start_date    DATE            NOT NULL,
    effective_end_date      DATE                            COMMENT 'NULL = current version',
    is_current_flag         BOOLEAN         NOT NULL        DEFAULT TRUE,
    job_title               VARCHAR(100)    NOT NULL,
    job_title_standard      VARCHAR(100)    NOT NULL        COMMENT 'Standardized for cross-company benchmarking',
    job_family_code         VARCHAR(30)     NOT NULL        COMMENT 'Engineering / Product / Finance / Sales / HR',
    job_family_name         VARCHAR(100)    NOT NULL,
    job_function_code       VARCHAR(30)     NOT NULL,
    job_function_name       VARCHAR(100)    NOT NULL,
    job_level_code          VARCHAR(20)     NOT NULL        COMMENT 'IC1/IC2/IC3/IC4/M1/M2/M3/D1/VP1',
    job_level_name          VARCHAR(50)     NOT NULL        COMMENT 'Associate / Mid / Senior / Staff / Principal',
    career_track_code       VARCHAR(20)     NOT NULL        COMMENT 'Individual-Contributor / Manager / Executive',
    pay_grade_code          VARCHAR(20)     NOT NULL,
    flsa_status_code        VARCHAR(20)     NOT NULL        COMMENT 'Exempt / Non-Exempt',
    is_manager_role_flag    BOOLEAN         NOT NULL        DEFAULT FALSE,
    is_executive_flag       BOOLEAN         NOT NULL        DEFAULT FALSE,
    required_education_code VARCHAR(30),
    eeoc_job_category_code  VARCHAR(30)     NOT NULL        COMMENT 'EEOC category for compliance reporting',
    o_net_soc_code          VARCHAR(10)                     COMMENT 'O*NET Standard Occupational Classification',
    target_pay_range_min_usd DECIMAL(18,2),
    target_pay_range_mid_usd DECIMAL(18,2),
    target_pay_range_max_usd DECIMAL(18,2),
    required_skills         ARRAY                           COMMENT 'Array of required skill taxonomy tags',
    is_critical_role_flag   BOOLEAN         NOT NULL        DEFAULT FALSE,
    created_at              TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_dim_role PRIMARY KEY (role_key)
)
CLUSTER BY (role_id, is_current_flag)
COMMENT = 'Job architecture dimension — SCD Type 2. Tracks job code reclassifications over time.';


-- ─────────────────────────────────────────
-- DIM_MANAGER  (SCD Type 2, role-playing extension of DIM_EMPLOYEE)
-- ─────────────────────────────────────────
CREATE OR REPLACE TABLE DIM_MANAGER (
    manager_key                     INT             NOT NULL AUTOINCREMENT,
    employee_key                    INT             NOT NULL        COMMENT 'FK → DIM_EMPLOYEE',
    employee_id                     VARCHAR(20)     NOT NULL        COMMENT 'Denormalized for query performance',
    full_name                       VARCHAR(200)    NOT NULL        COMMENT 'Denormalized for display',
    department_key                  INT             NOT NULL        COMMENT 'FK → DIM_DEPARTMENT',
    management_level_code           VARCHAR(30)     NOT NULL        COMMENT 'Team-Lead / Manager / Director / VP / SVP / C-Suite',
    direct_report_count             INT             NOT NULL        DEFAULT 0,
    total_org_size                  INT             NOT NULL        DEFAULT 0,
    span_of_control_ratio           DECIMAL(5,2)    NOT NULL        DEFAULT 0,
    tenure_as_manager_months        INT             NOT NULL        DEFAULT 0,
    manager_effectiveness_score     DECIMAL(5,2)                    COMMENT 'Composite: team engagement + attrition + 360',
    team_voluntary_attrition_rate   DECIMAL(6,4)                    COMMENT 'Rolling 12-month',
    team_engagement_score_avg       DECIMAL(5,2),
    team_performance_avg            DECIMAL(5,2),
    upward_feedback_score           DECIMAL(5,2)                    COMMENT 'From 360/upward feedback surveys',
    promotion_rate_of_team          DECIMAL(6,4),
    hire_approval_count_ytd         INT             NOT NULL        DEFAULT 0,
    termination_approval_count_ytd  INT             NOT NULL        DEFAULT 0,
    is_current_flag                 BOOLEAN         NOT NULL        DEFAULT TRUE,
    effective_start_date            DATE            NOT NULL,
    effective_end_date              DATE,
    created_at                      TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_dim_manager PRIMARY KEY (manager_key),
    CONSTRAINT fk_manager_employee FOREIGN KEY (employee_key) REFERENCES DIM_EMPLOYEE(employee_key)
)
COMMENT = 'Role-playing dimension for manager context. Extends DIM_EMPLOYEE with team-level aggregated metrics. SCD Type 2.';


-- ============================================================
-- 2. FACT TABLES
-- ============================================================

-- ─────────────────────────────────────────
-- FACT_EMPLOYEE_SNAPSHOT  (Periodic Snapshot — monthly)
-- ─────────────────────────────────────────
CREATE OR REPLACE TABLE FACT_EMPLOYEE_SNAPSHOT (
    employee_snapshot_key   BIGINT          NOT NULL AUTOINCREMENT,
    employee_key            INT             NOT NULL,
    employee_id             VARCHAR(20)     NOT NULL        COMMENT 'Denormalized natural key for filtering performance',
    date_key                INT             NOT NULL,
    department_key          INT             NOT NULL,
    location_key            INT             NOT NULL,
    manager_key             INT                             COMMENT 'NULL = no manager (CEO level)',
    role_key                INT             NOT NULL,
    employment_status_code  VARCHAR(20)     NOT NULL,
    employment_type_code    VARCHAR(20)     NOT NULL,
    fte_value               DECIMAL(5,2)    NOT NULL        DEFAULT 1.0,
    tenure_months           INT             NOT NULL,
    tenure_band_code        VARCHAR(20)     NOT NULL,
    is_active_flag          BOOLEAN         NOT NULL,
    is_regrettable_exit_flag BOOLEAN                        COMMENT 'Populated only on termination rows',
    voluntary_exit_flag     BOOLEAN,
    exit_reason_code        VARCHAR(50),
    compa_ratio             DECIMAL(6,4),
    total_comp_usd          DECIMAL(18,2),
    performance_rating_code VARCHAR(20),
    flight_risk_score       DECIMAL(5,2)                    COMMENT 'ML model output 0-100, weekly refresh',
    engagement_score        DECIMAL(5,2),
    created_at              TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    updated_at              TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_fact_employee_snapshot PRIMARY KEY (employee_snapshot_key),
    CONSTRAINT fk_fes_employee     FOREIGN KEY (employee_key)   REFERENCES DIM_EMPLOYEE(employee_key),
    CONSTRAINT fk_fes_date         FOREIGN KEY (date_key)       REFERENCES DIM_DATE(date_key),
    CONSTRAINT fk_fes_department   FOREIGN KEY (department_key) REFERENCES DIM_DEPARTMENT(department_key),
    CONSTRAINT fk_fes_location     FOREIGN KEY (location_key)   REFERENCES DIM_LOCATION(location_key),
    CONSTRAINT fk_fes_role         FOREIGN KEY (role_key)       REFERENCES DIM_ROLE(role_key)
)
CLUSTER BY (date_key, department_key)
COMMENT = 'Master headcount fact — monthly snapshot grain. One row per employee per month-end date.';


-- ─────────────────────────────────────────
-- FACT_ATTENDANCE
-- ─────────────────────────────────────────
CREATE OR REPLACE TABLE FACT_ATTENDANCE (
    attendance_key          BIGINT          NOT NULL AUTOINCREMENT,
    employee_key            INT             NOT NULL,
    date_key                INT             NOT NULL,
    department_key          INT             NOT NULL,
    location_key            INT             NOT NULL,
    attendance_status_code  VARCHAR(30)     NOT NULL        COMMENT 'Present/Absent-Excused/Absent-Unexcused/Late/WFH/Leave',
    leave_type_code         VARCHAR(30)                     COMMENT 'Annual/Sick/FMLA/Parental/Bereavement/Unpaid',
    hours_scheduled         DECIMAL(5,2)    NOT NULL,
    hours_worked            DECIMAL(5,2)    NOT NULL        DEFAULT 0,
    hours_overtime          DECIMAL(5,2)    NOT NULL        DEFAULT 0,
    hours_leave_taken       DECIMAL(5,2)    NOT NULL        DEFAULT 0,
    hours_leave_balance     DECIMAL(8,2),
    late_arrival_minutes    INT             NOT NULL        DEFAULT 0,
    early_departure_minutes INT             NOT NULL        DEFAULT 0,
    is_holiday_flag         BOOLEAN         NOT NULL        DEFAULT FALSE,
    is_weekend_flag         BOOLEAN         NOT NULL        DEFAULT FALSE,
    unplanned_absence_flag  BOOLEAN         NOT NULL        DEFAULT FALSE,
    created_at              TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_fact_attendance PRIMARY KEY (attendance_key),
    CONSTRAINT fk_fa_employee    FOREIGN KEY (employee_key)   REFERENCES DIM_EMPLOYEE(employee_key),
    CONSTRAINT fk_fa_date        FOREIGN KEY (date_key)       REFERENCES DIM_DATE(date_key),
    CONSTRAINT fk_fa_department  FOREIGN KEY (department_key) REFERENCES DIM_DEPARTMENT(department_key),
    CONSTRAINT fk_fa_location    FOREIGN KEY (location_key)   REFERENCES DIM_LOCATION(location_key)
)
CLUSTER BY (date_key, employee_key)
COMMENT = 'Daily attendance records — one row per employee per work day.';


-- ─────────────────────────────────────────
-- FACT_PERFORMANCE
-- ─────────────────────────────────────────
CREATE OR REPLACE TABLE FACT_PERFORMANCE (
    performance_key             BIGINT          NOT NULL AUTOINCREMENT,
    employee_key                INT             NOT NULL,
    manager_key                 INT             NOT NULL,
    review_date_key             INT             NOT NULL,
    department_key              INT             NOT NULL,
    role_key                    INT             NOT NULL,
    review_cycle_code           VARCHAR(30)     NOT NULL        COMMENT 'Annual-2024 / Mid-Year-2024',
    review_type_code            VARCHAR(30)     NOT NULL        COMMENT 'Manager-Review / Peer-360 / Self / Calibration',
    rating_numeric              DECIMAL(4,2)    NOT NULL,
    rating_label_code           VARCHAR(30)     NOT NULL        COMMENT 'Distinguished/Exceeds/Meets/Below/Unacceptable',
    rating_normalized           DECIMAL(5,4)    NOT NULL        COMMENT '0.0–1.0 for cross-cycle comparison',
    goal_achievement_pct        DECIMAL(5,2),
    goals_set_count             INT,
    goals_achieved_count        INT,
    competency_score_avg        DECIMAL(4,2),
    leadership_score            DECIMAL(4,2)                    COMMENT 'NULL for IC roles',
    innovation_score            DECIMAL(4,2),
    collaboration_score         DECIMAL(4,2),
    execution_score             DECIMAL(4,2),
    potential_rating_code       VARCHAR(20)                     COMMENT 'High / Medium / Standard',
    pip_flag                    BOOLEAN         NOT NULL        DEFAULT FALSE,
    calibration_adjusted_flag   BOOLEAN         NOT NULL        DEFAULT FALSE,
    calibration_delta           DECIMAL(4,2),
    created_at                  TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_fact_performance PRIMARY KEY (performance_key),
    CONSTRAINT fk_fp_employee    FOREIGN KEY (employee_key)   REFERENCES DIM_EMPLOYEE(employee_key),
    CONSTRAINT fk_fp_manager     FOREIGN KEY (manager_key)    REFERENCES DIM_MANAGER(manager_key),
    CONSTRAINT fk_fp_date        FOREIGN KEY (review_date_key) REFERENCES DIM_DATE(date_key),
    CONSTRAINT fk_fp_department  FOREIGN KEY (department_key) REFERENCES DIM_DEPARTMENT(department_key),
    CONSTRAINT fk_fp_role        FOREIGN KEY (role_key)       REFERENCES DIM_ROLE(role_key)
)
CLUSTER BY (review_date_key, department_key)
COMMENT = 'Performance evaluation fact — grain: employee × review cycle × review type.';


-- ─────────────────────────────────────────
-- FACT_RECRUITMENT
-- ─────────────────────────────────────────
CREATE OR REPLACE TABLE FACT_RECRUITMENT (
    recruitment_key             BIGINT          NOT NULL AUTOINCREMENT,
    requisition_id              VARCHAR(30)     NOT NULL,
    candidate_id                VARCHAR(30)     NOT NULL,
    employee_key                INT                             COMMENT 'Populated when candidate becomes employee',
    department_key              INT             NOT NULL,
    location_key                INT             NOT NULL,
    role_key                    INT             NOT NULL,
    manager_key                 INT             NOT NULL,
    recruiter_employee_key      INT             NOT NULL        COMMENT 'FK → DIM_EMPLOYEE (recruiter)',
    open_date_key               INT             NOT NULL,
    close_date_key              INT,
    application_date_key        INT             NOT NULL,
    stage_entry_date_key        INT             NOT NULL,
    stage_exit_date_key         INT,
    hire_date_key               INT,
    source_channel_code         VARCHAR(50)     NOT NULL        COMMENT 'LinkedIn/Referral/Indeed/Agency/Career-Site',
    source_subchannel           VARCHAR(100),
    pipeline_stage_code         VARCHAR(30)     NOT NULL        COMMENT 'Applied/Screen/Phone/Onsite/Offer/Hired/Rejected',
    rejection_reason_code       VARCHAR(50),
    offer_amount_usd            DECIMAL(18,2),
    offer_accepted_flag         BOOLEAN,
    days_to_fill                INT,
    days_in_stage               INT             NOT NULL        DEFAULT 0,
    interview_count             INT             NOT NULL        DEFAULT 0,
    interview_score_avg         DECIMAL(4,2),
    candidate_nps_score         INT,
    req_priority_code           VARCHAR(20)     NOT NULL        COMMENT 'Critical / High / Standard',
    req_type_code               VARCHAR(20)     NOT NULL        COMMENT 'Backfill / New-Headcount / Replacement',
    is_diversity_hire_flag      BOOLEAN,
    created_at                  TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_fact_recruitment PRIMARY KEY (recruitment_key),
    CONSTRAINT fk_fr_department  FOREIGN KEY (department_key) REFERENCES DIM_DEPARTMENT(department_key),
    CONSTRAINT fk_fr_location    FOREIGN KEY (location_key)   REFERENCES DIM_LOCATION(location_key),
    CONSTRAINT fk_fr_role        FOREIGN KEY (role_key)       REFERENCES DIM_ROLE(role_key),
    CONSTRAINT fk_fr_manager     FOREIGN KEY (manager_key)    REFERENCES DIM_MANAGER(manager_key),
    CONSTRAINT fk_fr_date_open   FOREIGN KEY (open_date_key)  REFERENCES DIM_DATE(date_key)
)
CLUSTER BY (open_date_key, department_key)
COMMENT = 'TA funnel fact — grain: candidate application × pipeline stage transition.';


-- ─────────────────────────────────────────
-- FACT_COMPENSATION
-- ─────────────────────────────────────────
CREATE OR REPLACE TABLE FACT_COMPENSATION (
    compensation_key            BIGINT          NOT NULL AUTOINCREMENT,
    employee_key                INT             NOT NULL,
    effective_date_key          INT             NOT NULL,
    end_date_key                INT                             COMMENT 'NULL = this is the current compensation record',
    department_key              INT             NOT NULL,
    role_key                    INT             NOT NULL,
    location_key                INT             NOT NULL,
    manager_key                 INT,
    change_type_code            VARCHAR(30)     NOT NULL        COMMENT 'Hire/Merit/Promotion/Market-Adj/Equity-Correction/Off-Cycle',
    change_reason_code          VARCHAR(50),
    base_salary_new_usd         DECIMAL(18,2)   NOT NULL,
    base_salary_prev_usd        DECIMAL(18,2),
    base_salary_change_usd      DECIMAL(18,2),
    base_salary_change_pct      DECIMAL(7,4),
    local_currency_code         CHAR(3)         NOT NULL        COMMENT 'ISO 4217',
    base_salary_local           DECIMAL(18,2)   NOT NULL,
    target_bonus_pct            DECIMAL(5,2),
    target_bonus_usd            DECIMAL(18,2),
    actual_bonus_usd            DECIMAL(18,2),
    equity_grant_usd            DECIMAL(18,2),
    equity_grant_shares         INT,
    equity_vest_schedule_code   VARCHAR(20),
    total_target_comp_usd       DECIMAL(18,2),
    benefits_cost_usd           DECIMAL(18,2),
    pay_grade_code              VARCHAR(20),
    pay_range_min_usd           DECIMAL(18,2),
    pay_range_mid_usd           DECIMAL(18,2),
    pay_range_max_usd           DECIMAL(18,2),
    compa_ratio                 DECIMAL(6,4)                    COMMENT 'base / range_mid — input to ML pay equity model',
    market_percentile           DECIMAL(5,2),
    approved_by_employee_key    INT                             COMMENT 'FK → DIM_EMPLOYEE (approver)',
    created_at                  TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_fact_compensation PRIMARY KEY (compensation_key),
    CONSTRAINT fk_fc_employee    FOREIGN KEY (employee_key)        REFERENCES DIM_EMPLOYEE(employee_key),
    CONSTRAINT fk_fc_date        FOREIGN KEY (effective_date_key)  REFERENCES DIM_DATE(date_key),
    CONSTRAINT fk_fc_department  FOREIGN KEY (department_key)      REFERENCES DIM_DEPARTMENT(department_key),
    CONSTRAINT fk_fc_role        FOREIGN KEY (role_key)            REFERENCES DIM_ROLE(role_key),
    CONSTRAINT fk_fc_location    FOREIGN KEY (location_key)        REFERENCES DIM_LOCATION(location_key)
)
CLUSTER BY (effective_date_key, department_key)
COMMENT = 'Compensation change event fact — every salary change captured. Source for pay equity ML model.';


-- ─────────────────────────────────────────
-- FACT_TRAINING
-- ─────────────────────────────────────────
CREATE OR REPLACE TABLE FACT_TRAINING (
    training_key                BIGINT          NOT NULL AUTOINCREMENT,
    employee_key                INT             NOT NULL,
    course_key                  INT             NOT NULL        COMMENT 'FK → DIM_COURSE (not in core 6, extend in Phase 3)',
    enrollment_date_key         INT             NOT NULL,
    completion_date_key         INT,
    due_date_key                INT,
    department_key              INT             NOT NULL,
    role_key                    INT             NOT NULL,
    delivery_method_code        VARCHAR(30)     NOT NULL        COMMENT 'eLearning/ILT/VILT/Coaching/Conference',
    status_code                 VARCHAR(20)     NOT NULL        COMMENT 'Enrolled/In-Progress/Completed/Failed/Withdrawn',
    completion_flag             BOOLEAN         NOT NULL        DEFAULT FALSE,
    is_mandatory_flag           BOOLEAN         NOT NULL        DEFAULT FALSE,
    is_overdue_flag             BOOLEAN         NOT NULL        DEFAULT FALSE,
    hours_assigned              DECIMAL(6,2)    NOT NULL,
    hours_completed             DECIMAL(6,2)    NOT NULL        DEFAULT 0,
    assessment_score_pct        DECIMAL(5,2),
    assessment_passed_flag      BOOLEAN,
    assessment_attempts         INT             NOT NULL        DEFAULT 1,
    learning_path_code          VARCHAR(50),
    skill_domain_code           VARCHAR(50)                     COMMENT 'Technical/Leadership/Compliance/Soft-Skills',
    skill_tags                  ARRAY,
    cost_usd                    DECIMAL(10,2),
    satisfaction_score          DECIMAL(4,2),
    manager_assigned_flag       BOOLEAN         NOT NULL        DEFAULT FALSE,
    created_at                  TIMESTAMP_NTZ   NOT NULL        DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_fact_training PRIMARY KEY (training_key),
    CONSTRAINT fk_ft_employee    FOREIGN KEY (employee_key)        REFERENCES DIM_EMPLOYEE(employee_key),
    CONSTRAINT fk_ft_date_enroll FOREIGN KEY (enrollment_date_key) REFERENCES DIM_DATE(date_key),
    CONSTRAINT fk_ft_department  FOREIGN KEY (department_key)      REFERENCES DIM_DEPARTMENT(department_key),
    CONSTRAINT fk_ft_role        FOREIGN KEY (role_key)            REFERENCES DIM_ROLE(role_key)
)
CLUSTER BY (completion_date_key, department_key)
COMMENT = 'L&D activity fact — grain: employee × course enrollment.';


-- ============================================================
-- 3. PRE-AGGREGATED SUMMARY TABLES (Power BI performance layer)
-- ============================================================
-- These live in AGGREGATIONS schema, rebuilt nightly via Airflow.
-- Power BI imports these instead of querying raw facts.

USE SCHEMA AGGREGATIONS;

CREATE OR REPLACE TABLE AGG_HEADCOUNT_MONTHLY (
    date_key                INT             NOT NULL,
    department_key          INT             NOT NULL,
    location_key            INT             NOT NULL,
    role_key                INT             NOT NULL,
    employment_type_code    VARCHAR(20)     NOT NULL,
    total_headcount         INT             NOT NULL,
    active_headcount        INT             NOT NULL,
    fte_total               DECIMAL(10,2)   NOT NULL,
    avg_tenure_months       DECIMAL(8,2),
    avg_compa_ratio         DECIMAL(6,4),
    avg_flight_risk_score   DECIMAL(5,2),
    avg_engagement_score    DECIMAL(5,2),
    refreshed_at            TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_agg_headcount PRIMARY KEY (date_key, department_key, location_key, role_key, employment_type_code)
)
CLUSTER BY (date_key, department_key)
COMMENT = 'Pre-aggregated monthly headcount — Power BI performance table. Rebuilt nightly.';


CREATE OR REPLACE TABLE AGG_ATTRITION_MONTHLY (
    date_key                    INT             NOT NULL,
    department_key              INT             NOT NULL,
    location_key                INT             NOT NULL,
    role_key                    INT             NOT NULL,
    total_separations           INT             NOT NULL    DEFAULT 0,
    voluntary_separations       INT             NOT NULL    DEFAULT 0,
    involuntary_separations     INT             NOT NULL    DEFAULT 0,
    regrettable_separations     INT             NOT NULL    DEFAULT 0,
    new_hire_90day_exits        INT             NOT NULL    DEFAULT 0,
    avg_headcount_in_period     DECIMAL(10,2)   NOT NULL,
    voluntary_attrition_rate    DECIMAL(8,6)    NOT NULL,
    regrettable_attrition_rate  DECIMAL(8,6)    NOT NULL,
    refreshed_at                TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_agg_attrition PRIMARY KEY (date_key, department_key, location_key, role_key)
)
CLUSTER BY (date_key, department_key)
COMMENT = 'Pre-aggregated monthly attrition by segment — Power BI performance table.';


CREATE OR REPLACE TABLE AGG_SOURCE_QUALITY (
    quarter_key             VARCHAR(7)      NOT NULL        COMMENT 'e.g. 2024-Q1',
    source_channel_code     VARCHAR(50)     NOT NULL,
    department_key          INT             NOT NULL,
    role_key                INT             NOT NULL,
    total_hires             INT             NOT NULL    DEFAULT 0,
    avg_days_to_fill        DECIMAL(8,2),
    offer_acceptance_rate   DECIMAL(6,4),
    avg_interview_score     DECIMAL(5,2),
    retention_12m_rate      DECIMAL(6,4)                COMMENT 'Still employed at 12 months post-hire',
    quality_of_hire_score   DECIMAL(5,4)                COMMENT 'Composite: performance + retention + engagement at 12m',
    avg_cost_per_hire_usd   DECIMAL(12,2),
    refreshed_at            TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_agg_source_quality PRIMARY KEY (quarter_key, source_channel_code, department_key, role_key)
)
COMMENT = 'Source-to-quality-of-hire correlation — requires joining FACT_RECRUITMENT to FACT_PERFORMANCE at 12m.';


CREATE OR REPLACE TABLE AGG_COMPENSATION_EQUITY (
    snapshot_date_key       INT             NOT NULL,
    department_key          INT             NOT NULL,
    role_key                INT             NOT NULL,
    location_key            INT             NOT NULL,
    gender_group            VARCHAR(20)     NOT NULL    COMMENT 'Male / Female / Non-Binary / Overall',
    ethnicity_group         VARCHAR(30)     NOT NULL    COMMENT 'EEOC category or Overall',
    employee_count          INT             NOT NULL,
    avg_base_salary_usd     DECIMAL(18,2),
    median_base_salary_usd  DECIMAL(18,2),
    avg_compa_ratio         DECIMAL(6,4),
    pay_gap_vs_male_pct     DECIMAL(7,4)                COMMENT 'Unexplained gap after regression controls',
    pay_gap_usd             DECIMAL(12,2),
    gap_is_significant_flag BOOLEAN                     COMMENT 'Statistical significance p<0.05',
    refreshed_at            TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_agg_comp_equity PRIMARY KEY (snapshot_date_key, department_key, role_key, location_key, gender_group, ethnicity_group)
)
COMMENT = 'Pre-computed pay equity statistics — inputs for ML anomaly detector and Power BI heatmaps.';


CREATE OR REPLACE TABLE AGG_TRAINING_COMPLIANCE (
    date_key                INT             NOT NULL,
    department_key          INT             NOT NULL,
    role_key                INT             NOT NULL,
    skill_domain_code       VARCHAR(50)     NOT NULL,
    total_enrollments       INT             NOT NULL    DEFAULT 0,
    completions             INT             NOT NULL    DEFAULT 0,
    mandatory_completions   INT             NOT NULL    DEFAULT 0,
    mandatory_total         INT             NOT NULL    DEFAULT 0,
    overdue_count           INT             NOT NULL    DEFAULT 0,
    compliance_rate         DECIMAL(6,4),
    avg_assessment_score    DECIMAL(5,2),
    avg_satisfaction_score  DECIMAL(4,2),
    total_hours_completed   DECIMAL(12,2),
    total_cost_usd          DECIMAL(14,2),
    refreshed_at            TIMESTAMP_NTZ   NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT pk_agg_training PRIMARY KEY (date_key, department_key, role_key, skill_domain_code)
)
COMMENT = 'Training compliance summary — mandatory completion rates and L&D ROI metrics.';


-- ============================================================
-- 4. ROW-LEVEL SECURITY (RLS) — Snowflake Dynamic Data Masking
-- ============================================================

USE SCHEMA GOLD;

-- Role definitions (map to your Snowflake roles)
-- ROLE: PP_EXEC         — CHRO, CEO, CFO — full access
-- ROLE: PP_HR_DIRECTOR  — HR Directors — full access minus global comp
-- ROLE: PP_HRBP         — HR Business Partners — own BU only
-- ROLE: PP_TA           — Talent Acquisition — recruitment data only
-- ROLE: PP_ANALYST      — HR Analysts — no PII, no salary exact values
-- ROLE: PP_COMP_ADMIN   — Total Rewards — full compensation access
-- ROLE: PP_COMPLIANCE   — Legal/Compliance — full access for compliance fields

-- PII Masking Policy: gender_code
CREATE OR REPLACE MASKING POLICY mask_gender_code
    AS (val VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN CURRENT_ROLE() IN ('PP_EXEC','PP_HR_DIRECTOR','PP_COMP_ADMIN','PP_COMPLIANCE') THEN val
        ELSE '***'
    END
COMMENT = 'Mask gender code for non-privileged roles';

-- PII Masking Policy: ethnicity_code
CREATE OR REPLACE MASKING POLICY mask_ethnicity_code
    AS (val VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN CURRENT_ROLE() IN ('PP_EXEC','PP_HR_DIRECTOR','PP_COMP_ADMIN','PP_COMPLIANCE') THEN val
        ELSE '***'
    END
COMMENT = 'Mask ethnicity for non-privileged roles (EEOC compliance)';

-- PII Masking Policy: birth_date
CREATE OR REPLACE MASKING POLICY mask_birth_date
    AS (val DATE) RETURNS DATE ->
    CASE
        WHEN CURRENT_ROLE() IN ('PP_EXEC','PP_HR_DIRECTOR','PP_COMPLIANCE') THEN val
        ELSE NULL
    END
COMMENT = 'Null out birth date for analyst-level roles';

-- Salary Masking: exact salary visible only to comp team and executives
CREATE OR REPLACE MASKING POLICY mask_salary_amount
    AS (val DECIMAL) RETURNS DECIMAL ->
    CASE
        WHEN CURRENT_ROLE() IN ('PP_EXEC','PP_COMP_ADMIN','PP_HR_DIRECTOR') THEN val
        WHEN CURRENT_ROLE() IN ('PP_HRBP','PP_ANALYST') THEN ROUND(val / 10000) * 10000  -- Band to nearest $10K
        ELSE NULL
    END
COMMENT = 'Salary rounded to nearest $10K for HRBP/analyst; exact for exec/comp admin';

-- Apply masking policies to DIM_EMPLOYEE
ALTER TABLE DIM_EMPLOYEE MODIFY COLUMN gender_code
    SET MASKING POLICY mask_gender_code;

ALTER TABLE DIM_EMPLOYEE MODIFY COLUMN ethnicity_code
    SET MASKING POLICY mask_ethnicity_code;

ALTER TABLE DIM_EMPLOYEE MODIFY COLUMN birth_date
    SET MASKING POLICY mask_birth_date;

-- Apply salary masking to FACT_COMPENSATION
ALTER TABLE FACT_COMPENSATION MODIFY COLUMN base_salary_new_usd
    SET MASKING POLICY mask_salary_amount;

ALTER TABLE FACT_COMPENSATION MODIFY COLUMN total_target_comp_usd
    SET MASKING POLICY mask_salary_amount;

-- Row-Level Security: HRBP can only see their assigned Business Unit
-- Implemented via Snowflake Row Access Policy
CREATE OR REPLACE ROW ACCESS POLICY rap_hrbp_department_scope
    AS (department_key INT) RETURNS BOOLEAN ->
    CASE
        WHEN CURRENT_ROLE() IN ('PP_EXEC','PP_HR_DIRECTOR','PP_COMP_ADMIN','PP_COMPLIANCE') THEN TRUE
        WHEN CURRENT_ROLE() = 'PP_HRBP' THEN
            department_key IN (
                SELECT d.department_key
                FROM DIM_DEPARTMENT d
                JOIN GOLD.HRBP_ASSIGNMENT h ON d.hierarchy_path LIKE h.business_unit_path || '%'
                WHERE h.hrbp_employee_id = CURRENT_USER()
            )
        ELSE FALSE
    END
COMMENT = 'HRBPs see only their assigned business unit and sub-departments';

ALTER TABLE FACT_EMPLOYEE_SNAPSHOT ADD ROW ACCESS POLICY rap_hrbp_department_scope ON (department_key);
ALTER TABLE FACT_PERFORMANCE        ADD ROW ACCESS POLICY rap_hrbp_department_scope ON (department_key);
ALTER TABLE FACT_COMPENSATION       ADD ROW ACCESS POLICY rap_hrbp_department_scope ON (department_key);
ALTER TABLE FACT_ATTENDANCE         ADD ROW ACCESS POLICY rap_hrbp_department_scope ON (department_key);


-- ============================================================
-- 5. SNOWFLAKE WAREHOUSE CONFIGURATION
-- ============================================================

-- Dedicated compute warehouse for Power BI (auto-suspend after 5 min)
CREATE OR REPLACE WAREHOUSE PEOPLEPULSE_BI_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    MAX_CLUSTER_COUNT = 3
    MIN_CLUSTER_COUNT = 1
    SCALING_POLICY = 'ECONOMY'
    COMMENT = 'Power BI dedicated warehouse — auto-scales under load';

-- Dedicated warehouse for ETL/dbt (larger, separate from BI)
CREATE OR REPLACE WAREHOUSE PEOPLEPULSE_ETL_WH
    WAREHOUSE_SIZE = 'LARGE'
    AUTO_SUSPEND = 120
    AUTO_RESUME = TRUE
    MAX_CLUSTER_COUNT = 2
    COMMENT = 'dbt transformation and Airflow pipeline warehouse';

-- ML batch inference warehouse
CREATE OR REPLACE WAREHOUSE PEOPLEPULSE_ML_WH
    WAREHOUSE_SIZE = 'XLARGE'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    MAX_CLUSTER_COUNT = 1
    COMMENT = 'ML model batch inference — used for weekly flight risk scoring';


-- ============================================================
-- 6. USEFUL ANALYTICAL VIEWS (dbt-generated equivalents in pure SQL)
-- ============================================================

USE SCHEMA GOLD;

-- View: Current active employees with full dimensional context
CREATE OR REPLACE VIEW V_CURRENT_EMPLOYEES AS
    SELECT
        fes.employee_snapshot_key,
        fes.employee_id,
        de.full_name,
        de.email_work,
        de.hire_date,
        fes.employment_type_code,
        fes.tenure_months,
        fes.tenure_band_code,
        fes.fte_value,
        dd.department_name,
        dd.division_name,
        dd.function_name,
        dd.hierarchy_path,
        dl.city_name,
        dl.country_name,
        dl.region_code,
        dr.job_title,
        dr.job_family_code,
        dr.job_level_code,
        dr.career_track_code,
        dm.full_name                    AS manager_name,
        dm.management_level_code,
        fes.compa_ratio,
        fes.performance_rating_code,
        fes.flight_risk_score,
        fes.engagement_score,
        d.year_num                      AS snapshot_year,
        d.month_num                     AS snapshot_month,
        d.fiscal_year,
        d.fiscal_quarter_label
    FROM FACT_EMPLOYEE_SNAPSHOT fes
    JOIN DIM_EMPLOYEE     de  ON fes.employee_key   = de.employee_key  AND de.is_current_flag = TRUE
    JOIN DIM_DATE         d   ON fes.date_key        = d.date_key
    JOIN DIM_DEPARTMENT   dd  ON fes.department_key  = dd.department_key
    JOIN DIM_LOCATION     dl  ON fes.location_key    = dl.location_key
    JOIN DIM_ROLE         dr  ON fes.role_key        = dr.role_key     AND dr.is_current_flag = TRUE
    LEFT JOIN DIM_MANAGER dm  ON fes.manager_key     = dm.manager_key  AND dm.is_current_flag = TRUE
    WHERE fes.is_active_flag = TRUE
      AND d.is_month_end_flag = TRUE
COMMENT = 'Active employees with full dimensional context — use for most HRBP and executive dashboards';


-- View: Attrition events with cohort context
CREATE OR REPLACE VIEW V_ATTRITION_EVENTS AS
    SELECT
        fes.employee_snapshot_key,
        fes.employee_id,
        de.full_name,
        de.hire_date,
        d.full_date                     AS exit_date,
        fes.voluntary_exit_flag,
        fes.is_regrettable_exit_flag,
        fes.exit_reason_code,
        fes.tenure_months               AS tenure_at_exit,
        fes.tenure_band_code,
        dd.department_name,
        dd.division_name,
        dl.region_code,
        dr.job_family_code,
        dr.job_level_code,
        fes.compa_ratio                 AS compa_ratio_at_exit,
        fes.performance_rating_code     AS last_perf_rating,
        fes.flight_risk_score           AS flight_risk_at_exit,
        fes.engagement_score            AS last_engagement_score,
        d.year_num,
        d.quarter_label,
        d.fiscal_year,
        d.fiscal_quarter_label
    FROM FACT_EMPLOYEE_SNAPSHOT fes
    JOIN DIM_EMPLOYEE     de  ON fes.employee_key   = de.employee_key
    JOIN DIM_DATE         d   ON fes.date_key        = d.date_key
    JOIN DIM_DEPARTMENT   dd  ON fes.department_key  = dd.department_key
    JOIN DIM_LOCATION     dl  ON fes.location_key    = dl.location_key
    JOIN DIM_ROLE         dr  ON fes.role_key        = dr.role_key
    WHERE fes.voluntary_exit_flag = TRUE
       OR fes.involuntary_exit_flag = TRUE
COMMENT = 'All attrition events with full context — source for cohort analysis and ML flight risk validation';

-- ============================================================
-- END OF DDL SCRIPT
-- PeoplePulse AI | Version 1.0 | Data Architecture Team
-- ============================================================
