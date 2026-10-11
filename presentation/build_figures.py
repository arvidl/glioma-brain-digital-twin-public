"""Build data tables and interactive Plotly figures for the clinical presentation.

The domain-vulnerability analysis is taken verbatim from the code cells of
``notebooks/NB_C08_Closing_the_Loop.ipynb`` so that the presentation always
matches the notebook. Running it requires the capstone data:

    python data/download_data.py --capstone
    python presentation/build_figures.py [--repo-root PATH]

Outputs (committed, so the slides render without the imaging data):
    presentation/data/*.csv
    presentation/assets/interactive/*.html
"""

import argparse
import json
import os
import re
from pathlib import Path

import pandas as pd
import plotly.graph_objects as go

HERE = Path(__file__).resolve().parent
DATA_OUT = HERE / "data"
HTML_OUT = HERE / "assets" / "interactive"

FONT = dict(family="Source Sans Pro, Helvetica, Arial, sans-serif", size=15, color="#222")
ZONE_COLORS = {
    "Expected preservation": "rgba(102,187,106,0.12)",
    "Resilience / plasticity": "rgba(66,133,244,0.12)",
    "Model miss / extra-structural": "rgba(255,167,38,0.14)",
    "Model-supported deficit": "rgba(229,57,53,0.12)",
}
DOMAIN_COLORS = {
    "Motor": "#C58F65",
    "Processing speed": "#5B9B6C",
    "Attention / speed": "#4E79A7",
    "Sustained attention": "#2F5D8A",
    "Executive function": "#8E63A9",
    "Working memory": "#D98C3F",
}
LABEL_POSITIONS = {
    "Sustained attention": "top left",
    "Executive function": "bottom right",
    "Motor": "bottom center",
}


def run_c08_analysis(repo_root: Path) -> dict:
    nb = json.loads((repo_root / "notebooks" / "NB_C08_Closing_the_Loop.ipynb").read_text())
    code = ["".join(c["source"]) for c in nb["cells"] if c["cell_type"] == "code"]
    setup, coupling, domains = code[0], code[1], code[2]
    setup = re.sub(r"^(\s*)!.*$", r"\1pass", setup, flags=re.M)

    ns: dict = {"__name__": "c08"}
    cwd = Path.cwd()
    os.chdir(repo_root / "notebooks")
    try:
        for src in (setup, coupling, domains):
            exec(compile(src, "NB_C08", "exec"), ns)
    finally:
        os.chdir(cwd)
    return ns


def write_tables(ns: dict) -> dict:
    DATA_OUT.mkdir(parents=True, exist_ok=True)
    summary = ns["domain_summary"]
    sens = ns["domain_sensitivity"]
    cog = ns["df_cog"]
    sessions = ns["df_ses"]

    summary.to_csv(DATA_OUT / "domain_summary.csv", index=False)
    sens.to_csv(DATA_OUT / "domain_sensitivity.csv", index=False)
    cog.to_csv(DATA_OUT / "cantab.csv", index=False)

    psych_cols = {
        "stai": ("STAI anxiety", 40, "higher = more anxious"),
        "pswq": ("PSWQ worry", 62, "higher = more worry"),
        "erq_reappraisal": ("ERQ reappraisal", None, "higher = more adaptive coping"),
        "erq_suppression": ("ERQ suppression", None, "higher = more suppression"),
        "loneliness": ("UCLA loneliness", 40, "higher = lonelier"),
    }
    rows = []
    for col, (label, threshold, meaning) in psych_cols.items():
        rows.append({
            "Measure": label,
            "Pre-op": float(sessions.loc["ses-preop", col]),
            "Post-op": float(sessions.loc["ses-postop", col]),
            "Threshold": threshold,
            "Meaning": meaning,
        })
    psych = pd.DataFrame(rows)
    psych.to_csv(DATA_OUT / "psychosocial.csv", index=False)
    return {
        "summary": summary,
        "sens": sens,
        "cog": cog,
        "psych": psych,
        "vuln_thr": ns["vulnerability_threshold"],
        "chg_thr": ns["change_threshold"],
        "alpha_sc": ns["alpha_sc"],
    }


def _layout(fig, title, height=560):
    fig.update_layout(
        title=dict(text=title, x=0.01, font=dict(size=20)),
        font=FONT,
        template="plotly_white",
        height=height,
        margin=dict(l=70, r=30, t=70, b=60),
        hoverlabel=dict(font_size=14),
    )


def _save(fig, name):
    HTML_OUT.mkdir(parents=True, exist_ok=True)
    fig.write_html(
        HTML_OUT / f"{name}.html",
        include_plotlyjs="directory",
        full_html=True,
        auto_play=False,
        config={"displaylogo": False, "responsive": True},
    )


def four_zone_figure(t: dict):
    summary, sens = t["summary"], t["sens"]
    vthr, cthr = t["vuln_thr"], t["chg_thr"]
    obs = summary.set_index("Domain")
    alphas = sorted(sens["alpha_sc"].unique())
    x_max = max(vthr + 2, sens["Predicted vulnerability (%)"].max() * 1.12)
    y_lim = max(10, obs["Observed change (%)"].abs().max() * 1.35)

    def traces_for(alpha):
        s = sens[sens["alpha_sc"] == alpha].set_index("Domain")
        out = []
        for dom in obs.index:
            v = s.loc[dom, "Predicted vulnerability (%)"]
            o = obs.loc[dom, "Observed change (%)"]
            out.append(go.Scatter(
                x=[v], y=[o], mode="markers+text", name=dom,
                text=[dom], textposition=LABEL_POSITIONS.get(dom, "top center"),
                marker=dict(size=18, color=DOMAIN_COLORS.get(dom, "#888"),
                            line=dict(color="white", width=2)),
                customdata=[[obs.loc[dom, "Metric"], obs.loc[dom, "Mean displacement (mm)"]]],
                hovertemplate=(
                    f"<b>{dom}</b><br>CANTAB: %{{customdata[0]}}"
                    "<br>Predicted vulnerability: %{x:.1f}%"
                    "<br>Observed change: %{y:+.1f}%"
                    "<br>Mean model displacement: %{customdata[1]:.3f} mm"
                    f"<br>Coupling strength α = {alpha:g}<extra></extra>"
                ),
            ))
        return out

    default = t["alpha_sc"] if t["alpha_sc"] in alphas else alphas[len(alphas) // 2]
    fig = go.Figure(data=traces_for(default))
    fig.frames = [go.Frame(data=traces_for(a), name=f"{a:g}") for a in alphas]

    shapes = [
        dict(type="rect", x0=0, x1=vthr, y0=0, y1=y_lim, fillcolor=ZONE_COLORS["Expected preservation"], line_width=0, layer="below"),
        dict(type="rect", x0=vthr, x1=x_max, y0=0, y1=y_lim, fillcolor=ZONE_COLORS["Resilience / plasticity"], line_width=0, layer="below"),
        dict(type="rect", x0=0, x1=vthr, y0=-y_lim, y1=0, fillcolor=ZONE_COLORS["Model miss / extra-structural"], line_width=0, layer="below"),
        dict(type="rect", x0=vthr, x1=x_max, y0=-y_lim, y1=0, fillcolor=ZONE_COLORS["Model-supported deficit"], line_width=0, layer="below"),
        dict(type="rect", x0=0, x1=x_max, y0=-cthr, y1=cthr, fillcolor="rgba(120,120,120,0.10)", line_width=0, layer="below"),
        dict(type="line", x0=vthr, x1=vthr, y0=-y_lim, y1=y_lim, line=dict(dash="dash", color="#777")),
        dict(type="line", x0=0, x1=x_max, y0=0, y1=0, line=dict(dash="dash", color="#777")),
    ]
    ann = [
        dict(x=vthr / 2, y=y_lim * 0.88, text="Expected preservation", showarrow=False, font=dict(color="#2E7D32")),
        dict(x=(vthr + x_max) / 2, y=y_lim * 0.88, text="Resilience / plasticity", showarrow=False, font=dict(color="#1565C0")),
        dict(x=vthr / 2, y=-y_lim * 0.88, text="Model miss / extra-structural", showarrow=False, font=dict(color="#E65100")),
        dict(x=(vthr + x_max) / 2, y=-y_lim * 0.88, text="Model-supported deficit", showarrow=False, font=dict(color="#C62828")),
        dict(x=0.3, y=0, xanchor="left", text=f"grey band: |change| < {cthr:g}%<br>no reliable change<br>(likely test–retest noise)",
             showarrow=False, align="left", font=dict(size=11, color="#555")),
    ]
    _layout(fig, "Closing the loop: predicted vulnerability vs observed cognitive change", height=620)
    fig.update_layout(
        shapes=shapes, annotations=ann, showlegend=False,
        xaxis=dict(title="Predicted structural vulnerability (%)  →  more model-predicted loss", range=[0, x_max]),
        yaxis=dict(title="Observed CANTAB change (%)  ↑ better", range=[-y_lim, y_lim], zeroline=False),
        sliders=[dict(
            active=alphas.index(default),
            currentvalue=dict(prefix="Mechanics → connectivity coupling strength α = "),
            pad=dict(t=50),
            steps=[dict(method="animate", label=f"{a:g}",
                        args=[[f"{a:g}"], dict(mode="immediate", frame=dict(duration=300, redraw=True),
                                                transition=dict(duration=300))]) for a in alphas],
        )],
        margin=dict(l=70, r=30, t=70, b=120),
    )
    _save(fig, "four_zone")


def cantab_figure(t: dict):
    cog = t["cog"].copy()
    cog["Aligned"] = cog.apply(lambda r: -r["%Delta"] if r["Direction"] == "lower_better" else r["%Delta"], axis=1)
    cog = cog.sort_values("Aligned")
    cthr = t["chg_thr"]
    colors = ["#9E9E9E" if abs(v) < cthr else "#2E7D32" if v > 0 else "#C62828" for v in cog["Aligned"]]
    labels = [f"{m}<br><span style='font-size:12px;color:#666'>{d}</span>" for m, d in zip(cog["Metric"], cog["Domain"])]
    fig = go.Figure(go.Bar(
        x=cog["Aligned"], y=labels, orientation="h", marker_color=colors,
        text=[f"{v:+.1f}%" for v in cog["Aligned"]], textposition="outside",
        customdata=cog[["Pre-op", "Post-op", "Direction"]].values,
        hovertemplate=("%{y}<br>Pre-op: %{customdata[0]:.3g}<br>Post-op: %{customdata[1]:.3g}"
                       "<br>Direction-aligned change: %{x:+.1f}%<br>(%{customdata[2]})<extra></extra>"),
    ))
    fig.add_vrect(x0=-cthr, x1=cthr, fillcolor="rgba(120,120,120,0.12)", line_width=0)
    fig.add_vline(x=0, line_color="#444")
    _layout(fig, "PAT16 CANTAB: pre- vs post-operative change (positive = better)", height=520)
    lim = max(12, cog["Aligned"].abs().max() * 1.35)
    fig.update_layout(xaxis=dict(title="Direction-aligned change (%)", range=[-lim, lim]), showlegend=False)
    fig.add_annotation(x=0, y=1.06, xref="x", yref="paper", showarrow=False,
                       text=f"grey band: |change| < {cthr:g}% (no reliable change)", font=dict(size=12, color="#555"))
    _save(fig, "cantab")


def psychosocial_figure(t: dict):
    psych = t["psych"]
    fig = go.Figure()
    fig.add_bar(name="Pre-op", x=psych["Measure"], y=psych["Pre-op"], marker_color="#90A4AE",
                customdata=psych["Meaning"], hovertemplate="%{x} (pre-op): %{y}<br>%{customdata}<extra></extra>")
    fig.add_bar(name="Post-op", x=psych["Measure"], y=psych["Post-op"], marker_color="#5C6BC0",
                customdata=psych["Meaning"], hovertemplate="%{x} (post-op): %{y}<br>%{customdata}<extra></extra>")
    for i, row in psych.iterrows():
        if pd.notna(row["Threshold"]):
            fig.add_shape(type="line", x0=i - 0.45, x1=i + 0.45, y0=row["Threshold"], y1=row["Threshold"],
                          line=dict(color="#C62828", dash="dot", width=2))
    _layout(fig, "Psychosocial context changed after surgery (red dotted = clinical threshold)", height=500)
    fig.update_layout(barmode="group", yaxis_title="Score", legend=dict(orientation="h", y=1.02, x=0.75))
    _save(fig, "psychosocial")


def geometry_3d_figure(repo_root: Path, panel: str = "scene3"):
    """Extract one 3D panel (default: displacement context) from the NB_C06 multi-panel export."""
    src = repo_root / "notebooks" / "figures" / "capstone" / "figC06_A5_geometry_3d.html"
    if not src.exists():
        return
    html = src.read_text()
    dec = json.JSONDecoder()
    start = html.index("[", html.index("Plotly.newPlot("))
    data, end = dec.raw_decode(html[start:])
    layout, _ = dec.raw_decode(html[html.index("{", start + end):])

    traces = []
    for t in data:
        if t.get("scene", "scene") == panel:
            t["scene"] = "scene"
            traces.append(t)
    scene = layout[panel]
    scene.pop("domain", None)
    eye = scene.get("camera", {}).get("eye", {"x": 1.25, "y": 1.25, "z": 1.25})
    scene["camera"] = {**scene.get("camera", {}), "eye": {k: v * 0.65 for k, v in eye.items()}}

    fig = go.Figure(data=traces)
    fig.update_layout(
        template="plotly_white",
        scene=scene,
        autosize=True,
        height=640,
        margin=dict(l=0, r=0, t=10, b=0),
        legend=dict(orientation="h", y=0.02, x=0.5, xanchor="center", font=dict(size=13),
                    bgcolor="rgba(255,255,255,0.7)", itemsizing="constant"),
        font=dict(family="Source Sans Pro, Helvetica, Arial, sans-serif"),
    )
    _save(fig, "geometry_3d")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo-root", type=Path, default=HERE.parent)
    args = parser.parse_args()
    repo_root = args.repo_root.resolve()

    tables = write_tables(run_c08_analysis(repo_root))
    four_zone_figure(tables)
    cantab_figure(tables)
    psychosocial_figure(tables)
    geometry_3d_figure(HERE.parent)
    print(tables["summary"][["Domain", "Predicted vulnerability (%)", "Observed change (%)", "Interpretation"]].to_string(index=False))
    print(f"Wrote tables to {DATA_OUT} and figures to {HTML_OUT}")


if __name__ == "__main__":
    main()
