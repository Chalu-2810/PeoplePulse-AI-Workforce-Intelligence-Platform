"""
PeoplePulse AI — Page 5: Recruitment Analytics
=================================================
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

from utils.helpers import require_login, load_hr_data, filter_by_role, render_header, BRAND_COLORS
from utils.nav import render_sidebar, apply_dark_mode

st.set_page_config(page_title="Recruitment Analytics | PeoplePulse AI", page_icon="🎯", layout="wide")

user = require_login()
render_sidebar(user, active_page="recruitment")
apply_dark_mode()

render_header("Recruitment Analytics", "Talent acquisition source quality, internal mobility, and pipeline health", user)

df = load_hr_data()
df = filter_by_role(df, user)

# ── KPIs ─────────────────────────────────────────────────────────
internal_rate = (df["Recruitment_Source"]=="Internal Transfer").mean()*100
avg_perf_overall = df["Performance_Rating"].mean()

src_quality = df.groupby("Recruitment_Source").agg(
    Count=("Employee_ID","count"),
    RetentionRate=("Attrition", lambda x: (x=="No").mean()*100),
    AvgPerf=("Performance_Rating","mean"),
    AvgEngagement=("Engagement_Score","mean"),
    AvgSalary=("Salary","mean")
).reset_index()
src_quality["QualityScore"] = (
    (src_quality["AvgPerf"]/5*35) + (src_quality["RetentionRate"]/100*35) + (src_quality["AvgEngagement"]/100*30)
)
top_source = src_quality.sort_values("QualityScore", ascending=False).iloc[0]

k1,k2,k3,k4 = st.columns(4)
k1.metric("Internal Hire Rate", f"{internal_rate:.1f}%", help="Benchmark: 30-40% is healthy")
k2.metric("Top Quality Source", top_source["Recruitment_Source"], f"Score: {top_source['QualityScore']:.1f}")
k3.metric("Avg Performance (All Hires)", f"{avg_perf_overall:.2f}/5")
k4.metric("Recruitment Channels", f"{df['Recruitment_Source'].nunique()}")

st.markdown("---")

# ── Source quality quadrant + Source mix ────────────────────────────
c1, c2 = st.columns(2)

with c1:
    st.markdown("##### Source Quality Quadrant")
    st.caption("Avg Salary (proxy for cost) vs Quality-of-Hire Score, bubble size = hire volume")
    fig = px.scatter(src_quality, x="AvgSalary", y="QualityScore", size="Count",
                      text="Recruitment_Source", color="QualityScore",
                      color_continuous_scale="RdYlGn", size_max=50)
    fig.update_traces(textposition="top center")
    median_quality = src_quality["QualityScore"].median()
    median_salary = src_quality["AvgSalary"].median()
    fig.add_hline(y=median_quality, line_dash="dash", line_color="gray")
    fig.add_vline(x=median_salary, line_dash="dash", line_color="gray")
    fig.update_layout(height=420, margin=dict(l=10,r=10,t=10,b=10),
                       xaxis_title="Avg Salary of Hires ($)", yaxis_title="Quality of Hire Score",
                       coloraxis_showscale=False)
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Source Mix with Retention Rate")
    fig = make_subplots = px.bar(
        src_quality.sort_values("Count", ascending=True),
        x="Count", y="Recruitment_Source", orientation="h",
        color="RetentionRate", color_continuous_scale="RdYlGn",
        text=src_quality.sort_values("Count", ascending=True)["RetentionRate"].round(1),
        labels={"color":"Retention %"}
    )
    fig.update_traces(texttemplate="Retention: %{text}%", textposition="inside")
    fig.update_layout(height=420, margin=dict(l=10,r=10,t=10,b=10), coloraxis_colorbar_title="Retention %")
    st.plotly_chart(fig, use_container_width=True)

st.markdown("---")

# ── Internal vs External + Candidate quality by dept ────────────────
c1, c2 = st.columns(2)

with c1:
    st.markdown("##### Internal vs External Hire — Performance & Retention")
    df["IsInternal"] = (df["Recruitment_Source"]=="Internal Transfer")
    comparison = pd.DataFrame({
        "Metric": ["Avg Performance Rating", "Retention Rate %"],
        "Internal": [
            df[df["IsInternal"]]["Performance_Rating"].mean(),
            (df[df["IsInternal"]]["Attrition"]=="No").mean()*100
        ],
        "External": [
            df[~df["IsInternal"]]["Performance_Rating"].mean(),
            (df[~df["IsInternal"]]["Attrition"]=="No").mean()*100
        ]
    })
    comparison_melt = comparison.melt(id_vars="Metric", var_name="Type", value_name="Value")
    fig = px.bar(comparison_melt, x="Metric", y="Value", color="Type", barmode="group",
                  color_discrete_map={"Internal":BRAND_COLORS["secondary"], "External":BRAND_COLORS["primary"]},
                  text=comparison_melt["Value"].round(1))
    fig.update_layout(height=380, margin=dict(l=10,r=10,t=10,b=10))
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Recruitment Source by Department (Top 5 Depts)")
    top_depts = df["Department"].value_counts().head(5).index.tolist()
    src_by_dept = df[df["Department"].isin(top_depts)].groupby(["Department","Recruitment_Source"]).size().reset_index(name="Count")
    fig = px.bar(src_by_dept, x="Department", y="Count", color="Recruitment_Source", barmode="stack")
    fig.update_layout(height=380, margin=dict(l=10,r=10,t=10,b=10), xaxis_tickangle=-30,
                       legend=dict(font=dict(size=9)))
    st.plotly_chart(fig, use_container_width=True)

st.markdown("---")
st.markdown("##### Full Source Quality Table")
st.dataframe(
    src_quality.sort_values("QualityScore", ascending=False).round(2),
    use_container_width=True, hide_index=True,
    column_config={
        "QualityScore": st.column_config.ProgressColumn("Quality Score", min_value=0, max_value=100, format="%.1f"),
        "RetentionRate": st.column_config.NumberColumn("Retention %", format="%.1f%%"),
        "AvgSalary": st.column_config.NumberColumn("Avg Salary", format="$%d"),
    }
)
