"""
PeoplePulse AI — Page 1: Executive Overview
=============================================
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

from utils.helpers import (
    require_login, load_hr_data, filter_by_role, render_header,
    to_excel_bytes, to_pdf_bytes, BRAND_COLORS
)
from utils.nav import render_sidebar, apply_dark_mode

st.set_page_config(page_title="Executive Overview | PeoplePulse AI", page_icon="📊", layout="wide")

user = require_login()
render_sidebar(user, active_page="overview")
apply_dark_mode()

render_header("Executive Overview", "Workforce health at a glance — real-time KPIs across the organization", user)

df = load_hr_data()
df = filter_by_role(df, user)

# ── Global filters ──────────────────────────────────────────────
with st.expander("🔎 Filters", expanded=False):
    c1, c2, c3, c4 = st.columns(4)
    with c1:
        dept_filter = st.multiselect("Department", sorted(df["Department"].unique()))
    with c2:
        loc_filter = st.multiselect("Location", sorted(df["Location"].unique()))
    with c3:
        level_filter = st.multiselect("Job Level", sorted(df["Job_Level"].unique()))
    with c4:
        wm_filter = st.multiselect("Work Mode", sorted(df["Work_Mode"].unique()))

if dept_filter:
    df = df[df["Department"].isin(dept_filter)]
if loc_filter:
    df = df[df["Location"].isin(loc_filter)]
if level_filter:
    df = df[df["Job_Level"].isin(level_filter)]
if wm_filter:
    df = df[df["Work_Mode"].isin(wm_filter)]

if len(df) == 0:
    st.warning("No employees match the selected filters.")
    st.stop()

# ── KPI Strip ────────────────────────────────────────────────────
total_hc = len(df)
attrition_rate = (df["Attrition"] == "Yes").mean() * 100
avg_engagement = df["Engagement_Score"].mean()
avg_salary = df["Salary"].mean()
high_risk_count = (df["Engagement_Score"] < 40).sum()
regrettable_pct = ((df["Attrition"]=="Yes") & (df["Performance_Rating"]>=4)).mean() * 100

k1, k2, k3, k4, k5, k6 = st.columns(6)
k1.metric("Total Headcount", f"{total_hc:,}")
k2.metric("Attrition Rate", f"{attrition_rate:.1f}%",
          delta=f"{attrition_rate-18:.1f}pp vs 18% benchmark", delta_color="inverse")
k3.metric("Avg Engagement", f"{avg_engagement:.1f}/100")
k4.metric("Avg Salary", f"${avg_salary/1000:.0f}K")
k5.metric("High Flight Risk", f"{high_risk_count:,}")
k6.metric("Regrettable Attrition", f"{regrettable_pct:.1f}%")

st.markdown("---")

# ── Row 2: Dept headcount + attrition overlay | Org Health gauge ──
col_left, col_right = st.columns([1.6, 1])

with col_left:
    st.markdown("##### Headcount & Attrition Rate by Department")
    dept_summary = df.groupby("Department").agg(
        Headcount=("Employee_ID","count"),
        AttritionRate=("Attrition", lambda x: (x=="Yes").mean()*100)
    ).reset_index().sort_values("Headcount", ascending=True)

    fig = go.Figure()
    fig.add_trace(go.Bar(
        y=dept_summary["Department"], x=dept_summary["Headcount"],
        name="Headcount", orientation="h",
        marker_color=BRAND_COLORS["primary"], opacity=0.85
    ))
    fig.add_trace(go.Scatter(
        y=dept_summary["Department"], x=dept_summary["AttritionRate"],
        name="Attrition Rate %", mode="markers+lines",
        marker=dict(color=BRAND_COLORS["danger"], size=10),
        xaxis="x2"
    ))
    fig.update_layout(
        xaxis=dict(title="Headcount"),
        xaxis2=dict(title="Attrition Rate %", overlaying="x", side="top", range=[0,40]),
        height=420, margin=dict(l=10,r=10,t=40,b=10),
        legend=dict(orientation="h", yanchor="bottom", y=1.08)
    )
    st.plotly_chart(fig, use_container_width=True)

with col_right:
    st.markdown("##### Organizational Health Index")
    # Composite score
    att_score = max(0, (1 - min(attrition_rate/100, 0.5)/0.5)) * 30
    eng_score = (avg_engagement/100) * 30
    perf_score = ((df["Performance_Rating"]>=4).mean()) * 20
    gender_pay_gap = abs(
        (df[df.Gender=="Male"]["Salary"].mean() - df[df.Gender=="Female"]["Salary"].mean())
        / df[df.Gender=="Male"]["Salary"].mean()
    ) if (df.Gender=="Female").any() and (df.Gender=="Male").any() else 0
    equity_score = (1 - min(gender_pay_gap, 0.10)/0.10) * 20
    health_score = att_score + eng_score + perf_score + equity_score

    fig_gauge = go.Figure(go.Indicator(
        mode="gauge+number",
        value=health_score,
        domain={'x':[0,1],'y':[0,1]},
        gauge={
            'axis': {'range':[0,100]},
            'bar': {'color': BRAND_COLORS["primary"]},
            'steps': [
                {'range':[0,50], 'color': BRAND_COLORS["danger_light"]},
                {'range':[50,75], 'color': BRAND_COLORS["warning_light"]},
                {'range':[75,100], 'color': BRAND_COLORS["secondary_light"]},
            ],
        },
        number={'suffix':"/100", 'font':{'size':36}}
    ))
    fig_gauge.update_layout(height=260, margin=dict(l=10,r=10,t=20,b=10))
    st.plotly_chart(fig_gauge, use_container_width=True)

    st.caption(f"Attrition: {att_score:.1f}/30 · Engagement: {eng_score:.1f}/30 · "
               f"Performance: {perf_score:.1f}/20 · Equity: {equity_score:.1f}/20")

st.markdown("---")

# ── Row 3: Gender donut | Location treemap | Flight risk funnel ──
c1, c2, c3 = st.columns(3)

with c1:
    st.markdown("##### Gender Distribution")
    gender_counts = df["Gender"].value_counts().reset_index()
    gender_counts.columns = ["Gender","Count"]
    fig = px.pie(gender_counts, names="Gender", values="Count", hole=0.55,
                  color="Gender",
                  color_discrete_map={"Male":BRAND_COLORS["primary"],
                                       "Female":BRAND_COLORS["secondary"],
                                       "Non-binary":BRAND_COLORS["purple"]})
    fig.update_layout(height=300, margin=dict(l=10,r=10,t=10,b=10),
                       legend=dict(orientation="h", y=-0.1))
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Headcount by Location")
    loc_counts = df["Location"].value_counts().reset_index()
    loc_counts.columns = ["Location","Count"]
    fig = px.treemap(loc_counts, path=["Location"], values="Count",
                      color="Count", color_continuous_scale="Blues")
    fig.update_layout(height=300, margin=dict(l=10,r=10,t=10,b=10))
    st.plotly_chart(fig, use_container_width=True)

with c3:
    st.markdown("##### Engagement Tier Distribution")
    tier_order = ["High Risk","Medium Risk","Low Risk","Engaged"]
    tier_counts = df["Engagement_Tier"].value_counts().reindex(tier_order).fillna(0).reset_index()
    tier_counts.columns = ["Tier","Count"]
    colors_map = {"High Risk":BRAND_COLORS["danger"], "Medium Risk":BRAND_COLORS["warning"],
                   "Low Risk":BRAND_COLORS["primary"], "Engaged":BRAND_COLORS["secondary"]}
    fig = go.Figure(go.Funnel(
        y=tier_counts["Tier"], x=tier_counts["Count"],
        marker={"color":[colors_map[t] for t in tier_counts["Tier"]]}
    ))
    fig.update_layout(height=300, margin=dict(l=10,r=10,t=10,b=10))
    st.plotly_chart(fig, use_container_width=True)

st.markdown("---")

# ── Export options ──────────────────────────────────────────────
st.markdown("##### 📤 Export This View")
exp1, exp2, exp3 = st.columns([1,1,4])

with exp1:
    excel_data = to_excel_bytes(dept_summary, sheet_name="Department Summary")
    st.download_button("📊 Export Excel", data=excel_data,
                        file_name="PeoplePulse_Executive_Overview.xlsx",
                        mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                        use_container_width=True)

with exp2:
    kpis = {
        "Total Headcount": f"{total_hc:,}",
        "Attrition Rate": f"{attrition_rate:.1f}%",
        "Avg Engagement Score": f"{avg_engagement:.1f}",
        "Avg Salary": f"${avg_salary:,.0f}",
        "High Flight Risk Count": f"{high_risk_count:,}",
        "Regrettable Attrition %": f"{regrettable_pct:.1f}%",
        "Workforce Health Score": f"{health_score:.1f}/100",
    }
    pdf_data = to_pdf_bytes("PeoplePulse Executive Overview", kpis, dept_summary)
    st.download_button("📄 Export PDF", data=pdf_data,
                        file_name="PeoplePulse_Executive_Overview.pdf",
                        mime="application/pdf", use_container_width=True)
