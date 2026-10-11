# Google Slides: Freeview Illustrations

This folder holds high-resolution image exports from a companion Google
Slides deck used to supplement the Beamer presentation with Freeview
screenshots and interactive visualizations.

## Workflow

1. **Source deck:** Maintain a single Google Slides presentation with
   all Freeview-based illustrations. Each slide contains one illustration
   with a descriptive title.

2. **Export format:** Download individual slides as **PNG** (high
   resolution: File > Download > PNG image) or as a full-deck **PDF**
   for archival.

3. **Place exports here:** Save PNG files into this `gslides/` folder
   using the naming convention below.

4. **Reference from Beamer:** Include in slides via
   `\includegraphics{gslides/FV-NN_description.png}` -- the
   `\graphicspath` in `preamble.tex` already includes this directory.

## Naming Convention

```
FV-NN_short_description.png
```

where `NN` is a zero-padded sequence number matching the Beamer figure
slot.

| ID | Description | Beamer section |
|----|-------------|----------------|
| FV-01 | T1w showing glioma mass effect | 03 Neuro-oncology |
| FV-02 | Pre-op vs post-op T1w overlay | 03 Neuro-oncology |
| FV-03 | FreeSurfer aparc+aseg overlay | 04 mpMRI |
| FV-04 | FA map and tractography overlay | 04 mpMRI |
| FV-05 | BOLD signal and FC matrix | 04 mpMRI |
| FV-06 | FreeSurfer segmentation QC | 06 Pipeline |
| FV-07 | fMRIPrep SDC + registration QC | 06 Pipeline |
| FV-08 | QSIPrep distortion correction | 06 Pipeline |
| FV-09 | Tractography and fODF glyphs | 06 Pipeline |
| FV-10 | Cavity mask overlay on post-op T1w | 07 Longitudinal |
| FV-11 | Warped pre-op T1w alignment | 07 Longitudinal |
| FV-12 | SC vs FC matrices (pre-op) | 08 Digital twin |
| FV-13 | Displacement magnitude map | 10 Results |
| FV-14 | Jacobian determinant map | 10 Results |
| FV-15 | Delta-SC and delta-FC matrices | 10 Results |
| FV-16 | Tumor mask vs cavity mask comparison | 07 Longitudinal |

## Dynamic Content

For animated Freeview walkthroughs or screen recordings:

- Export as MP4 or GIF
- Link from the Google Slides deck (Insert > Video)
- In the Beamer presentation, reference the Google Slides deck or show
  the video live during the talk

## Existing Google Slides Presentations

Prior presentations by the author (not distributed in this repository):

- CAS Brain Mechanics opening conference, Oslo, 20-22 Aug 2025
- "From Gliomas to PD: AI-driven Neuroimaging Pipelines", Dezhou, 18 Nov 2025

## Freeview Scripts

The repository contains Freeview launch scripts that produce the
visualizations to capture:

| Script | Content |
|--------|---------|
| `scripts/freeview_preop.sh` | Pre-op T1w + overlays |
| `scripts/freeview_postop.sh` | Post-op T1w + overlays |
| `scripts/freeview_preop_postop.sh` | Side-by-side comparison |
| `scripts/freeview_deformation.sh` | Displacement + Jacobian maps |
| `scripts/freeview_resseg.sh` | RESSEG cavity segmentation QC |
| `scripts/freeview_tumor_vs_cavity.sh` | Tumor vs cavity (side-by-side or overlay) |
