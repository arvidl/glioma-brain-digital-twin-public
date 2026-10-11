# Slide Deck Builder (`build_pptx.py`)

Programmatically build the Finse 2026 presentation as a `.pptx` file using
[python-pptx](https://python-pptx.readthedocs.io/).  The script mirrors the
nine capstone notebooks (NB\_C01–C09) and the existing Beamer deck, producing
a self-contained PowerPoint file with embedded figures, speaker notes, and a
consistent visual identity.

## Quick start

```bash
# Default output: beamer/glioma_digital_twin_finse2026.pptx
python beamer/build_pptx.py

# Custom output path
python beamer/build_pptx.py -o my_talk.pptx

# Use an alternate figure directory
python beamer/build_pptx.py --fig-dir /path/to/figures
```

The generated `.pptx` can be opened in **PowerPoint**, **Keynote**, or
**Google Slides**.

## Architecture

```
build_pptx.py
├── Configuration ──── colours, fonts, slide dimensions (16:9)
├── Helpers
│   ├── _set_slide_bg()        set solid background colour
│   ├── _add_textbox()         single-paragraph text box
│   ├── _add_rich_textbox()    multi-paragraph with per-line formatting
│   ├── _add_image()           insert PNG or show placeholder
│   ├── _set_notes()           speaker notes
│   ├── _section_divider()     dark section-break slide
│   ├── _content_slide()       title bar + bullets ± figure
│   └── _full_figure_slide()   full-width figure with caption
├── Section builders ── build_c01() … build_c09(), build_summary()
└── main() ──────────── CLI, calls build_deck()
```

### Colour palette

Defined to match the Beamer `preamble.tex`:

| Variable | RGB | Use |
|----------|-----|-----|
| `CLR_DARK` | `#23373B` | Dark teal backgrounds |
| `CLR_TEAL` | `#007788` | Title bars (metropolis teal) |
| `CLR_ACCENT` | `#EB811E` | Orange accent (section numbers) |
| `CLR_TUMOR` | `#CC3333` | Tumor overlays |
| `CLR_CAVITY` | `#3366CC` | Cavity overlays |
| `CLR_WM` | `#339966` | White-matter overlays |

## Adding or modifying slides

Each `build_cNN()` function corresponds to one capstone notebook.  To add a
slide, call one of the helper functions inside the relevant builder:

```python
# Text + figure (two-column)
_content_slide(prs,
    "My New Slide Title",
    ["First bullet point",
     "Second bullet with Unicode: \u03b1, \u03b2, \u03b3"],
    fig_dir, "my_figure.png",
    notes="Speaker notes go here.")

# Full-width figure
_full_figure_slide(prs,
    "Full Figure Title",
    fig_dir, "wide_figure.png",
    caption="Optional caption below the figure",
    notes="Speaker notes.")

# Section divider (dark background)
_section_divider(prs, "Part X", "Section Title\nOptional Second Line",
                 "Subtitle / notebook reference")
```

After editing, regenerate with `python beamer/build_pptx.py`.

---

## Tips and tricks

### 1. Tables

`python-pptx` has a full table API.  Add a helper like this to the script:

```python
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN

def _add_table(slide, left, top, width, height, data, *,
               col_widths=None, header_color=None, font_size=14):
    """
    Add a formatted table to a slide.

    Parameters
    ----------
    data : list[list[str]]
        2-D list: first row is treated as header.
    col_widths : list[Inches] | None
        Per-column widths; if None, columns are equal width.
    header_color : RGBColor | None
        Background fill for the header row.
    """
    rows, cols = len(data), len(data[0])
    table_shape = slide.shapes.add_table(rows, cols, left, top, width, height)
    table = table_shape.table

    # Column widths
    if col_widths:
        for j, w in enumerate(col_widths):
            table.columns[j].width = w

    for i, row_data in enumerate(data):
        for j, cell_text in enumerate(row_data):
            cell = table.cell(i, j)
            cell.text = str(cell_text)

            # Font
            for paragraph in cell.text_frame.paragraphs:
                paragraph.font.size = Pt(font_size)
                paragraph.font.name = "Calibri"
                paragraph.alignment = PP_ALIGN.CENTER

            # Header row styling
            if i == 0:
                for paragraph in cell.text_frame.paragraphs:
                    paragraph.font.bold = True
                    paragraph.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
                if header_color:
                    cell.fill.solid()
                    cell.fill.fore_color.rgb = header_color

    return table_shape
```

**Usage example** (acquisition parameters table):

```python
slide = prs.slides.add_slide(prs.slide_layouts[6])  # blank layout

data = [
    ["Modality", "Resolution", "TR / TE", "Other"],
    ["T1w MPRAGE", "1.0 mm iso", "2300 / 2.98 ms", "176 slices"],
    ["DWI",       "2.5 mm iso", "7200 / 90 ms",   "b = 700/1000/2000"],
    ["BOLD",      "3.0 mm iso", "1700 / 30 ms",   "200 volumes"],
]

_add_table(slide,
    left=Inches(1.5), top=Inches(1.5),
    width=Inches(10), height=Inches(3),
    data=data,
    col_widths=[Inches(2.5), Inches(2.5), Inches(2.5), Inches(2.5)],
    header_color=CLR_TEAL,
    font_size=16)
```

**Table tips:**

- **Merge cells:** `table.cell(0, 0).merge(table.cell(0, 2))` spans three
  columns.
- **Per-cell colour:** `cell.fill.solid(); cell.fill.fore_color.rgb = CLR_TUMOR`
  to highlight a cell (e.g. tumor-related rows).
- **Borders:** `python-pptx` does not yet have a high-level border API.
  Workaround: set `table.first_row = True` and `table.horz_banding = True`
  for built-in banding styles, or manipulate the XML directly:

```python
from lxml import etree

def _set_cell_border(cell, color="007788", width="12700"):
    """Set all four borders of a cell (width in EMU; 12700 = 1 pt)."""
    tc = cell._tc
    tcPr = tc.get_or_add_tcPr()
    for edge in ("lnL", "lnR", "lnT", "lnB"):
        ln = etree.SubElement(
            tcPr,
            "{http://schemas.openxmlformats.org/drawingml/2006/main}" + edge,
            w=width)
        solidFill = etree.SubElement(
            ln,
            "{http://schemas.openxmlformats.org/drawingml/2006/main}solidFill")
        srgbClr = etree.SubElement(
            solidFill,
            "{http://schemas.openxmlformats.org/drawingml/2006/main}srgbClr",
            val=color)
```

---

### 2. Figures and images

#### Embedding PNGs from the notebooks

The capstone figures live in `notebooks/figures/capstone/`.  The
`_add_image()` helper inserts the file if it exists; otherwise it places a
grey placeholder text box so the deck always builds without errors.

```python
# Width-constrained (aspect ratio preserved)
slide.shapes.add_picture("path/to/fig.png", Inches(1), Inches(1.5),
                         width=Inches(10))

# Both width and height specified (may distort)
slide.shapes.add_picture("path/to/fig.png", Inches(1), Inches(1.5),
                         width=Inches(10), height=Inches(5))
```

#### Rendering matplotlib figures to slides

Instead of saving to disk first, render directly from a matplotlib figure:

```python
import io
from pptx.util import Inches

def _add_mpl_figure(slide, fig, left, top, width, height=None):
    """Embed a matplotlib Figure object directly into a slide."""
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=200, bbox_inches="tight",
                facecolor="white", edgecolor="none")
    buf.seek(0)
    if height:
        slide.shapes.add_picture(buf, left, top, width, height)
    else:
        slide.shapes.add_picture(buf, left, top, width=width)
    buf.close()
```

**Usage:**

```python
import matplotlib.pyplot as plt
import numpy as np

fig, ax = plt.subplots(figsize=(8, 4))
ax.imshow(np.random.rand(83, 83), cmap="RdBu_r")
ax.set_title("FC matrix")

_add_mpl_figure(slide, fig, Inches(1), Inches(1.5), Inches(10))
plt.close(fig)
```

#### Freeview screenshots

The interactive workflow for Freeview illustrations is documented in
`beamer/gslides/README.md`.  To incorporate screenshots:

1. Position the view in Freeview.
2. `File → Save Screenshot` or use the Freeview scripting command:
   `freeview -cmd "screencapture /path/to/screenshot.png"`.
3. Save into `notebooks/figures/capstone/` with a descriptive name.
4. Reference from `build_pptx.py` via `_full_figure_slide()` or
   `_content_slide()`.

#### Image DPI and resolution

For a 16:9 slide displayed at 1920×1080:

| Image width on slide | Recommended pixel width |
|---------------------|------------------------|
| Full width (11 in) | 2200 px (200 DPI) |
| Half width (5.5 in) | 1100 px (200 DPI) |
| Quarter width (2.75 in) | 825 px (300 DPI) |

Use `dpi=200` or higher when saving from matplotlib.  PNGs are preferred
over JPEGs for scientific figures (lossless, transparent background support).

---

### 3. Mathematics (LaTeX-style)

PowerPoint does not natively render LaTeX.  There are three practical
approaches, from simplest to most flexible:

#### Approach A: Unicode mathematical symbols (used in this script)

Python source files support Unicode directly.  This is the simplest approach
and works everywhere (PowerPoint, Keynote, Google Slides):

```python
# Greek letters
"\u03b1"  # α    "\u03b2"  # β    "\u03b3"  # γ    "\u03b4"  # δ
"\u03b5"  # ε    "\u03b8"  # θ    "\u03ba"  # κ    "\u03bb"  # λ
"\u03bc"  # μ    "\u03c0"  # π    "\u03c1"  # ρ    "\u03c3"  # σ
"\u03c6"  # φ    "\u03c8"  # ψ    "\u03c9"  # ω    "\u0394"  # Δ
"\u03a9"  # Ω    "\u03b6"  # ζ

# Operators and relations
"\u2207"  # ∇ (nabla)          "\u2202"  # ∂ (partial)
"\u222b"  # ∫ (integral)       "\u2211"  # ∑ (sum)
"\u221a"  # √ (sqrt)           "\u00b7"  # · (middle dot)
"\u00d7"  # × (times)          "\u2248"  # ≈ (approx)
"\u2260"  # ≠ (not equal)      "\u2264"  # ≤ (leq)
"\u2265"  # ≥ (geq)            "\u221e"  # ∞ (infinity)
"\u2192"  # → (rightarrow)     "\u2190"  # ← (leftarrow)
"\u21d2"  # ⇒ (Rightarrow)     "\u2208"  # ∈ (in)

# Subscripts and superscripts (limited set in Unicode)
"\u2080"  # ₀    "\u2081"  # ₁    "\u2082"  # ₂    "\u2083"  # ₃
"\u1d62"  # ᵢ    "\u2c7c"  # ⱼ    "\u2099"  # ₙ
"\u00b2"  # ²    "\u00b3"  # ³

# Set notation
"\u2282"  # ⊂    "\u222a"  # ∪    "\u2229"  # ∩    "\u2205"  # ∅

# Example: the momentum equation
"\u2207 \u00b7 \u03c3(u, \u03b8) + b = \u03c1 \u00fc"
# renders as: ∇ · σ(u, θ) + b = ρ ü
```

**Tip:** Use the `Cambria Math` font for runs that contain mathematical
symbols — it has the widest Unicode math coverage of any standard Windows
font:

```python
run = p.add_run()
run.text = "∇ · σ(u, θ) + b = ρ ü"
run.font.name = "Cambria Math"
run.font.size = Pt(24)
```

#### Approach B: Render LaTeX to PNG and embed as image

For complex expressions (fractions, matrices, integrals with limits), render
the LaTeX to a transparent PNG and insert it as an image:

```python
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from pptx.util import Inches
import io

def _latex_to_image(latex: str, fontsize: int = 28,
                    dpi: int = 300) -> io.BytesIO:
    """Render a LaTeX string to a transparent PNG in memory."""
    fig, ax = plt.subplots(figsize=(0.01, 0.01))
    ax.axis("off")
    fig.patch.set_alpha(0.0)
    text = ax.text(0, 0, f"${latex}$",
                   fontsize=fontsize, color="black",
                   ha="left", va="baseline",
                   transform=ax.transAxes)

    # Tight bounding box around the rendered text
    fig.canvas.draw()
    bbox = text.get_window_extent(fig.canvas.get_renderer())
    bbox = bbox.expanded(1.15, 1.3)  # small padding
    bbox_inches = bbox.transformed(fig.dpi_scale_trans.inverted())

    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=dpi, bbox_inches=bbox_inches,
                transparent=True)
    plt.close(fig)
    buf.seek(0)
    return buf

def _add_latex(slide, latex: str, left, top, width, *,
               fontsize: int = 28, dpi: int = 300):
    """Place rendered LaTeX on a slide as a PNG image."""
    buf = _latex_to_image(latex, fontsize=fontsize, dpi=dpi)
    slide.shapes.add_picture(buf, left, top, width=width)
    buf.close()
```

**Usage:**

```python
# Weak form of the momentum equation
_add_latex(slide,
    r"\int_{\Omega} \mathbf{P}(\mathbf{u}) : \nabla \delta\mathbf{v} "
    r"\, d\Omega = \int_{\Omega} \mathbf{b} \cdot \delta\mathbf{v} "
    r"\, d\Omega",
    Inches(1.5), Inches(3.0), Inches(10),
    fontsize=32)

# Neo-Hookean + Holzapfel strain energy
_add_latex(slide,
    r"\Psi = \frac{\mu}{2}(I_1 - 3) + \frac{k_1}{2k_2}"
    r"\left(e^{k_2(I_4 - 1)^2} - 1\right)",
    Inches(2.0), Inches(4.5), Inches(9))

# Matrix expression
_add_latex(slide,
    r"\mathbf{C} = \begin{bmatrix} c_{11} & c_{12} \\ "
    r"c_{21} & c_{22} \end{bmatrix}",
    Inches(4.0), Inches(2.5), Inches(5))
```

**LaTeX rendering tips:**

- Matplotlib uses its own `mathtext` engine by default.  For full LaTeX
  support (e.g. `\bm`, `\mathbb`, AMS environments), set
  `plt.rcParams["text.usetex"] = True` — this requires a local LaTeX
  installation.
- Use `transparent=True` so the equation floats over the slide background.
- Render at 300 DPI for print-quality slides.
- For dark backgrounds, pass `color="white"` to `ax.text()`.

#### Approach C: PowerPoint's native equation editor (OOXML)

PowerPoint supports OOXML math markup.  This is the most complex approach
but produces editable equations inside the `.pptx`:

```python
from lxml import etree

NSMAP = {
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "m": "http://schemas.openxmlformats.org/officeDocument/2006/math",
}

def _add_ooxml_equation(slide, left, top, width, height, mathml_xml: str):
    """
    Insert an OOXML math paragraph into a text box.

    mathml_xml should be a valid <m:oMath> element string.
    """
    txBox = slide.shapes.add_textbox(left, top, width, height)
    tf = txBox.text_frame
    p = tf.paragraphs[0]._p  # lxml element

    # Parse and insert the math element
    math_elem = etree.fromstring(mathml_xml)
    p.append(math_elem)
    return txBox
```

**Example OOXML for** `∇ · σ`:

```xml
<m:oMath xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
  <m:r><m:t>∇</m:t></m:r>
  <m:r><m:t> · </m:t></m:r>
  <m:r><m:rPr><m:sty m:val="bi"/></m:rPr><m:t>σ</m:t></m:r>
</m:oMath>
```

This approach is verbose but produces equations that are **editable in
PowerPoint** (right-click → Edit Equation).

**Recommendation:** For this project, **Approach A** (Unicode) handles most
needs (Greek letters, arrows, subscripts).  Use **Approach B** (LaTeX→PNG)
for complex expressions like the weak form or constitutive model.  Reserve
**Approach C** only if you need editable equations in the final `.pptx`.

---

### 4. Mixed formatting within a single text box

To combine regular text, bold, italic, coloured, or different-sized text on
the same line, use multiple **runs** within a paragraph:

```python
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor

txBox = slide.shapes.add_textbox(Inches(1), Inches(2), Inches(10), Inches(1))
tf = txBox.text_frame
p = tf.paragraphs[0]

# Run 1: normal text
r1 = p.add_run()
r1.text = "Tumor volume: "
r1.font.size = Pt(20)

# Run 2: bold + red
r2 = p.add_run()
r2.text = "50.2 cm³"
r2.font.size = Pt(20)
r2.font.bold = True
r2.font.color.rgb = RGBColor(0xCC, 0x33, 0x33)

# Run 3: grey annotation
r3 = p.add_run()
r3.text = " (manual segmentation)"
r3.font.size = Pt(16)
r3.font.color.rgb = RGBColor(0x88, 0x88, 0x88)
```

---

### 5. Hyperlinks

```python
r = p.add_run()
r.text = "OpenNeuro ds002080"
r.font.size = Pt(18)
r.font.color.rgb = RGBColor(0x33, 0x66, 0xCC)
r.font.underline = True
r.hyperlink.address = "https://openneuro.org/datasets/ds002080"
```

---

### 6. Slide numbering

For automatic slide numbers in the bottom-right corner:

```python
from pptx.oxml.ns import qn
from lxml import etree

def _add_slide_number(slide, left, top, width, height, color=CLR_MED_GRAY):
    txBox = slide.shapes.add_textbox(left, top, width, height)
    tf = txBox.text_frame
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.RIGHT

    # Insert a field code for slide number
    fld = etree.SubElement(p._p, qn("a:fld"),
                           attrib={"type": "slidenum"})
    rPr = etree.SubElement(fld, qn("a:rPr"), lang="en-US", dirty="0")
    rPr.set("sz", str(int(Pt(12))))
    t = etree.SubElement(fld, qn("a:t"))
    t.text = "<#>"

    return txBox
```

---

### 7. Workflow summary

```
┌──────────────────────────────────────────────────────────┐
│ 1. Run capstone notebooks → figures saved to             │
│    notebooks/figures/capstone/                           │
│                                                          │
│ 2. Capture Freeview screenshots → save to same dir       │
│                                                          │
│ 3. Edit build_pptx.py:                                   │
│    - Add/remove slides in build_cNN() functions          │
│    - Reference new figures by filename                   │
│    - Add speaker notes                                   │
│                                                          │
│ 4. python beamer/build_pptx.py                           │
│                                                          │
│ 5. Open .pptx in PowerPoint/Keynote/Google Slides        │
│    - Fine-tune alignment, animations, transitions        │
│    - Add live demo slides or video links                 │
│                                                          │
│ 6. Iterate: re-run step 4 to regenerate from source      │
└──────────────────────────────────────────────────────────┘
```

### 8. Useful python-pptx references

- [python-pptx documentation](https://python-pptx.readthedocs.io/)
- [API reference — shapes](https://python-pptx.readthedocs.io/en/latest/api/shapes.html)
- [API reference — table](https://python-pptx.readthedocs.io/en/latest/api/table.html)
- [Working with text](https://python-pptx.readthedocs.io/en/latest/user/text.html)
- [OOXML math spec (ECMA-376)](https://ecma-international.org/publications-and-standards/standards/ecma-376/)
- [Unicode math symbols](https://en.wikipedia.org/wiki/Mathematical_operators_and_symbols_in_Unicode)

## Beamer deck (LaTeX)

The original Beamer presentation remains in `main.tex` with sections in
`sections/`.  Build with:

```bash
cd beamer && make pdf   # or: latexmk -pdf main.tex
```

Both the Beamer and PPTX decks share the same colour palette and figure
sources, so they stay visually consistent.
