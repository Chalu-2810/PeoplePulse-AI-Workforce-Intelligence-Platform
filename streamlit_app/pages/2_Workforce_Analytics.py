"""
PeoplePulse AI — Page 2: Workforce Analytics
===============================================
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go

from utils.helpers import require_login, load_hr_data, filter_by_role, render_header, BRAND_COLORS
from utils.nav import render_sidebar, apply_dark_mode

st.set_page_config(page_title="Workforce Analytics | PeoplePulse AI", page_icon="👥", layout="wide")

user = require_login()
render_sidebar(user, active_page="workforce")
apply_dark_mode()

render_header("Workforce Analytics", "Organizational structure, composition, and capacity", user)

df = load_hr_data()
df = filter_by_role(df, user)

# ── KPIs ─────────────────────────────────────────────────────────
total_fte = len(df)  # all full-time in this dataset
span_data = df.groupby("Manager_ID").size()
avg_span = span_data.mean()
ic_count = df["Job_Level"].isin(["L1","L2","L3","L4"]).sum()
mgr_count = df["Job_Level"].isin(["L5","L6"]).sum()
exec_count = df["Job_Level"].isin(["L7","L8"]).sum()
remote_pct = (df["Work_Mode"]=="Remote").mean()*100
avg_tenure = df["Years_At_Company"].mean()

k1,k2,k3,k4,k5,k6 = st.columns(6)
k1.metric("Total Headcount", f"{len(df):,}")
k2.metric("Avg Span of Control", f"{avg_span:.1f}")
k3.metric("IC : Mgr : Exec", f"{ic_count/len(df)*100:.0f}:{mgr_count/len(df)*100:.0f}:{exec_count/len(df)*100:.0f}")
k4.metric("Remote %", f"{remote_pct:.1f}%")
k5.metric("Avg Tenure", f"{avg_tenure:.1f} yrs")
k6.metric("Departments", f"{df['Department'].nunique()}")

st.markdown("---")

# ── Org Pyramid + Geographic distribution ─────────────────────────
c1, c2 = st.columns([1.3, 1])

with c1:
    st.markdown("##### Organizational Pyramid (Headcount by Level)")
    level_order = ["L8","L7","L6","L5","L4","L3","L2"]
    level_counts = df["Job_Level"].value_counts().reindex(level_order).fillna(0).reset_index()
    level_counts.columns = ["Level","Count"]
    level_names = {"L2":"Associate","L3":"Specialist","L4":"Senior Specialist",
                    "L5":"Staff/Principal","L6":"Director","L7":"VP","L8":"C-Suite"}
    level_counts["Label"] = level_counts["Level"].map(level_names)

    fig = go.Figure(go.Bar(
        y=level_counts["Label"], x=level_counts["Count"], orientation="h",
        marker_color=px.colors.sequential.Blues[2:9][::-1],
        text=level_counts["Count"], textposition="outside"
    ))
    fig.update_layout(height=420, margin=dict(l=10,r=10,t=10,b=10),
                       xaxis_title="Headcount", yaxis_title="")
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Headcount by Location")
    loc_counts = df["Location"].value_counts().reset_index()
    loc_counts.columns = ["Location","Count"]
    fig = px.bar(loc_counts.sort_values("Count"), x="Count", y="Location", orientation="h",
                  color="Count", color_continuous_scale="Blues")
    fig.update_layout(height=420, margin=dict(l=10,r=10,t=10,b=10), coloraxis_showscale=False)
    st.plotly_chart(fig, use_container_width=True)

st.markdown("---")

# ── Span of control + Work mode + Age x Level heatmap ──────────────
c1, c2, c3 = st.columns(3)

with c1:
    st.markdown("##### Span of Control Distribution")
    fig = px.histogram(span_data.reset_index(name="Reports"), x="Reports", nbins=20,
                        color_discrete_sequence=[BRAND_COLORS["primary"]])
    fig.add_vline(x=4, line_dash="dash", line_color=BRAND_COLORS["warning"], annotation_text="Under-span")
    fig.add_vline(x=12, line_dash="dash", line_color=BRAND_COLORS["danger"], annotation_text="Overloaded")
    fig.update_layout(height=320, margin=dict(l=10,r=10,t=10,b=10), xaxis_title="Direct Reports", yaxis_title="Managers")
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Work Mode by Department")
    wm = pd.crosstab(df["Department"], df["Work_Mode"], normalize="index")*100
    wm = wm.reset_index().melt(id_vars="Department", var_name="Work Mode", value_name="Pct")
    fig = px.bar(wm, x="Department", y="Pct", color="Work Mode", barmode="stack",
                  color_discrete_map={"On-site":BRAND_COLORS["secondary"],
                                       "Hybrid":BRAND_COLORS["warning"],
                                       "Remote":BRAND_COLORS["primary"]})
    fig.update_layout(height=320, margin=dict(l=10,r=10,t=10,b=10), xaxis_tickangle=-35, yaxis_title="%")
    st.plotly_chart(fig, use_container_width=True)

with c3:
    st.markdown("##### Age Band × Job Level Heatmap")
    age_bins = [0,25,35,45,55,65,100]
    age_labels = ["<25","25-34","35-44","45-54","55-64","65+"]
    df["AgeBand"] = pd.cut(df["Age"], bins=age_bins, labels=age_labels)
    heatmap_data = pd.crosstab(df["AgeBand"], df["Job_Level"])
    fig = px.imshow(heatmap_data, text_auto=True, color_continuous_scale="Blues", aspect="auto")
    fig.update_layout(height=320, margin=dict(l=10,r=10,t=10,b=10))
    st.plotly_chart(fig, use_container_width=True)

st.markdown("---")

# ── Tenure distribution ────────────────────────────────────────────
st.markdown("##### Tenure Distribution")
fig = px.histogram(df, x="Years_At_Company", nbins=40, color_discrete_sequence=[BRAND_COLORS["primary"]])
fig.add_vline(x=df["Years_At_Company"].median(), line_dash="dash", line_color=BRAND_COLORS["danger"],
               annotation_text=f"Median: {df['Years_At_Company'].median():.1f}yr")
fig.update_layout(height=280, margin=dict(l=10,r=10,t=10,b=10), xaxis_title="Years at Company", yaxis_title="Employees")
st.plotly_chart(fig, use_container_width=True)

with st.expander("📋 Department Detail Table"):
    summary = df.groupby("Department").agg(
        Headcount=("Employee_ID","count"),
        AvgTenure=("Years_At_Company","mean"),
        AvgSalary=("Salary","mean"),
        RemotePct=("Work_Mode", lambda x: (x=="Remote").mean()*100)
    ).round(1).reset_index()
    st.dataframe(summary, use_container_width=True, hide_index=True)
