"""
PeoplePulse AI — Page 7: Diversity Analytics
===============================================
"""

import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go

from utils.helpers import require_login, load_hr_data, filter_by_role, render_header, BRAND_COLORS
from utils.nav import render_sidebar, apply_dark_mode

st.set_page_config(page_title="Diversity Analytics | PeoplePulse AI", page_icon="🌐", layout="wide")

user = require_login()
render_sidebar(user, active_page="diversity")
apply_dark_mode()

render_header("Diversity Analytics", "Representation, pay equity, and inclusion health for DEI strategy and ESG reporting", user)

df = load_hr_data()
df = filter_by_role(df, user)

# ── KPIs ─────────────────────────────────────────────────────────
female_pct = (df["Gender"]=="Female").mean()*100
senior_levels = ["L6","L7","L8"]
female_senior_pct = (df[df["Job_Level"].isin(senior_levels)]["Gender"]=="Female").mean()*100 if (df["Job_Level"].isin(senior_levels)).any() else 0

male_avg = df[df.Gender=="Male"]["Salary"].mean()
female_avg = df[df.Gender=="Female"]["Salary"].mean()
pay_gap_pct = abs((male_avg-female_avg)/male_avg*100) if male_avg else 0
pay_equity_index = 100 - min(pay_gap_pct, 10)/10*100

male_att = (df[df.Gender=="Male"]["Attrition"]=="Yes").mean()*100
female_att = (df[df.Gender=="Female"]["Attrition"]=="Yes").mean()*100
att_diff = female_att - male_att

k1,k2,k3,k4,k5 = st.columns(5)
k1.metric("Female Representation (Overall)", f"{female_pct:.1f}%")
k2.metric("Female Representation (L6+)", f"{female_senior_pct:.1f}%")
k3.metric("Pay Equity Index", f"{pay_equity_index:.1f}/100")
k4.metric("Pay Gap (Gender)", f"{pay_gap_pct:.2f}%")
k5.metric("Attrition Differential (F-M)", f"{att_diff:+.1f}pp")

st.markdown("---")

# ── Representation pipeline + Pay equity gauge ──────────────────────
c1, c2 = st.columns([1.4,1])

with c1:
    st.markdown("##### Representation Pipeline — Gender % by Job Level")
    level_order = ["L2","L3","L4","L5","L6","L7","L8"]
    level_names = {"L2":"Associate","L3":"Specialist","L4":"Sr Specialist","L5":"Staff/Principal",
                    "L6":"Director","L7":"VP","L8":"C-Suite"}

    pipeline = []
    for lvl in level_order:
        sub = df[df["Job_Level"]==lvl]
        if len(sub)==0: continue
        pipeline.append({
            "Level": level_names[lvl],
            "Male": (sub["Gender"]=="Male").mean()*100,
            "Female": (sub["Gender"]=="Female").mean()*100,
            "Non-binary": (sub["Gender"]=="Non-binary").mean()*100,
        })
    pipe_df = pd.DataFrame(pipeline)
    pipe_melt = pipe_df.melt(id_vars="Level", var_name="Gender", value_name="Pct")
    fig = px.bar(pipe_melt, x="Level", y="Pct", color="Gender", barmode="stack",
                  category_orders={"Level": [level_names[l] for l in level_order]},
                  color_discrete_map={"Male":BRAND_COLORS["primary"], "Female":BRAND_COLORS["secondary"],
                                       "Non-binary":BRAND_COLORS["purple"]})
    fig.update_layout(height=420, margin=dict(l=10,r=10,t=10,b=10), yaxis_title="% of Level")
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Pay Equity Index")
    fig = go.Figure(go.Indicator(
        mode="gauge+number",
        value=pay_equity_index,
        gauge={
            'axis': {'range':[80,100]},
            'bar': {'color': BRAND_COLORS["primary"]},
            'steps': [
                {'range':[80,90], 'color': BRAND_COLORS["danger_light"]},
                {'range':[90,95], 'color': BRAND_COLORS["warning_light"]},
                {'range':[95,100], 'color': BRAND_COLORS["secondary_light"]},
            ],
            'threshold': {'line':{'color':"black",'width':3}, 'value':97}
        },
        number={'suffix':"/100"}
    ))
    fig.update_layout(height=280, margin=dict(l=10,r=10,t=20,b=10))
    st.plotly_chart(fig, use_container_width=True)
    st.caption("Above 97: within statistical noise. Below 95: remediation warranted. Below 90: material legal exposure.")

st.markdown("---")

# ── New hire vs existing + Attrition differential heatmap ────────────
c1, c2 = st.columns(2)

with c1:
    st.markdown("##### New Hires vs Existing Workforce — Gender Mix")
    new_hires = df[df["Years_At_Company"]<1]
    existing = df[df["Years_At_Company"]>=1]

    comp_data = []
    for g in ["Male","Female","Non-binary"]:
        comp_data.append({"Gender": g,
                           "New Hires": (new_hires["Gender"]==g).mean()*100 if len(new_hires) else 0,
                           "Existing Workforce": (existing["Gender"]==g).mean()*100 if len(existing) else 0})
    comp_df = pd.DataFrame(comp_data).melt(id_vars="Gender", var_name="Population", value_name="Pct")
    fig = px.bar(comp_df, x="Gender", y="Pct", color="Population", barmode="group",
                  color_discrete_map={"New Hires":BRAND_COLORS["secondary"], "Existing Workforce":BRAND_COLORS["primary"]},
                  text=comp_df["Pct"].round(1))
    fig.update_traces(texttemplate="%{text}%", textposition="outside")
    fig.update_layout(height=380, margin=dict(l=10,r=10,t=10,b=10))
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Attrition Rate by Gender × Department")
    att_matrix = df.groupby(["Department","Gender"]).apply(
        lambda x: (x["Attrition"]=="Yes").mean()*100
    ).reset_index(name="AttritionRate")
    pivot = att_matrix.pivot(index="Department", columns="Gender", values="AttritionRate")
    fig = px.imshow(pivot, text_auto=".1f", color_continuous_scale="RdYlGn_r", aspect="auto",
                     labels=dict(color="Attrition %"))
    fig.update_layout(height=380, margin=dict(l=10,r=10,t=10,b=10))
    st.plotly_chart(fig, use_container_width=True)

st.markdown("---")

# ── Age distribution + Source diversity ──────────────────────────────
c1, c2 = st.columns(2)

with c1:
    st.markdown("##### Age Band Distribution")
    age_bins = [0,25,35,45,55,65,100]
    age_labels = ["<25","25-34","35-44","45-54","55-64","65+"]
    df["AgeBand"] = pd.cut(df["Age"], bins=age_bins, labels=age_labels)
    age_counts = df["AgeBand"].value_counts().reindex(age_labels).reset_index()
    age_counts.columns = ["AgeBand","Count"]
    fig = px.bar(age_counts, x="AgeBand", y="Count", color="Count", color_continuous_scale="Blues",
                  text="Count")
    fig.update_layout(height=350, margin=dict(l=10,r=10,t=10,b=10), coloraxis_showscale=False)
    st.plotly_chart(fig, use_container_width=True)

with c2:
    st.markdown("##### Recruitment Source — Gender Mix")
    src_gender = df.groupby(["Recruitment_Source","Gender"]).size().reset_index(name="Count")
    src_total = df.groupby("Recruitment_Source").size().reset_index(name="Total")
    src_gender = src_gender.merge(src_total, on="Recruitment_Source")
    src_gender["Pct"] = src_gender["Count"]/src_gender["Total"]*100
    fig = px.bar(src_gender, x="Recruitment_Source", y="Pct", color="Gender", barmode="stack",
                  color_discrete_map={"Male":BRAND_COLORS["primary"], "Female":BRAND_COLORS["secondary"],
                                       "Non-binary":BRAND_COLORS["purple"]})
    fig.update_layout(height=350, margin=dict(l=10,r=10,t=10,b=10), xaxis_tickangle=-30, yaxis_title="%")
    st.plotly_chart(fig, use_container_width=True)
