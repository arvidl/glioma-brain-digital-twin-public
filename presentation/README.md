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
| `assets/vendor/mathjax/` | Bundled MathJax 3 (Apache-2.0) so equations render offline |
| `present_offline.sh` | Serves the rendered slides locally for a talk without internet |
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
numbers in the notebook.

Pushing changes under `presentation/` to `main` redeploys GitHub Pages via
`.github/workflows/pages.yml`.

## Presenting offline (recommended for the talk)

Venue Wi-Fi can fail. Everything the slides need is bundled in the site:
reveal.js, Plotly, MathJax (`assets/vendor/mathjax/`), the videos and fonts.
Only the hyperlinks to papers and to GitHub need the internet.

```bash
bash presentation/present_offline.sh            # renders if needed, serves, opens the browser
bash presentation/present_offline.sh --render   # force a fresh render first
PORT=8080 bash presentation/present_offline.sh  # if port 8000 is taken
```

The script serves `presentation/_site/` at <http://localhost:8000/> using only
Python's built-in web server. It also warns if any script, style or media file
would still be loaded from the internet. Stop it with `Ctrl+C`.

Use a local server rather than double-clicking `_site/index.html`: some
browsers block the embedded interactive charts when a page is opened directly
from disk.

Before the talk:

1. Run `bash presentation/present_offline.sh --render` once while you still
   have internet. Rendering needs [Quarto](https://quarto.org); serving the
   result does not.
2. Turn Wi-Fi off and click through the interactive slides (CANTAB,
   psychosocial, 3D geometry, four-zone slider), the four videos and the
   mechanics deep-dive equations.
3. Press `F` for full screen. Press `S` for the speaker view (notes, timer and
   next slide); it opens in a separate window, so allow pop-ups for
   `localhost`.

To present from another computer without Quarto, copy the whole
`presentation/_site/` folder and run
`python3 -m http.server 8000 --directory _site` next to it.

## Caveat

Single-patient proof-of-concept. Research prototype, not for clinical use.
