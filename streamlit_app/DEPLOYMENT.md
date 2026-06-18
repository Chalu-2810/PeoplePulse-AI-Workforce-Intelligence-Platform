# PeoplePulse AI — Streamlit SaaS Platform
## Phase 9 | Senior Full-Stack Data Product Engineer Build
### Production-Ready Multi-Page Application

---

## WHAT WAS BUILT

A complete 12-page Streamlit SaaS application implementing every requirement:

| Requirement | Implementation |
|---|---|
| **Authentication** | Email/password login (`Home.py`) with SHA-256 hashed credentials, session-state persistence |
| **Role-Based Access** | 5 roles (CEO/CHRO, HR Director, HRBP, Total Rewards, Admin) — sidebar dynamically renders only accessible pages |
| **Dashboard Navigation** | `st.page_link`-based sidebar nav, active-page highlighting, persists across all pages |
| **Predictive Analytics** | Page 8 surfaces Phase 8 ML model output — risk tiers, SHAP drivers, what-if engagement slider |
| **AI Insights** | Page 10 — natural-language narrative generation, key influencers, decomposition explorer |
| **Employee Search** | Page 9 — searchable individual profile with peer benchmarks, flight risk gauge, recommended actions |
| **Export PDF** | `to_pdf_bytes()` via ReportLab — KPI summary + detail table, used on Overview, Attrition, Employee Search |
| **Export Excel** | `to_excel_bytes()` via openpyxl — used on every analytical page |
| **Admin Panel** | Page 11 (Admin/CEO only) — user directory, data refresh status, system health |
| **Dark Mode** | Sidebar toggle injects CSS overrides via `apply_dark_mode()` |
| **Responsive Design** | `layout="wide"`, column-based grids that reflow on narrower viewports |
| **Advanced Filters** | Expandable filter panels (Department/Location/Level/Work Mode) on every page |
| **Deployment Architecture** | Below |

---

## APPLICATION STRUCTURE

```
streamlit_app/
├── Home.py                          # Login / entry point
├── .streamlit/
│   └── config.toml                  # Theme (PeoplePulse Blue branding)
├── data/
│   ├── PeoplePulse_HR_Dataset.csv
│   └── PeoplePulse_Attrition_Predictions.csv
├── utils/
│   ├── __init__.py
│   ├── helpers.py                   # Auth, RBAC, data loading, export, theming
│   └── nav.py                       # Shared sidebar navigation + dark mode
└── pages/
    ├── 1_Executive_Overview.py       # KPI strip, org health gauge, donut/treemap/funnel
    ├── 2_Workforce_Analytics.py      # Org pyramid, span of control, geo, age×level heatmap
    ├── 3_Attrition_Intelligence.py   # Survival curve, 9-box, driver decomposition
    ├── 4_Compensation_Analytics.py   # Salary box plots, pay equity heatmap, compa-ratio
    ├── 5_Recruitment_Analytics.py    # Source quality quadrant, internal vs external
    ├── 6_Performance_Analytics.py    # Distribution vs target, perf-comp correlation
    ├── 7_Diversity_Analytics.py      # Representation pipeline, pay equity index
    ├── 8_Predictive_Analytics.py     # ML risk tiers, SHAP, what-if scenario slider
    ├── 9_Employee_Search.py          # Individual profile, peer comparison, PDF export
    ├── 10_AI_Insights.py             # Narrative generation, key influencers
    └── 11_Admin_Panel.py             # User mgmt, system health (Admin/CEO only)
```

---

## ROLE-BASED ACCESS MATRIX (as implemented)

| Role | Pages Accessible | Row-Level Filter |
|---|---|---|
| **CEO/CHRO** | All 11 pages | None — full company view |
| **HR Director** | All except Admin | None — full company view |
| **HRBP** | Overview, Attrition, Performance, Predictive, Employee Search, AI Insights | `Department == assigned_dept` |
| **Total Rewards** | Overview, Compensation, Diversity, AI Insights | None |
| **Admin** | All 11 pages | None |

Implemented via `ROLE_PAGE_ACCESS` dict in `utils/helpers.py` and `filter_by_role()` applied to every page's dataframe load.

---

## DEMO CREDENTIALS

| Role | Email | Password |
|---|---|---|
| CEO/CHRO | `ceo@peoplepulse.ai` | `admin123` |
| HR Director | `hrdirector@peoplepulse.ai` | `hrdir123` |
| HRBP (Customer Success) | `hrbp.cs@peoplepulse.ai` | `hrbp123` |
| HRBP (Engineering) | `hrbp.eng@peoplepulse.ai` | `hrbp123` |
| Total Rewards | `totalrewards@peoplepulse.ai` | `comp123` |
| Admin | `admin@peoplepulse.ai` | `super123` |

---

## RUNNING LOCALLY

```bash
cd streamlit_app
pip install streamlit pandas numpy plotly openpyxl reportlab
streamlit run Home.py
```

The app was tested and confirmed to launch successfully (HTTP 200) with no runtime errors across all 11 authenticated pages.

---

## DEPLOYMENT ARCHITECTURE

### Option A — Streamlit Community Cloud (fastest path to demo)
```
GitHub Repo (peoplepulse-streamlit)
        │
        ▼
Streamlit Community Cloud
  - Auto-deploys on push to main
  - Free tier: 1 GB RAM, sleeps after inactivity
  - Secrets management via st.secrets (for prod credentials)
  - Custom subdomain: peoplepulse.streamlit.app
```
**Best for:** Portfolio demos, proof-of-concept, recruiter-facing links.
**Limitation:** Not suitable for real PII — demo data only.

---

### Option B — Containerized Enterprise Deployment (production)
```
┌─────────────────────────────────────────────────────────────┐
│                     LOAD BALANCER (ALB/NGINX)                │
│              TLS termination · WAF · Rate limiting            │
└───────────────────────────┬───────────────────────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ Streamlit Pod 1│   │ Streamlit Pod 2│   │ Streamlit Pod N│
│  (ECS/K8s)     │   │  (ECS/K8s)     │   │  (ECS/K8s)     │
└───────┬────────┘   └───────┬────────┘   └───────┬────────┘
        │                     │                     │
        └─────────────────────┼─────────────────────┘
                               ▼
                ┌──────────────────────────────┐
                │   Shared Session Store         │
                │   (Redis — for multi-pod auth) │
                └──────────────┬─────────────────┘
                               ▼
                ┌──────────────────────────────┐
                │   Snowflake / PostgreSQL       │
                │   (replaces local CSV files)   │
                │   - hr.Employee                │
                │   - hr.FlightRiskScore          │
                │   - audit.EmployeeChangeLog     │
                └──────────────┬─────────────────┘
                               ▼
                ┌──────────────────────────────┐
                │   ML Inference Service (FastAPI)│
                │   Weekly batch + on-demand score│
                └──────────────────────────────────┘
```

**Dockerfile (production):**
```dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8501
HEALTHCHECK CMD curl --fail http://localhost:8501/_stcore/health
ENTRYPOINT ["streamlit", "run", "Home.py", \
            "--server.port=8501", "--server.address=0.0.0.0"]
```

**Key production changes from this build:**
1. `USER_DIRECTORY` dict → replaced with Auth0/Okta SAML SSO + a `users` table in Postgres
2. `load_hr_data()` CSV read → replaced with `hr.vw_EmployeeFull` query against Snowflake (Phase 4 schema)
3. `st.session_state` for auth → replaced with Redis-backed session store (multi-pod consistency)
4. Static `Attrition_Predictions.csv` → replaced with live calls to the ML Inference Service, refreshed weekly via Airflow
5. RLS via Python dict filtering → replaced with Snowflake Row Access Policies (Phase 2) — defense in depth, DB enforces it even if app layer has a bug

---

### CI/CD Pipeline
```yaml
# .github/workflows/deploy.yml
name: Deploy PeoplePulse Streamlit
on:
  push:
    branches: [main]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install -r requirements.txt
      - run: python -m pytest tests/
      - run: python -c "import ast; [ast.parse(open(f).read()) for f in __import__('glob').glob('**/*.py', recursive=True)]"
  build_and_push:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: docker/build-push-action@v5
        with:
          push: true
          tags: registry/peoplepulse-streamlit:${{ github.sha }}
  deploy:
    needs: build_and_push
    runs-on: ubuntu-latest
    steps:
      - run: kubectl set image deployment/peoplepulse-app app=registry/peoplepulse-streamlit:${{ github.sha }}
```

---

## SECURITY NOTES (production hardening checklist)

- [ ] Replace hardcoded `USER_DIRECTORY` with SSO (SAML 2.0 / OAuth)
- [ ] Move credentials to `st.secrets` / environment variables — never commit
- [ ] Enable `enableXsrfProtection = true` (already set)
- [ ] Apply Snowflake RLS (Phase 2 policies) as defense-in-depth beyond app-layer filtering
- [ ] Audit log every PDF/Excel export (who exported what, when) per `audit.EmployeeChangeLog`
- [ ] Rate-limit login attempts (currently unlimited — add Redis-based throttling)
- [ ] PII masking in Employee Search for non-Comp-Admin roles (salary banding per Phase 2 masking policy)

---

*Document: PeoplePulse AI Streamlit SaaS Platform v1.0*
*Phase 9 | Senior Full-Stack Data Product Engineer*
