"""
PeoplePulse AI — Page 11: Admin Panel
========================================
User management, data refresh, system health (Admin/CEO only).
"""

import streamlit as st
import pandas as pd
from datetime import datetime

from utils.helpers import require_login, load_hr_data, USER_DIRECTORY, render_header, has_access
from utils.nav import render_sidebar, apply_dark_mode

st.set_page_config(page_title="Admin Panel | PeoplePulse AI", page_icon="⚙️", layout="wide")

user = require_login()

if not has_access(user, "admin"):
    st.error("🔒 Access Denied — this page is restricted to Admin and CEO/CHRO roles.")
    st.stop()

render_sidebar(user, active_page="admin")
apply_dark_mode()

render_header("Admin Panel", "User management, data pipeline status, and system configuration", user)

df = load_hr_data()

# ── System Health ────────────────────────────────────────────────
st.markdown("##### 🩺 System Health")
c1, c2, c3, c4 = st.columns(4)
c1.metric("Total Records", f"{len(df):,}")
c2.metric("Data Last Refreshed", "Jun 14, 2026 06:00 UTC")
c3.metric("ML Model Version", "v1.0 (LogReg)")
c4.metric("Active Sessions", "1 (you)")

st.success("✅ All systems operational. ETL pipeline: dbt Bronze → Silver → Gold completed without errors.")

st.markdown("---")

# ── User Management ──────────────────────────────────────────────
st.markdown("##### 👤 User Management")

user_table = pd.DataFrame([
    {"Email": email, "Name": u["name"], "Role": u["role"],
     "Department Scope": u["department"] or "All Departments"}
    for email, u in USER_DIRECTORY.items()
])
st.dataframe(user_table, use_container_width=True, hide_index=True)

with st.expander("➕ Add New User (Demo — not persisted)"):
    c1, c2, c3 = st.columns(3)
    with c1:
        new_email = st.text_input("Email")
        new_name = st.text_input("Full Name")
    with c2:
        new_role = st.selectbox("Role", ["CEO/CHRO","HR Director","HRBP","Total Rewards","Admin"])
    with c3:
        new_dept = st.selectbox("Department Scope", ["All Departments"] + sorted(df["Department"].unique().tolist()))

    if st.button("Create User"):
        st.success(f"✅ (Demo) User '{new_name}' would be created with role '{new_role}' "
                    f"scoped to '{new_dept}'. In production, this writes to the identity-service "
                    f"database (Phase 1 architecture) and triggers an Auth0 invitation email.")

st.markdown("---")

# ── Data Pipeline Configuration ──────────────────────────────────
st.markdown("##### 🔄 Data Pipeline Configuration")

c1, c2 = st.columns(2)

with c1:
    st.markdown("**Connected Data Sources**")
    sources = pd.DataFrame([
        {"Source": "Workday HRIS", "Status": "🟢 Connected", "Last Sync": "Jun 14, 2026 06:00"},
        {"Source": "Greenhouse ATS", "Status": "🟢 Connected", "Last Sync": "Jun 14, 2026 06:00"},
        {"Source": "ADP Payroll", "Status": "🟢 Connected", "Last Sync": "Jun 14, 2026 06:00"},
        {"Source": "Qualtrics Engagement Survey", "Status": "🟡 Sync Pending", "Last Sync": "Jun 10, 2026 06:00"},
        {"Source": "Cornerstone LMS", "Status": "🟢 Connected", "Last Sync": "Jun 14, 2026 06:00"},
    ])
    st.dataframe(sources, use_container_width=True, hide_index=True)

with c2:
    st.markdown("**ML Model Refresh Schedule**")
    models = pd.DataFrame([
        {"Model": "Flight Risk Predictor", "Version": "v1.0", "Last Trained": "Jun 13, 2026", "Schedule": "Weekly (Sundays 02:00 UTC)"},
        {"Model": "Quality of Hire", "Version": "—", "Last Trained": "Not yet deployed", "Schedule": "Monthly (Phase 3 roadmap)"},
        {"Model": "Pay Equity Anomaly Detector", "Version": "—", "Last Trained": "Not yet deployed", "Schedule": "Quarterly (Phase 3 roadmap)"},
    ])
    st.dataframe(models, use_container_width=True, hide_index=True)

if st.button("🔄 Trigger Manual Data Refresh (Demo)"):
    with st.spinner("Refreshing data pipeline..."):
        import time
        time.sleep(1.5)
    st.success(f"✅ Data refresh completed at {datetime.now().strftime('%H:%M:%S')} (demo — cache cleared)")
    st.cache_data.clear()

st.markdown("---")

# ── Audit Log ──────────────────────────────────────────────────────
st.markdown("##### 📜 Recent Audit Log (Sample)")
audit_log = pd.DataFrame([
    {"Timestamp": "2026-06-14 09:14:22", "User": "hrbp.cs@peoplepulse.ai", "Action": "Viewed Employee Profile", "Target": "EMP14821"},
    {"Timestamp": "2026-06-14 09:02:10", "User": "totalrewards@peoplepulse.ai", "Action": "Exported Compensation Detail (Excel)", "Target": "Department=All"},
    {"Timestamp": "2026-06-14 08:45:33", "User": "hrdirector@peoplepulse.ai", "Action": "Viewed High-Risk Employee List", "Target": "Page 8 Predictive"},
    {"Timestamp": "2026-06-13 17:30:01", "User": "admin@peoplepulse.ai", "Action": "ML Model Retrained", "Target": "Flight Risk v1.0"},
    {"Timestamp": "2026-06-13 06:00:00", "User": "system", "Action": "Scheduled ETL Refresh Completed", "Target": "dbt Gold layer"},
])
st.dataframe(audit_log, use_container_width=True, hide_index=True)

st.markdown("---")

# ── Role Permission Matrix ──────────────────────────────────────────
st.markdown("##### 🔐 Role-Based Access Control Matrix")
from utils.helpers import ROLE_PAGE_ACCESS, PAGE_LABELS

matrix_rows = []
for role, pages in ROLE_PAGE_ACCESS.items():
    row = {"Role": role}
    for page_key, label in PAGE_LABELS.items():
        row[label] = "✅" if page_key in pages else ""
    matrix_rows.append(row)

matrix_df = pd.DataFrame(matrix_rows).set_index("Role")
st.dataframe(matrix_df, use_container_width=True)
