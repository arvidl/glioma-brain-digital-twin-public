# Processing Pipeline

This document describes the full processing pipeline for the Glioma Brain Digital Twin project -- from raw BIDS-formatted MRI acquisitions to TVB-ready connectivity matrices and derived parameter maps.

## Overview

```
Raw BIDS data (T1w, DWI AP+PA, rs-fMRI)
        │
        │  For each subject (PAT16) x session (preop, postop):
        │
        ├── Step 1: FreeSurfer recon-all ──────────── cortical parcellation
        │       (scripts/run_freesurfer.sh)           (~2-3 h per run)
        │
        ├── Step 2: fMRIPrep BOLD preprocessing ──── preprocessed BOLD
        │       (scripts/run_fmriprep.sh)             (~1-2 h, parallel w/ Step 3)
        │
        ├── Step 3: QSIPrep DWI preprocessing ────── preprocessed DWI
        │       (scripts/run_qsiprep.sh)              (~2-4 h, parallel w/ Step 2)
        │
        ├── Step 4: MRtrix3 CSD + tractography ──── fODFs + tractogram
        │       (scripts/run_mrtrix_recon.sh)         (~1-2 h per run)
        │
        ├── Step 5: Co-register to T1w space ──────── unified coordinate frame
        │       (scripts/register_to_t1w.sh)          (~10 min per run)
        │
        ├── Step 5b: Longitudinal registration ──────── deformation fields
        │       (scripts/register_longitudinal.sh)      (~30-90 min per subject)
        │
        ├── Step 6: Pre-op vs post-op comparison ──── longitudinal analysis
        │       (scripts/compare_preop_postop.py)      (~5 min per subject)
        │
        ├── Step 7: Structural connectivity ──────── SC matrices
        │       (scripts/compute_tvb_connectome.py)    (~30 s per session)
        │
        ├── Step 8: Functional connectivity ──────── FC matrices + ROI time series
        │       (scripts/compute_fc.py)                (~30 s per session)
        │
        └── Step 9: rsHRF estimation ────────────── HRF parameter maps
                (scripts/compute_rshrf.py)             (~30 s per session)

        │
        ▼
derivatives/freesurfer/      ── surfaces, segmentations, label maps
derivatives/fmriprep/        ── preprocessed BOLD (T1w + MNI space)
derivatives/qsiprep/         ── preprocessed DWI (T1w space)
derivatives/mrtrix_recon/    ── CSD, DTI maps, tractography
derivatives/registered_t1w/  ── all modalities in native T1w space
derivatives/connectivity/    ── SC (sc_sift2, sc_dk84) + FC (pearson, fisher_z)
derivatives/TVB/             ── SC.csv, SC_normalised.csv
derivatives/rsHRF/           ── voxel-wise FWHM, Height, Time2peak (pipeline-computed)
```

### Master Orchestration

```bash
bash scripts/run_pipeline.sh --parallel --threads 8

# Process a single subject/session:
bash scripts/run_pipeline.sh --subjects PAT16 --sessions preop --threads 8
```

## External Inputs

The pipeline is **fully self-contained**.  Only two external inputs are required:

| Input | Location | Source |
|---|---|---|
| Raw BIDS NIfTI files | `data/BIDS_preop_postop/sub-PAT16/` | Pre-op + post-op MRI recordings |
| Tumor delineation | `data/BIDS_preop_postop/derivatives/tumor_masks/sub-PAT16/` | Aerts method (binary mask) |

Everything else (FreeSurfer, fMRIPrep, QSIPrep, MRtrix3, RESSEG, SC, FC, rsHRF) is computed by the pipeline scripts.

### Reference Data in the Release

The data release also ships with **pre-computed derivatives** from independent processing (for comparison / Track A notebooks):

| Derivative | Location | Notes |
|---|---|---|
| Structural connectivity (SC) | `data/.../derivatives/TVB/sub-PAT16/ses-preop/SCthrAn.mat` | Pre-computed reference |
| Functional connectivity (FC) | `data/.../derivatives/TVB/sub-PAT16/ses-preop/FC.mat` | Pre-computed reference |
| ROI BOLD time series | `data/.../derivatives/TVB/sub-PAT16/ses-preop/ROIts.dat` | Pre-computed reference |
| rsHRF maps | `data/.../derivatives/rsHRF/sub-PAT16/` | Pre-computed with rsHRF BIDS App |

Track A notebooks (NB04-NB08) can use either the data-release reference or the pipeline-computed derivatives.  Track B notebooks (NB15-NB17) use pipeline-computed outputs exclusively.

## Data Formats

| File | Format | Dimensions | Description |
|---|---|---|---|
| `SCthrAn.mat` | MATLAB v5 | (N×N) | Thresholded & normalised structural connectivity |
| `FC.mat` | MATLAB/Octave | (N×N) | Functional connectivity (Pearson correlation of BOLD) |
| `ROIts.dat` | plain text | (T×N) | BOLD time series per ROI (T=180 time points) |
| `HRF.csv` | CSV | (24800×N_hrf) | Estimated HRF per ROI (~24.8 s at 1 ms resolution) |
| `SC.zip` | TVB-format zip | varies | Structural connectivity in TVB import format |
| `*_FWHM.nii.gz` | NIfTI | 3D volume | Full-width at half-maximum of rsHRF |
| `*_Height.nii.gz` | NIfTI | 3D volume | Peak height of rsHRF |
| `*_Time2peak.nii.gz` | NIfTI | 3D volume | Time-to-peak of rsHRF |
| `*_label-tumor.nii.gz` | NIfTI (gzipped) | 3D volume | Binary tumor segmentation mask |

---

## Step-by-Step: Reproducing Derivatives from Raw Data

The steps below are only needed if you want to regenerate the derivatives from scratch (e.g. for new subjects or with different parameters).

### Prerequisites

| Software | Version | Purpose |
|---|---|---|
| [FreeSurfer](https://surfer.nmr.mgh.harvard.edu/) | 8.1.0 | Cortical parcellation, segmentation |
| [fMRIPrep](https://fmriprep.org/) | 25.2.4 | BOLD preprocessing (conda `cas-fmriprep`) |
| [QSIPrep](https://qsiprep.readthedocs.io/) | 1.1.1 | DWI preprocessing (conda `cas-qsiprep`) |
| [MRtrix3](https://www.mrtrix.org/) | 3.0.8 | CSD, tractography, connectome |
| [FSL](https://fsl.fmrib.ox.ac.uk/) | 6.0.7.19 | Registration, eddy correction |
| [AFNI](https://afni.nimh.nih.gov/) | 26.0.09 | fMRI utilities |
| [ANTs](http://stnava.github.io/ANTs/) | ≥2.5 | Registration, bias correction |
| [Connectome Workbench](https://www.humanconnectome.org/) | 2.1.0 | Surface-based analysis |
| [rsHRF toolbox](https://github.com/BIDS-Apps/rsHRF) | latest | Resting-state HRF estimation |
| Python 3.11+ | | Connectome assembly, analysis |

### Step 1: FreeSurfer Cortical Reconstruction

**What it produces:** Cortical surfaces, Desikan-Killiany parcellation (`aparc+aseg.mgz`), subcortical segmentation, plus additional segmentations (brainstem, thalamic nuclei, hippocampal subfields).

**Script:** `scripts/run_freesurfer.sh`

```bash
bash scripts/run_freesurfer.sh \
    --subject PAT16 \
    --session preop \
    --threads 8
```

**Input:** T1-weighted NIfTI (`sub-PAT16_ses-preop_T1w.nii.gz`)

**Output:** `derivatives/freesurfer/sub-PAT16_ses-preop/` containing `mri/`, `surf/`, `label/`, `stats/`

**Estimated time:** ~2-3 hours per run (FreeSurfer 8.1.0 on M4 Max with 8 threads)

**Notes:**
- Requires `FREESURFER_HOME` to be set and `SetUpFreeSurfer.sh` sourced
- Additional segmentations require Matlab Runtime R2019b (`fs_install_mcr R2019b`)
- Use `--extra-seg-only` to re-run additional segmentations without repeating recon-all
- Repeat for each subject x session combination

### Step 2: fMRIPrep BOLD Preprocessing

**What it produces:** Preprocessed resting-state BOLD in T1w and MNI space, confound regressors, brain masks.

**Script:** `scripts/run_fmriprep.sh`

```bash
bash scripts/run_fmriprep.sh \
    --subject PAT16 \
    --session preop \
    --nthreads 8 --mem-mb 16000
```

**Output:** `derivatives/fmriprep/sub-PAT16/ses-preop/{anat,func}/`

**Estimated time:** ~1-2 hours per run

**Notes:**
- Uses SyN fieldmap-less distortion correction (single-PE BOLD)
- Outputs in T1w space (for brain mechanics) and MNI152NLin2009cAsym (for reporting)
- Reuses FreeSurfer output from Step 1 if available (skips internal recon-all)
- Requires the `cas-fmriprep` conda environment
- Can run in parallel with Step 3 (QSIPrep)
- For multi-session BIDS datasets, the script creates a temporary session-specific
  BIDS view (symlinks) to work around an fMRIPrep 25.x session-discovery conflict

### Step 3: QSIPrep DWI Preprocessing

**What it produces:** Preprocessed DWI at 1.0 mm resolution in T1w-aligned (ACPC) space, with rotated b-values/b-vectors.

**Script:** `scripts/run_qsiprep.sh`

```bash
bash scripts/run_qsiprep.sh \
    --subject PAT16 \
    --session preop \
    --nthreads 8 --mem-mb 16000
```

**Output:** `derivatives/qsiprep/sub-PAT16/ses-preop/dwi/`

**Estimated time:** ~2-4 hours per run

**Notes:**
- Uses reverse phase-encoding (AP+PA) b0 pairs for proper susceptibility distortion correction
- Output resolution 1.0 mm matches T1w grid (avoids double interpolation at FE mesh stage)
- Requires the `cas-qsiprep` conda environment
- Can run in parallel with Step 2 (fMRIPrep)
- Use `--recon` flag to automatically trigger MRtrix3 reconstruction (Step 4)

### Step 4: MRtrix3 Reconstruction (CSD + DTI + Tractography)

**What it produces:** Fibre orientation distributions, DTI scalar maps, whole-brain tractogram, SIFT2 weights.

**Script:** `scripts/run_mrtrix_recon.sh`

```bash
bash scripts/run_mrtrix_recon.sh \
    --subject PAT16 \
    --session preop \
    --nthreads 8 --streamlines 10000000
```

**Processing steps:**

| # | Step | MRtrix3 Command | Output |
|---|---|---|---|
| 1 | Convert to MIF (with b-value rounding) | `mrconvert` | `dwi.mif` |
| 2 | Response function estimation | `dwi2response dhollander` | `{wm,gm,csf}_response.txt` |
| 3 | Multi-tissue CSD + normalization | `dwi2fod msmt_csd` + `mtnormalise` | `{wm,gm,csf}_fod_norm.mif` |
| 4 | DTI fitting + scalar maps | `dwi2tensor` + `tensor2metric` | `fa/md/ad/rd.nii.gz` |
| 5 | Tractography (iFOD2) | `tckgen` | `whole_brain.tck` |
| 6 | SIFT2 filtering | `tcksift2` | `sift2_weights.txt` |

**Input:** QSIPrep-preprocessed DWI from Step 3

**Output:** `derivatives/mrtrix_recon/sub-PAT16/ses-preop/`

**Estimated time:** ~1-2 hours per run (10M streamlines)

**Disk space:** ~5-10 GB per run (tractogram dominates)

### Step 5: Co-register All to T1w Space

**What it produces:** All modalities (DTI maps, fODs, tractography, FreeSurfer segmentations) in the fMRIPrep native T1w coordinate frame.

**Script:** `scripts/register_to_t1w.sh`

```bash
bash scripts/register_to_t1w.sh \
    --subject PAT16 \
    --session preop \
    --nthreads 8
```

**Processing steps:**

| # | Step | Tools | Output |
|---|---|---|---|
| 1 | Rigid ACPC -> T1w registration | FLIRT | `transforms/acpc_to_t1w_flirt.mat` |
| 2 | Register DTI scalar maps | FLIRT | `{fa,md,ad,rd}_space-T1w.nii.gz` |
| 3 | Register fODs (with SH reorientation) | mrtransform | `{wm,gm,csf}_fod_norm_space-T1w.mif` |
| 4 | Transform tractography | transform_tck.py | `whole_brain_space-T1w.tck` |
| 5 | Convert FreeSurfer volumes | mri_convert + ANTs | `aparc+aseg_space-T1w.nii.gz` |
| 6 | (Optional) BOLD resampling | fMRIPrep | T1w-space BOLD |

**Output:** `derivatives/registered_t1w/sub-PAT16/ses-preop/`

**Estimated time:** ~10 minutes

### Step 7: Structural Connectivity

**What it produces:** TVB-ready SC matrix (SIFT2-weighted streamline counts) + DK-84 submatrix.

**Script:** `scripts/compute_tvb_connectome.py`

```bash
python scripts/compute_tvb_connectome.py \
    --tck derivatives/registered_t1w/sub-PAT16/ses-preop/whole_brain_space-T1w.tck \
    --parc derivatives/registered_t1w/sub-PAT16/ses-preop/aparc+aseg_space-T1w.nii.gz \
    --weights derivatives/registered_t1w/sub-PAT16/ses-preop/sift2_weights.txt \
    --out derivatives/TVB/sub-PAT16/ses-preop/SC.csv
```

**Output:** `SC.csv`, `SC_normalised.csv` (TVB), plus `sc_sift2.npy`, `sc_dk84.npy` (NB16/NB17) in `derivatives/connectivity/`.

**Estimated time:** ~30 seconds per session

### Step 8: Functional Connectivity and ROI Time Series

**What it produces:** FC matrix (Pearson correlation + Fisher z-transform), cleaned ROI BOLD time series.

**Script:** `scripts/compute_fc.py`

```bash
python scripts/compute_fc.py --subject PAT16 --project-dir .
```

Processing: confound regression (6 motion + derivatives, 5 aCompCor, 3 cosine drift), bandpass 0.01-0.1 Hz, scrubbing FD > 0.5 mm, Pearson correlation.

**Output:** `derivatives/connectivity/sub-PAT16/ses-{preop,postop}/`
- `fc_pearson.npy`, `fc_fisher_z.npy` -- FC matrices
- `roi_timeseries.npy` -- cleaned ROI time series
- `fc_roi_names.json` -- ROI labels (82 DK cortical + subcortical)

**Estimated time:** ~30 seconds per session

### Step 9: rsHRF Parameter Estimation

**What it produces:** Voxel-wise HRF parameter maps (FWHM, Height, Time-to-peak).

**Script:** `scripts/compute_rshrf.py`

Implements point-process deconvolution (Wu et al. 2013) -- a self-contained replacement for the external rsHRF BIDS App. No additional dependencies beyond scipy/numpy/nibabel.

```bash
python scripts/compute_rshrf.py --subject PAT16 --project-dir .
```

**Output:** `derivatives/rsHRF/sub-PAT16/` -- `*_FWHM.nii.gz`, `*_Height.nii.gz`, `*_Time2peak.nii.gz`

**Estimated time:** ~30 seconds per session

### Tumor Segmentation (External Input)

**What it produces:** Binary tumor masks in native (T1) and standard (MNI) space.

Tumor segmentation is typically done:
- **Manually** using ITK-SNAP or 3D Slicer (gold standard)
- **Semi-automatically** using tools like HD-GLIO or BraTS-toolkit
- **Automatically** using deep learning models (e.g. nnU-Net trained on BraTS)

The masks provided in this dataset were manually segmented by a neuroradiologist.

---

## Complete Pipeline: Recommended Order

For each subject x session combination, run the steps in this order:

```
1. FreeSurfer recon-all          (Step 1)   ~2-3 h
          ↓
     ┌────┴────┐
2. fMRIPrep   3. QSIPrep        (Steps 2+3) ~2-4 h  [run in parallel]
     └────┬────┘
          ↓
4. MRtrix3 reconstruction       (Step 4)   ~1-2 h   [requires Step 3]
          ↓
5. Co-register to T1w space     (Step 5)   ~10 min  [requires Steps 1-4]
          ↓
5b. Longitudinal registration   (Step 5b)  ~30-90 min [ANTs SyN + RESSEG]
          ↓
6. Pre-op vs post-op comparison (Step 6)   ~5 min   [requires Steps 5, 5b]
          ↓
7. SC  8. FC  9. rsHRF          (Steps 7-9) ~2 min  [requires Steps 2-5]
```

**Total wall-clock time:** ~6-12 hours per subject x session (dominated by Steps 1-4). Steps 7-9 add only ~2 minutes.

**Parallelisation tip:** Steps 2 and 3 reuse FreeSurfer output and can run simultaneously.
Within the same step, different subject/session combinations can also run in parallel on a multi-core machine.

**Master orchestration:**
```bash
bash scripts/run_pipeline.sh --parallel --threads 8 --mem-mb 16000
```

---

## Notebook Dependencies

Which derivatives each notebook requires:

| Notebook | Requires | Fallback |
|---|---|---|
| NB01 (BIDS Exploration) | Raw BIDS data | Metadata only |
| NB02 (Structural MRI) | T1w NIfTI | --- |
| NB03 (Diffusion MRI) | DWI NIfTI | --- |
| NB04 (Functional MRI) | rsHRF maps (pipeline or data release) | Synthetic simulation |
| NB05 (Connectivity) | SC + FC (pipeline or data release) | Synthetic Watts-Strogatz |
| NB06 (Tumor Impact) | Tumor masks, FC, rsHRF maps | Simulated volumes/maps |
| NB07 (Brain Mechanics) | None (pure computation) | Analytical + synthetic FEM |
| NB08 (Digital Twin) | SC, FC, tumor masks | Synthetic networks |
| NB15 (Pipeline FC) | fMRIPrep BOLD + aparc+aseg (Steps 2, 5) | --- |
| NB16 (Pipeline SC) | MRtrix3 tractography + SIFT2 (Steps 4, 5) | --- |
| NB17 (Longitudinal) | SC + FC from NB15-NB16 | --- |

Track A notebooks (NB04-NB08) detect whether real derivatives exist and load them automatically; they fall back to synthetic data when missing.  Track B notebooks (NB15-NB17) require the pipeline to have been run.

---

## Troubleshooting

### Missing DWI NIfTI files
The raw DWI NIfTI files (~100+ MB each) are not tracked in git. Download them via:
```bash
python data/download_data.py
```

### MRtrix3 not installed
Install via conda:
```bash
conda install -c mrtrix3 mrtrix3
```

### FreeSurfer license
FreeSurfer requires a license file (`license.txt`). Obtain one free at:
https://surfer.nmr.mgh.harvard.edu/registration.html

### Post-operative TVB limitations
Post-operative TVB derivatives for **PAT16** are unavailable due to susceptibility artifacts from the resection cavity (air-tissue interface).
