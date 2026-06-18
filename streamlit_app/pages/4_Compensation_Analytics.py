"""
PeoplePulse AI — Page 4: Compensation Analytics
==================================================
"""

import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go

from utils.helpers import require_login, load_hr_data, filter_by_role, render_header, BRAND_COLORS, to_excel_bytes
from utils.nav import render_sidebar, apply_dark_mode

st.set_page_config(page_title="Compensation Analytics | PeoplePulse AI", page_icon="💰", layout="wide")

user = require_login()
render_sidebar(user, active_page="compensation")
apply_dark_mode()

render_header("Compensation Analytics", "Pay competitiveness, equity, and total rewards cost structure", user)

df = load_hr_data()
df = filter_by_role(df, user)

# ── KPIs ─────────────────────────────────────────────────────────
avg_compa = df["Compa_Ratio"].mean()
below_market = (df["Compa_Ratio"] < 0.85).mean()*100
total_comp_cost = df["Total_Comp"].sum()
avg_bonus_ratio = (df["Bonus"]/df["Salary"]).mean()*100

male_avg = df[df.Gender=="Male"]["Salary"].mean()
female_avg = df[df.Gender=="Female"]["Salary"].mean()
pay_gap_pct = (male_avg - female_avg)/male_avg*100 if male_avg else 0

k1,k2,k3,k4,k5 = st.columns(5)
k1.metric("Avg Compa-Ratio", f"{avg_compa:.3f}")
k2.metric("Gender Pay Gap", f"{pay_gap_pct:.2f}%")
k3.metric("Total Comp Cost", f"${total_comp_cost/1e6:.1f}M")
k4.metric("% Below Market (<0.85)", f"{below_market:.1f}%")
k5.metric("Avg Bonus-to-Base", f"{avg_bonus_ratio:.1f}%")

st.markdown("---")

# ── Salary distribution by level + pay equity heatmap ──────────────
c1, c2 = st.columns(2)

with c1:
    st.markdown("##### Salary Distribution by Level (Box Plot)")
    level_order = ["L2","L3","L4","L5","L6","L7","L8"]
    fig = px.box(df, x="Job_Level", y="Salary", category_orders={"Job_Level": level_order},
                  color_discrete_sequence=[BRAND_COLORS["primary"]])
    fig.update_layout(height=420, margin=dict(l=10,r=10,t=10,b=10), yaxis_title="Salary ($)")
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Pay Equity Heatmap — Gender Pay Gap % by Level")
    level_order = ["L2","L3","L4","L5","L6","L7","L8"]
    rows = []
    for lvl in level_order:
        sub = df[df["Job_Level"]==lvl]
        m = sub[sub.Gender=="Male"]["Salary"].mean()
        f = sub[sub.Gender=="Female"]["Salary"].mean()
        gap = (m-f)/m*100 if (m and not np.isnan(m) and not np.isnan(f)) else np.nan
        rows.append({"Level": lvl, "Pay Gap %": gap})
    gap_df = pd.DataFrame(rows).set_index("Level")
    fig = px.imshow(gap_df.T, text_auto=".1f", color_continuous_scale="RdYlGn_r",
                     aspect="auto", labels=dict(color="Gap %"), zmin=-5, zmax=10)
    fig.update_layout(height=200, margin=dict(l=10,r=10,t=10,b=10))
    st.plotly_chart(fig, use_container_width=True)

    st.markdown("##### Compa-Ratio Distribution")
    bins = [0,0.7,0.8,0.9,1.1,1.2,3]
    labels = ["<0.70 Severely Underpaid","0.70-0.80 At Risk","0.80-0.90 Below Mid",
              "0.90-1.10 Market Range","1.10-1.20 Above Mid","1.20+ Top of Band"]
    df["CompaBand"] = pd.cut(df["Compa_Ratio"], bins=bins, labels=labels)
    compa_counts = df["CompaBand"].value_counts().reindex(labels).reset_index()
    compa_counts.columns = ["Band","Count"]
    colors = [BRAND_COLORS["danger"], BRAND_COLORS["danger"], BRAND_COLORS["warning"],
              BRAND_COLORS["secondary"], BRAND_COLORS["primary"], BRAND_COLORS["purple"]]
    fig = px.bar(compa_counts, x="Count", y="Band", orientation="h", color="Band",
                  color_discrete_sequence=colors)
    fig.update_layout(height=220, margin=dict(l=10,r=10,t=10,b=10), showlegend=False)
    st.plotly_chart(fig, use_container_width=True)

st.markdown("---")

# ── Bonus differentiation + Band penetration ────────────────────────
c1, c2 = st.columns(2)

with c1:
    st.markdown("##### Bonus-to-Base Ratio by Performance Tier")
    perf_labels = {1:"Unacceptable",2:"Below Exp.",3:"Meets Exp.",4:"Exceeds Exp.",5:"Distinguished"}
    df["PerfLabelOrdered"] = df["Performance_Rating"].map(perf_labels)
    bonus_by_perf = df.groupby("Performance_Rating").apply(
        lambda x: (x["Bonus"]/x["Salary"]).mean()*100
    ).reset_index()
    bonus_by_perf.columns = ["Rating","BonusPct"]
    bonus_by_perf["Label"] = bonus_by_perf["Rating"].map(perf_labels)

    fig = px.bar(bonus_by_perf, x="Label", y="BonusPct",
                  category_orders={"Label": list(perf_labels.values())},
                  color="BonusPct", color_continuous_scale="Blues",
                  text=bonus_by_perf["BonusPct"].round(1))
    fig.update_traces(texttemplate="%{text}%", textposition="outside")
    fig.update_layout(height=380, margin=dict(l=10,r=10,t=10,b=10), coloraxis_showscale=False,
                       yaxis_title="Avg Bonus % of Base")
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Total Comp Cost by Department")
    dept_cost = df.groupby("Department")["Total_Comp"].sum().reset_index()
    dept_cost.columns = ["Department","TotalCost"]
    fig = px.treemap(dept_cost, path=["Department"], values="TotalCost",
                      color="TotalCost", color_continuous_scale="Blues")
    fig.update_layout(height=380, margin=dict(l=10,r=10,t=10,b=10))
    st.plotly_chart(fig, use_container_width=True)

st.markdown("---")

# ── Detail table & export ────────────────────────────────────────────
with st.expander("📋 Department × Level Compensation Table"):
    detail = df.groupby(["Department","Job_Level"]).agg(
        Headcount=("Employee_ID","count"),
        AvgSalary=("Salary","mean"),
        AvgCompaRatio=("Compa_Ratio","mean"),
        AvgBonus=("Bonus","mean")
    ).round(2).reset_index()
    st.dataframe(detail, use_container_width=True, hide_index=True)

    excel_data = to_excel_bytes(detail, sheet_name="Compensation Detail")
    st.download_button("📊 Export to Excel", data=excel_data,
                        file_name="PeoplePulse_Compensation_Detail.xlsx",
                        mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
