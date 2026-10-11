# Interactive presentation

A [Quarto](https://quarto.org) / reveal.js presentation of the glioma brain
digital twin, written for neuro-oncologists, neurosurgeons, clinical
neuroscientists and neuropsychologists.

**Live version:** <https://arvidl.github.io/glioma-brain-digital-twin-public/>

Navigation: `←` `→` between sections, `↓` for deep-dive slides, `M` menu,
`O` overview, `F` full screen, `S` speaker notes.

## Contents

| Path | What it is |
|---|---|
| `index.qmd` | Slide source |
| `_quarto.yml`, `custom.scss` | reveal.js configuration and styling |
| `references.bib` | Cited literature |
| `build_figures.py` | Regenerates the interactive Plotly figures and CSV tables from `NB_C08` |
| `assets/img/` | Static figures copied from `notebooks/figures/capstone/` |
| `assets/interactive/` | Standalone Plotly HTML (four-zone plot, CANTAB, psychosocial, 3D geometry) |
| `assets/video/` | Compressed screen recordings (Freeview, tractography, fMRI) and an AI-generated (Gemini Veo) clip |
| `data/` | Domain summary, sensitivity and test-score tables behind the figures |

## Build

```bash
# 1. (optional) regenerate interactive figures; needs the capstone derivatives
python data/download_data.py --capstone
python presentation/build_figures.py

# 2. render
quarto render presentation        # output in presentation/_site/
quarto preview presentation       # live preview
```

`build_figures.py` executes the analysis cells of
`notebooks/NB_C08_Closing_the_Loop.ipynb`, so the numbers on the slides are the
numbers in the notebook. The rendered site is self-contained (Plotly is bundled
locally), so it can be presented offline from `presentation/_site/index.html`
served by any static web server, for example
`python -m http.server -d presentation/_site`.

Pushing changes under `presentation/` to `main` redeploys GitHub Pages via
`.github/workflows/pages.yml`.

## Caveat

Single-patient proof-of-concept. Research prototype, not for clinical use.
