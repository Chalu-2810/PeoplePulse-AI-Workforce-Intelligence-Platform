"""
PeoplePulse AI — Page 9: Employee Search
===========================================
Individual employee profile lookup — the "single pane of glass" for HRBPs.
"""

import streamlit as st
import pandas as pd
import numpy as np
import plotly.graph_objects as go

from utils.helpers import require_login, load_hr_data, load_risk_predictions, filter_by_role, render_header, BRAND_COLORS, to_pdf_bytes
from utils.nav import render_sidebar, apply_dark_mode

st.set_page_config(page_title="Employee Search | PeoplePulse AI", page_icon="🔍", layout="wide")

user = require_login()
render_sidebar(user, active_page="employee_search")
apply_dark_mode()

render_header("Employee Search", "Individual employee profile — single pane of glass for 1:1 prep", user)

df = load_hr_data()
df = filter_by_role(df, user)
risk_df = load_risk_predictions()

# ── Search / Advanced Filters ───────────────────────────────────────
st.markdown("##### 🔍 Search & Filter")
c1, c2, c3, c4 = st.columns(4)

with c1:
    search_name = st.text_input("Search by Name", placeholder="e.g. Charles Barnett")
with c2:
    dept_f = st.multiselect("Department", sorted(df["Department"].unique()))
with c3:
    level_f = st.multiselect("Job Level", sorted(df["Job_Level"].unique()))
with c4:
    risk_f = st.multiselect("Attrition Status", ["Yes","No"])

c5, c6, c7 = st.columns(3)
with c5:
    eng_range = st.slider("Engagement Score Range", 0, 100, (0,100))
with c6:
    salary_range = st.slider("Salary Range ($)", int(df["Salary"].min()), int(df["Salary"].max()),
                              (int(df["Salary"].min()), int(df["Salary"].max())))
with c7:
    tenure_range = st.slider("Tenure (Years)", 0.0, float(df["Years_At_Company"].max()), (0.0, float(df["Years_At_Company"].max())))

filtered = df.copy()
if search_name:
    filtered = filtered[filtered["Employee_Name"].str.contains(search_name, case=False, na=False)]
if dept_f:
    filtered = filtered[filtered["Department"].isin(dept_f)]
if level_f:
    filtered = filtered[filtered["Job_Level"].isin(level_f)]
if risk_f:
    filtered = filtered[filtered["Attrition"].isin(risk_f)]
filtered = filtered[
    (filtered["Engagement_Score"]>=eng_range[0]) & (filtered["Engagement_Score"]<=eng_range[1]) &
    (filtered["Salary"]>=salary_range[0]) & (filtered["Salary"]<=salary_range[1]) &
    (filtered["Years_At_Company"]>=tenure_range[0]) & (filtered["Years_At_Company"]<=tenure_range[1])
]

st.caption(f"{len(filtered):,} employees match the current filters")

st.dataframe(
    filtered[["Employee_ID","Employee_Name","Department","Job_Role","Job_Level","Manager_ID",
              "Location","Salary","Engagement_Score","Performance_Rating","Attrition"]].head(200),
    use_container_width=True, hide_index=True
)

st.markdown("---")

# ── Individual profile ──────────────────────────────────────────────
st.markdown("##### 👤 Individual Employee Profile")
emp_options = filtered["Employee_ID"] + " — " + filtered["Employee_Name"]
selected = st.selectbox("Select an employee for full profile", emp_options.tolist() if len(emp_options) else ["No results"])

if selected != "No results" and len(filtered):
    emp_id = selected.split(" — ")[0]
    emp = filtered[filtered["Employee_ID"]==emp_id].iloc[0]

    with st.container(border=True):
        c1, c2, c3 = st.columns([1,1,1])
        with c1:
            st.markdown(f"### {emp['Employee_Name']}")
            st.markdown(f"**{emp['Job_Role']}** ({emp['Job_Level']})")
            st.caption(f"{emp['Department']} · {emp['Location']} · {emp['Work_Mode']}")
        with c2:
            st.metric("Tenure", f"{emp['Years_At_Company']:.1f} yrs")
            st.metric("Manager", emp['Manager_ID'])
        with c3:
            st.metric("Salary", f"${emp['Salary']:,.0f}")
            st.metric("Bonus", f"${emp['Bonus']:,.0f}")

    # Bullet charts vs department avg
    st.markdown("###### Individual vs Department Average")
    dept_avg = df[df["Department"]==emp["Department"]]

    bullet_metrics = [
        ("Engagement Score", emp["Engagement_Score"], dept_avg["Engagement_Score"].mean(), 100),
        ("Satisfaction Score", emp["Satisfaction_Score"], dept_avg["Satisfaction_Score"].mean(), 100),
        ("Attendance %", emp["Attendance_Pct"], dept_avg["Attendance_Pct"].mean(), 100),
        ("Performance Rating", emp["Performance_Rating"], dept_avg["Performance_Rating"].mean(), 5),
        ("Training Hours", emp["Training_Hours"], dept_avg["Training_Hours"].mean(), 120),
        ("Compa-Ratio", emp["Compa_Ratio"], dept_avg["Compa_Ratio"].mean(), 1.5),
    ]

    cols = st.columns(3)
    for i, (label, val, avg, maxv) in enumerate(bullet_metrics):
        with cols[i%3]:
            fig = go.Figure(go.Indicator(
                mode="gauge+number+delta",
                value=val,
                delta={'reference': avg, 'relative': False},
                gauge={'axis':{'range':[0,maxv]},
                       'bar':{'color':BRAND_COLORS["primary"]},
                       'threshold':{'line':{'color':BRAND_COLORS["danger"],'width':3},'value':avg}},
                title={'text':label, 'font':{'size':13}}
            ))
            fig.update_layout(height=180, margin=dict(l=10,r=10,t=40,b=10))
            st.plotly_chart(fig, use_container_width=True)

    # Flight risk + drivers
    st.markdown("###### Flight Risk Assessment")
    if not risk_df.empty:
        risk_row = risk_df[risk_df["Employee_ID"]==emp_id]
        if len(risk_row):
            risk_row = risk_row.iloc[0]
            c1, c2 = st.columns([1,2])
            with c1:
                fig = go.Figure(go.Indicator(
                    mode="gauge+number",
                    value=risk_row["Risk_Score"],
                    gauge={'axis':{'range':[0,100]},
                           'bar':{'color': BRAND_COLORS["danger"] if risk_row["Risk_Score"]>=70 else BRAND_COLORS["warning"] if risk_row["Risk_Score"]>=45 else BRAND_COLORS["secondary"]},
                           'steps':[{'range':[0,45],'color':BRAND_COLORS["secondary_light"]},
                                    {'range':[45,70],'color':BRAND_COLORS["warning_light"]},
                                    {'range':[70,100],'color':BRAND_COLORS["danger_light"]}]},
                    title={'text':f"Risk Tier: {risk_row['Risk_Tier']}"}
                ))
                fig.update_layout(height=220, margin=dict(l=10,r=10,t=40,b=10))
                st.plotly_chart(fig, use_container_width=True)
            with c2:
                st.markdown("**Top 3 Risk Drivers:**")
                drivers = str(risk_row.get("Top_3_Drivers","")).split(" | ")
                for d in drivers:
                    st.markdown(f"- {d}")
                st.markdown("**Recommended Action:**")
                st.info(risk_row.get("Recommended_Action","—"))
        else:
            st.info("Risk score not available for this employee.")
    else:
        st.info("Risk prediction data not loaded.")

    # Promotion history
    st.markdown("###### Career Snapshot")
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Promotions", emp["Promotions"])
    c2.metric("Promotion Gap", f"{emp['Promotion_Gap']:.1f} yrs")
    c3.metric("Leave Count", emp["Leave_Count"])
    c4.metric("Recruitment Source", emp["Recruitment_Source"])

    # Export individual profile
    profile_kpis = {
        "Name": emp["Employee_Name"], "Department": emp["Department"],
        "Role": emp["Job_Role"], "Level": emp["Job_Level"],
        "Tenure (yrs)": f"{emp['Years_At_Company']:.1f}",
        "Salary": f"${emp['Salary']:,.0f}",
        "Engagement": f"{emp['Engagement_Score']:.1f}",
        "Performance Rating": emp["Performance_Rating"],
        "Promotion Gap": f"{emp['Promotion_Gap']:.1f} yrs",
    }
    pdf_bytes = to_pdf_bytes(f"Employee Profile — {emp['Employee_Name']}", profile_kpis)
    st.download_button("📄 Export Profile (PDF)", data=pdf_bytes,
                        file_name=f"PeoplePulse_Profile_{emp_id}.pdf", mime="application/pdf")
