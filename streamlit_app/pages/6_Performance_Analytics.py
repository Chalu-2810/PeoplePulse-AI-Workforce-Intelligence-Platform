"""
PeoplePulse AI — Page 6: Performance Analytics
=================================================
"""

import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go

from utils.helpers import require_login, load_hr_data, filter_by_role, render_header, BRAND_COLORS
from utils.nav import render_sidebar, apply_dark_mode

st.set_page_config(page_title="Performance Analytics | PeoplePulse AI", page_icon="⭐", layout="wide")

user = require_login()
render_sidebar(user, active_page="performance")
apply_dark_mode()

render_header("Performance Analytics", "Performance management process integrity and pay-for-performance alignment", user)

df = load_hr_data()
df = filter_by_role(df, user)

# ── KPIs ─────────────────────────────────────────────────────────
avg_perf = df["Performance_Rating"].mean()
high_perf_pct = (df["Performance_Rating"]>=4).mean()*100
overall_retention = (df["Attrition"]=="No").mean()*100
hipo_retention = (df[df["Performance_Rating"]>=4]["Attrition"]=="No").mean()*100
pip_count = (df["Performance_Rating"]==1).sum()

k1,k2,k3,k4,k5 = st.columns(5)
k1.metric("Avg Performance Rating", f"{avg_perf:.2f}/5")
k2.metric("High Performers", f"{high_perf_pct:.1f}%")
k3.metric("Overall Retention", f"{overall_retention:.1f}%")
k4.metric("High-Performer Retention", f"{hipo_retention:.1f}%",
          delta=f"{hipo_retention-overall_retention:.1f}pp vs overall")
k5.metric("Employees on PIP (Rating 1)", f"{pip_count:,}")

st.markdown("---")

# ── Distribution actual vs target + Perf vs Comp scatter ────────────
c1, c2 = st.columns(2)

with c1:
    st.markdown("##### Performance Distribution: Actual vs Target")
    target_dist = {1:3, 2:12, 3:53, 4:26, 5:5}
    actual_dist = (df["Performance_Rating"].value_counts(normalize=True)*100).sort_index()
    labels = {1:"Unacceptable",2:"Below Exp.",3:"Meets Exp.",4:"Exceeds Exp.",5:"Distinguished"}

    comp_df = pd.DataFrame({
        "Rating": [labels[i] for i in range(1,6)],
        "Actual": [actual_dist.get(i,0) for i in range(1,6)],
        "Target": [target_dist[i] for i in range(1,6)]
    })
    comp_melt = comp_df.melt(id_vars="Rating", var_name="Type", value_name="Pct")
    fig = px.bar(comp_melt, x="Rating", y="Pct", color="Type", barmode="group",
                  color_discrete_map={"Actual":BRAND_COLORS["primary"], "Target":BRAND_COLORS["secondary"]},
                  text=comp_melt["Pct"].round(1))
    fig.update_traces(texttemplate="%{text}%", textposition="outside")
    fig.update_layout(height=400, margin=dict(l=10,r=10,t=10,b=10), yaxis_title="% of Workforce")
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Performance vs Compensation (Compa-Ratio)")
    fig = px.scatter(df.sample(min(2000,len(df)), random_state=42),
                      x="Performance_Rating", y="Compa_Ratio", color="Department",
                      trendline="ols", opacity=0.5)
    fig.update_layout(height=400, margin=dict(l=10,r=10,t=10,b=10),
                       xaxis_title="Performance Rating", yaxis_title="Compa-Ratio",
                       legend=dict(font=dict(size=8)))
    st.plotly_chart(fig, use_container_width=True)

    # Correlation
    corr = df["Performance_Rating"].corr(df["Compa_Ratio"])
    st.caption(f"Correlation (Performance vs Compa-Ratio): **r = {corr:.3f}** — "
               + ("Weak alignment; pay-for-performance may need strengthening." if abs(corr)<0.15
                  else "Meaningful alignment between performance and pay."))

st.markdown("---")

# ── Retention comparison + Training by perf tier ─────────────────────
c1, c2 = st.columns(2)

with c1:
    st.markdown("##### Retention: Overall vs High-Performer")
    fig = go.Figure()
    fig.add_trace(go.Bar(x=["Overall Retention","High-Performer Retention"],
                          y=[overall_retention, hipo_retention],
                          marker_color=[BRAND_COLORS["primary"], BRAND_COLORS["secondary"]],
                          text=[f"{overall_retention:.1f}%", f"{hipo_retention:.1f}%"],
                          textposition="outside"))
    fig.update_layout(height=350, margin=dict(l=10,r=10,t=10,b=10), yaxis_title="Retention %", yaxis_range=[0,100])
    st.plotly_chart(fig, use_container_width=True)

    gap = hipo_retention - overall_retention
    if gap < -2:
        st.warning(f"⚠️ Inverted retention pattern: high performers retained at a {abs(gap):.1f}pp LOWER rate than the overall workforce.")
    else:
        st.success(f"✅ High performers retained at a {gap:.1f}pp rate vs overall — healthy pattern.")

with c2:
    st.markdown("##### Training Hours by Performance Tier")
    labels_map = {1:"Unacceptable",2:"Below Exp.",3:"Meets Exp.",4:"Exceeds Exp.",5:"Distinguished"}
    train_by_perf = df.groupby("Performance_Rating")["Training_Hours"].mean().reset_index()
    train_by_perf["Label"] = train_by_perf["Performance_Rating"].map(labels_map)
    fig = px.bar(train_by_perf, x="Label", y="Training_Hours",
                  category_orders={"Label": list(labels_map.values())},
                  color="Training_Hours", color_continuous_scale="Purples",
                  text=train_by_perf["Training_Hours"].round(1))
    fig.update_traces(texttemplate="%{text} hrs", textposition="outside")
    fig.update_layout(height=350, margin=dict(l=10,r=10,t=10,b=10), coloraxis_showscale=False,
                       yaxis_title="Avg Training Hours")
    st.plotly_chart(fig, use_container_width=True)

st.markdown("---")

# ── Calibration by department ──────────────────────────────────────
st.markdown("##### Performance Distribution by Department (Calibration Check)")
dept_perf = pd.crosstab(df["Department"], df["Performance_Rating"], normalize="index")*100
dept_perf.columns = [labels_map[c] for c in dept_perf.columns]
fig = px.bar(dept_perf.reset_index().melt(id_vars="Department", var_name="Rating", value_name="Pct"),
              x="Department", y="Pct", color="Rating", barmode="stack",
              category_orders={"Rating": list(labels_map.values())},
              color_discrete_sequence=["#993C1D","#D85A30","#BA7517","#5BA85E","#1D9E75"])
fig.update_layout(height=380, margin=dict(l=10,r=10,t=10,b=10), xaxis_tickangle=-30, yaxis_title="% of Department")
st.plotly_chart(fig, use_container_width=True)

with st.expander("📋 Manager-Level Calibration Outliers"):
    mgr_perf = df.groupby("Manager_ID").agg(
        TeamSize=("Employee_ID","count"),
        PctBelowExpectations=("Performance_Rating", lambda x: (x<=2).mean()*100),
        AvgRating=("Performance_Rating","mean")
    ).reset_index()
    mgr_perf = mgr_perf[mgr_perf["TeamSize"]>=3]
    outliers = mgr_perf[mgr_perf["PctBelowExpectations"]>15].sort_values("PctBelowExpectations", ascending=False)
    st.caption(f"{len(outliers)} managers have >15% of their team rated 'Below Expectations' or 'Unacceptable' — candidates for calibration session review.")
    st.dataframe(outliers.round(2), use_container_width=True, hide_index=True)
