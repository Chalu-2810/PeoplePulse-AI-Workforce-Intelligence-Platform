# 👥 PeoplePulse AI
### Enterprise Workforce Intelligence Platform — Production-Ready Package

A complete, runnable HR analytics platform: causally-modeled dataset → SQL
data warehouse → ML attrition prediction → Power BI architecture → deployed
Streamlit SaaS application. Clone, install, and run end-to-end.

---

## Quick Start (5 Minutes)

```bash
git clone https://github.com/yourname/peoplepulse-ai.git
cd PeoplePulseAI
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
cd streamlit_app && streamlit run Home.py
```
Open `http://localhost:8501` and log in with `ceo@peoplepulse.ai` / `admin123`.

For full setup including database and ML model training, see
**`docs/07_local_installation_guide.md`**.

---

## Folder Structure

```
PeoplePulseAI/
│
├── data/                              # Dataset + generator
│   ├── PeoplePulse_HR_Dataset.csv     # 10,000 employees x 24 columns
│   ├── generate_hr_dataset.py         # Causal dataset generator
│   └── dataset_profile.html           # Interactive data profiling report
│
├── sql/                               # Database schemas (3 engines) + queries
│   ├── postgresql_schema.sql          # PRIMARY schema (recommended)
│   ├── mysql_schema.sql               # MySQL 8.0+ variant
│   ├── mssql_schema.sql               # SQL Server pointer -> 03_sql_library.sql
│   ├── 01_ddl_and_rls.sql             # Original DDL + row-level security design
│   ├── 02_dbt_models.sql              # dbt staging/mart model stubs
│   ├── 03_sql_library.sql             # Full T-SQL library: tables, views, procs, 13 analytical queries
│   └── validation/
│       └── run_validation.sql         # 8 validation query sets
│
├── powerbi/
│   └── dax_measures_phase4.dax        # Original 80+ DAX measure library
│
├── notebooks/
│   └── 01_exploratory_analysis.ipynb  # Quick-start EDA notebook (tested, executes clean)
│
├── streamlit_app/                     # Self-contained 12-page SaaS application
│   ├── Home.py                        # Login entry point
│   ├── .streamlit/config.toml         # Branded theme config
│   ├── data/                          # Bundled data copy (self-contained deploy)
│   ├── utils/
│   │   ├── helpers.py                 # Auth, RBAC, data loading, export functions
│   │   └── nav.py                     # Sidebar navigation + dark mode
│   ├── pages/                         # 11 authenticated pages
│   ├── requirements.txt
│   └── DEPLOYMENT.md                  # App-specific deployment notes
│
├── docs/                              # All documentation, numbered in read order
│   ├── 01_product_architecture.md
│   ├── 02_data_model.md
│   ├── 03_dataset_design.md
│   ├── 04_kpi_framework.md
│   ├── 05_powerbi_architecture.md
│   ├── 06_advanced_dax.md
│   ├── 07_local_installation_guide.md
│   ├── 08_database_deployment_guide.md
│   ├── 09_ml_execution_guide.md
│   ├── 10_powerbi_deployment_guide.md
│   ├── 11_streamlit_deployment_guide.md
│   ├── 12_career_assets.md
│   └── 13_testing_and_validation.md
│
├── ml_models/                         # ML pipeline + persisted artifacts
│   ├── train_attrition_model.py       # Full pipeline: 4 models, SHAP, risk segmentation
│   ├── save_model.py                  # Persist production model to disk
│   ├── score_employees.py             # Fast inference-only scoring
│   ├── attrition_predictions.csv      # Full output (all 10,000 employees + SHAP drivers)
│   ├── active_employee_risk_list.csv  # Actionable subset (active employees only)
│   ├── feature_importance.csv
│   ├── model_comparison.csv
│   └── artifacts/                     # Serialized model/preprocessor (joblib)
│
├── assets/
│   └── shap_summary.png               # SHAP global feature importance plot
│
├── deployment/
│   └── docker/
│       ├── Dockerfile
│       └── docker-compose.yml         # App + Postgres + pgAdmin stack
│
├── scripts/
│   ├── load_data.py                   # Universal CSV-to-DB loader (Postgres/MySQL/MSSQL)
│   └── generate_password_hashes.py    # Demo user password hash generator
│
├── tests/                             # 77 pytest tests, all passing
│   ├── conftest.py
│   ├── test_data_quality.py           # 26 tests
│   ├── test_kpi_validation.py         # 17 tests
│   ├── test_model_validation.py       # 14 tests
│   └── test_dashboard_validation.py   # 20 tests
│
├── requirements.txt                   # Master dependency list, versioned
├── .env.example                       # Environment configuration template
├── .gitignore
└── README.md                          # This file
```

---

## What's Inside (By Phase)

| Phase | Deliverable | Location |
|---|---|---|
| 1 | Product Architecture | `docs/01_product_architecture.md` |
| 2 | Data Model (Star Schema, ERD, RLS) | `docs/02_data_model.md`, `sql/01_ddl_and_rls.sql` |
| 3 | Synthetic Dataset (causal model) | `data/` |
| 4 | SQL Engineering (130+ objects) | `sql/03_sql_library.sql` |
| 5 | KPI Framework (52 KPIs) | `docs/04_kpi_framework.md` |
| 6 | Power BI Architecture (15 pages) | `docs/05_powerbi_architecture.md` |
| 7 | Advanced DAX (130+ measures) | `docs/06_advanced_dax.md`, `powerbi/` |
| 8 | ML Attrition Prediction | `ml_models/` |
| 9 | Streamlit SaaS App | `streamlit_app/` |
| 10 | Career/Portfolio Assets | `docs/12_career_assets.md` |
| Final | This consolidated package | Everything above + `tests/`, `deployment/`, `scripts/` |

---

## Key Results

- **23.8%** baseline attrition rate, causally modeled (not random noise)
- **1.62x** precision lift over random selection at the top-risk decile (Logistic Regression, AUC 0.601)
- **3.4x** spread in actual attrition rate across ML risk tiers (16.1% Low → 54.4% Critical) — validated, not assumed
- **77/77** automated tests passing across data quality, KPIs, model calibration, and application security
- **12-page** Streamlit application with 5-role RBAC, tested end-to-end

---

## Demo Credentials (Streamlit App)

| Role | Email | Password |
|---|---|---|
| CEO/CHRO (full access) | `ceo@peoplepulse.ai` | `admin123` |
| HR Director | `hrdirector@peoplepulse.ai` | `hrdir123` |
| HRBP (Customer Success) | `hrbp.cs@peoplepulse.ai` | `hrbp123` |
| HRBP (Engineering) | `hrbp.eng@peoplepulse.ai` | `hrbp123` |
| Total Rewards | `totalrewards@peoplepulse.ai` | `comp123` |
| Admin | `admin@peoplepulse.ai` | `super123` |

---

## Execution Order (Clone to Full Deployment)

See **`docs/07_local_installation_guide.md`** for the detailed step-by-step
with expected outputs and troubleshooting. Summary sequence:

1. Clone repo → create venv → `pip install -r requirements.txt`
2. `cp .env.example .env`
3. *(Optional)* Deploy database — `docs/08_database_deployment_guide.md`
4. `python ml_models/train_attrition_model.py` — trains models, generates predictions
5. `python ml_models/save_model.py` — persists model artifacts
6. `pytest tests/ -v` — confirm 77/77 passing
7. *(Optional)* Build Power BI report — `docs/10_powerbi_deployment_guide.md`
8. `cd streamlit_app && streamlit run Home.py` — launch the application
9. Log in and explore; deploy to production via `docs/11_streamlit_deployment_guide.md`

---

## License
MIT. Dataset is fully synthetic — no real employee data.
