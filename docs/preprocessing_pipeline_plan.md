# Glioma Multi-Subject Multi-Timepoint Preprocessing Pipeline

**Project**: Glioma Brain Digital Twin  
**Date**: March 3, 2026  
**Status**: Implementation plan

---

## 1. Motivation

This project extends the single-subject, single-timepoint MRI processing pipeline
developed for the [CAS Brain Mechanics Workshop (Finse 2026)](https://github.com/arvidl/brain-digital-twin-finse2026)
to a **multi-timepoint** glioma dataset. The goal is to produce
fully preprocessed and co-registered multimodal MRI derivatives for one brain
tumor patient (sub-PAT16), enabling pre-operative vs post-operative comparison in the
context of *mathematical challenges in brain mechanics*.

## 2. Data

### 2.1 Subjects and Sessions

| Subject | Session | T1w | DWI (AP+PA) | rs-fMRI | Tumor Mask |
|---------|---------|-----|-------------|---------|------------|
| PAT16   | preop   | yes | yes         | yes     | yes        |
| PAT16   | postop  | yes | yes         | yes     | yes        |

**Total**: 2 subject x session combinations to process.

### 2.2 BIDS Layout

```
data/BIDS_preop_postop/
  sub-PAT16/
    ses-preop/
      anat/   sub-PAT16_ses-preop_T1w.{nii.gz,json}
      dwi/    sub-PAT16_ses-preop_acq-{AP,PA}_dwi.{nii.gz,bval,bvec,json}
      func/   sub-PAT16_ses-preop_task-rest_bold.{nii.gz,json}
    ses-postop/
      anat/   sub-PAT16_ses-postop_T1w.{nii.gz,json}
      dwi/    sub-PAT16_ses-postop_acq-{AP,PA}_dwi.{nii.gz,bval,bvec,json}
      func/   sub-PAT16_ses-postop_task-rest_bold.{nii.gz,json}
```

### 2.3 Known Caveats

- **PAT16 postop**: Susceptibility artifacts from the resection cavity
  (air-tissue interface) may degrade DWI and fMRI preprocessing quality.
  The pipeline will warn but proceed; QC inspection is critical.
- **Single-PE fMRI**: BOLD acquisitions have only AP phase encoding; fMRIPrep
  will use SyN-based fieldmap-less distortion correction.
- **Dual-PE DWI**: Both AP and PA DWI acquisitions are available, enabling
  proper susceptibility distortion correction in QSIPrep.

## 3. Software Environment

| Tool                 | Version          | Notes                              |
|----------------------|------------------|------------------------------------|
| FreeSurfer           | 8.1.0            | Native ARM64                       |
| FSL                  | 6.0.7.19         | Official installer                 |
| AFNI                 | 26.0.09          | Built from source                  |
| MRtrix3              | 3.0.8            | Built from source (bundled Eigen)  |
| Connectome Workbench | 2.1.0            | Built from source (Qt 6)           |
| DSI Studio           | Hou (2025.04.16) | Official ARM64 build               |
| fMRIPrep             | 25.2.4           | conda env `cas-fmriprep`           |
| QSIPrep              | 1.1.1            | conda env `cas-qsiprep`            |
| ANTs                 | >= 2.5           | `finse26` env: `conda install -c conda-forge ants` |

### 3.1 Conda Environments

Three separate environments are required due to dependency conflicts:

| Environment      | File                              | Purpose                        |
|------------------|-----------------------------------|--------------------------------|
| `finse26`        | `environment/environment.yml`     | General analysis, notebooks    |
| `cas-fmriprep`   | `environment/environment_fmriprep.yml` | fMRIPrep BOLD preprocessing |
| `cas-qsiprep`    | `environment/environment_qsiprep.yml`  | QSIPrep DWI preprocessing   |

## 4. Pipeline Architecture

```
Raw BIDS data (T1w, DWI AP+PA, rs-fMRI)
     |
     |  For each subject x session:
     |
     +---> Step 1: FreeSurfer segmentation                       (~1-8 h)
     |         scripts/run_freesurfer.sh (standard, pre-op)
     |         scripts/run_freesurfer_clinical.sh (clinical, post-op)
     |         Output: derivatives/freesurfer/sub-{SUB}_ses-{SES}/
     |
     +---> Step 2: fMRIPrep BOLD preprocessing  (parallel w/ Step 3)  (~1-2 h)
     |         scripts/run_fmriprep.sh
     |         Requires: FreeSurfer output from Step 1
     |         Output: derivatives/fmriprep/sub-{SUB}/ses-{SES}/
     |
     +---> Step 3: QSIPrep DWI preprocessing    (parallel w/ Step 2)  (~2-4 h)
     |         scripts/run_qsiprep.sh
     |         Output: derivatives/qsiprep/sub-{SUB}/ses-{SES}/
     |
     +---> Step 4: MRtrix3 CSD + tractography                        (~1-2 h)
     |         scripts/run_mrtrix_recon.sh
     |         Requires: QSIPrep preprocessed DWI
     |         Output: derivatives/mrtrix_recon/sub-{SUB}/ses-{SES}/
     |
     +---> Step 5: Co-register all to T1w space                      (~10 min)
              scripts/register_to_t1w.sh
              Requires: Steps 1-4
              Output: derivatives/registered_t1w/sub-{SUB}/ses-{SES}/

     Then, per subject:
     +---> Step 5b: Longitudinal registration (ANTs SyN)             (~30-90 min)
              scripts/register_longitudinal.sh
              Requires: Step 5 outputs for both sessions
              Output: derivatives/registered_t1w/sub-{SUB}/longitudinal/

     +---> Step 6: Pre-op vs Post-op comparison
              scripts/compare_preop_postop.py
              (uses warped pre-op data from Step 5b when available)
```

**Total wall-clock time**: ~6-12 hours per subject x session
(Steps 2 and 3 run in parallel; 4 combinations = ~24-48h total).

## 5. Step-by-Step Details

### Step 1: FreeSurfer Segmentation

Two scripts are available, selected automatically by `--clinical-postop`.
Both scripts detect already-completed runs (by checking for `aparc+aseg.mgz`)
and skip them, so the pipeline is safe to re-run without redoing finished work.

#### Standard recon-all
**Script**: `scripts/run_freesurfer.sh --subject PAT16 --session preop`

**Processing**:
- `recon-all -all` with 8 threads on the T1w volume
- Additional segmentations (requires Matlab Runtime R2019b):
  - Brainstem substructures (`segmentBS.sh`)
  - Thalamic nuclei (`segmentThalamicNuclei.sh`)
  - Hippocampal subfields (`segmentHA_T1.sh`)

**Best for**: Pre-op sessions with mild/diffuse tumors (better cortical thickness).

#### recon-all-clinical (for pathological anatomy)
**Script**: `scripts/run_freesurfer_clinical.sh --subject PAT16 --session postop`

**Processing** (uses flag-based syntax: `-i`, `-subjid`, `-threads`, `-sdir`):
- SynthSeg deep learning segmentation (robust to tumors, resection cavities)
- SynthDist distance-based surface placement (not intensity-driven)
- SynthSR 1mm MPRAGE synthesis for visualization

**Best for**: Post-op sessions (resection cavity) and pre-op with large tumors.
Runs ~1-2h (vs ~6-8h for standard). See Gopinath et al. (2025) Medical Image Analysis.

#### Recommended strategy for glioma patients

| Subject | Session | Primary | Comparison |
|---------|---------|---------|------------|
| PAT16 | pre-op | Standard `recon-all` | `recon-all-clinical` (with `_clinical` suffix) |
| PAT16 | post-op | `recon-all-clinical` | -- |

For pre-op sessions, the glioma is present and can affect standard `recon-all`
(tumor mass effect may displace cortex, edema alters tissue contrast). Running
`recon-all-clinical` in parallel (with `_clinical` suffix) enables comparison of
segmentation quality in the peri-tumoral region: where does standard segmentation
struggle, and does the SynthSeg-based approach produce more plausible boundaries?
This is activated by the `--clinical-compare` flag in `run_pipeline.sh`.

Post-op sessions always use `recon-all-clinical` as the primary method because
the resection cavity breaks standard surface reconstruction.

**Key outputs** (both variants):
- `mri/aparc+aseg.mgz` -- Desikan-Killiany parcellation
- `surf/{lh,rh}.{white,pial}` -- Cortical surfaces
- `mri/brainmask.mgz`, `mri/wm.mgz` -- Masks
- (clinical only) `mri/synthSR.mgz`, `mri/synthseg.mgz`

### Step 2: fMRIPrep BOLD Preprocessing

**Script**: `scripts/run_fmriprep.sh --subject PAT16 --session preop`

**Processing**:
- Skull stripping, bias field correction, tissue segmentation
- BOLD-to-T1w coregistration (BBR)
- SyN fieldmap-less distortion correction (single-PE BOLD)
- Confound estimation (motion, aCompCor, etc.)
- Output in T1w space and MNI152NLin2009cAsym

**Key outputs** (T1w space):
- `*_space-T1w_desc-preproc_bold.nii.gz` -- Preprocessed BOLD
- `*_desc-confounds_timeseries.tsv` -- Confound regressors
- `*_space-T1w_desc-brain_mask.nii.gz` -- Brain mask

### Step 3: QSIPrep DWI Preprocessing

**Script**: `scripts/run_qsiprep.sh --subject PAT16 --session preop`

**Processing**:
- Head motion and eddy current correction
- Susceptibility distortion correction using reverse-PE (AP+PA) b0 pairs
- Bias field correction
- Output at 1.0 mm resolution in T1w-aligned (ACPC) space

**Key outputs**:
- `*_space-T1w_desc-preproc_dwi.nii.gz` -- Preprocessed DWI
- `*_space-T1w_desc-preproc_dwi.{bval,bvec}` -- Rotated gradients
- `*_space-T1w_desc-brain_mask.nii.gz` -- Brain mask

### Step 4: MRtrix3 Reconstruction

**Script**: `scripts/run_mrtrix_recon.sh --subject PAT16 --session preop`

**Processing** (6 sub-steps):
1. Convert QSIPrep output to MIF format (with b-value rounding)
2. Estimate tissue response functions (dhollander)
3. Multi-shell multi-tissue CSD (`dwi2fod msmt_csd`)
4. DTI fitting (`dwi2tensor`) + scalar maps (FA, MD, AD, RD)
5. Whole-brain tractography (iFOD2, 10M streamlines)
6. SIFT2 streamline filtering

**Key outputs**:
- `{fa,md,ad,rd}.nii.gz` -- DTI scalar maps
- `{wm,gm,csf}_fod_norm.mif` -- Normalised fibre orientation distributions
- `whole_brain.tck` -- 10M-streamline tractogram
- `sift2_weights.txt` -- SIFT2 weights

### Step 5: Co-register All to T1w Space

**Script**: `scripts/register_to_t1w.sh --subject PAT16 --session preop`

**Processing** (6 sub-steps):
1. Compute rigid (6-DOF) ACPC-to-T1w registration (FLIRT)
2. Apply to DTI scalar maps (FA, MD, AD, RD)
3. Apply to fOD images with SH reorientation
4. Transform whole-brain tractography streamlines
5. Convert FreeSurfer volumes to T1w-space NIfTI
6. (Optional) Resample BOLD timeseries

**Key outputs** (all in fMRIPrep native T1w space):
- `{fa,md,ad,rd}_space-T1w.nii.gz`
- `{wm,gm,csf}_fod_norm_space-T1w.mif`
- `whole_brain_space-T1w.tck`
- `aparc+aseg_space-T1w.nii.gz`

### Step 5b: Longitudinal Registration (ANTs SyN)

**Script**: `scripts/register_longitudinal.sh --subject PAT16`

**Processing** (5 sub-steps):
1. Generate resection cavity mask (SynthSeg difference or RESSEG)
2. ANTs SyN diffeomorphic registration (pre-op -> post-op T1w) with
   cavity excluded from cost function (`-x` flag)
3. Compute Jacobian determinant and displacement magnitude maps
4. Warp pre-op derivatives (T1w, DTI maps, parcellation) to post-op space
5. Compute ROI-level displacement statistics

**Cavity masking strategy** (three tiers):
- **Tier 1 (default, recommended)**: Use the pre-operative **binary tumor mask**
  from the dataset (`derivatives/tumor_masks/sub-*/anat/*_space_T1_label-tumor_binary.nii.gz`,
  created by `scripts/create_binary_masks.sh`) as a spatial prior for the
  resection cavity.  The binary mask (thresholded at p > 0.5 with morphological
  cleanup) is dilated by ~3 mm to account for surgical margins.
  This is the most reliable approach because the resection cavity corresponds
  to the tumor location.  The mask is resampled from pre-op T1w space to
  post-op T1w space using NIfTI affine headers.

- **Tier 2 (fallback)**: If no tumor mask is available, compare pre-op and
  post-op FreeSurfer segmentations (SynthSeg difference).  Voxels that are
  brain in pre-op but CSF/background in post-op approximate the resection
  cavity.  **Caveat**: This approach can produce mislocated masks when the
  two asegs come from different FreeSurfer methods or when systematic label
  differences in non-surgical regions dominate the largest-component filter.

- **Tier 3 (`--resseg`)**: Use the RESSEG deep-learning model for more
  precise masking.  Requires `pip install resseg`.

**Key outputs**:
- `preop_to_postop_1Warp.nii.gz` -- Forward deformation field
- `preop_to_postop_1InverseWarp.nii.gz` -- Inverse deformation field
- `jacobian_preop_to_postop.nii.gz` -- Local volume change (J > 1 = expansion)
- `displacement_magnitude.nii.gz` -- |u(x)| in mm
- `cavity_mask_postop.nii.gz` -- Resection cavity mask
- `T1w_preop_in_postop.nii.gz` -- Pre-op T1w warped to post-op space
- `{fa,md,ad,rd}_preop_in_postop.nii.gz` -- Warped DTI maps
- `aparc+aseg_preop_in_postop.nii.gz` -- Warped parcellation
- `displacement_roi_stats.json` -- Per-ROI displacement statistics

### Step 5c: TumorSynth Tumor Segmentation (optional, experimental)

**Script**: `scripts/test_tumorsynth.sh`

**Purpose**: Assess whether automated deep-learning tumor segmentation
(TumorSynth, Wu et al. 2026, Radiology: Imaging Cancer) produces sharper,
more anatomically plausible tumor boundaries than the existing Aerts et al.
probabilistic masks.

**Background**: The dataset ships with Gaussian-smoothed (σ=3 mm) probabilistic
tumor masks from a semi-automated SPM pipeline.  Thresholding at `p > 0.5`
gives plausible core volumes (~45 cm³ PAT16), but the boundaries
are inherently fuzzy.  TumorSynth is a CNN-based tool (nnUNet v1.7) integrated
with FreeSurfer that segments both healthy brain tissue and tumor from a single
MRI sequence (T1w, T1ce, T2, or FLAIR).  It outputs FreeSurfer-compatible labels
including label 18 = "Whole tumor".

**Requirements**:
- Separate conda environment: `nnUNet_v1.7` (created by `scripts/install_tumorsynth.sh`)
- Model weights: `Task002_Tumor` (whole tumor), optionally `Task003_InnerTumor`
- FreeSurfer 8.1.0 (for `mri_synthstrip` skull-stripping and `mri_robust_register`)

**Preprocessing** (per T1w image):
1. Skull-strip with `mri_synthstrip` (fast, resolution-agnostic)
2. Register to SRI-24 template with `mri_robust_register`

**Execution**:
```bash
conda activate nnUNet_v1.7
bash scripts/test_tumorsynth.sh
```

Or run in the background with `nohup` (recommended — CPU inference with
5-fold ensemble takes ~15-30 min per scan, ~1-2 h total for all 4 images):
```bash
mkdir -p logs
nohup bash -c 'eval "$(conda shell.bash hook)" && conda activate nnUNet_v1.7 && bash scripts/test_tumorsynth.sh --threads 8' \
  > logs/tumorsynth.log 2>&1 &
echo "PID: $!"
```

Monitor progress:
```bash
tail -f logs/tumorsynth.log          # live follow (Ctrl-C to stop watching)
tail -20 logs/tumorsynth.log         # quick status check
```

Runs `mri_TumorSynth --wholetumor --cpu --threads 8` on all 4 T1w images
(PAT16 × pre-op/post-op).  Preprocessing (skull-strip + registration)
is fast (~1-2 min/scan); the nnUNet 5-fold ensemble inference dominates
runtime (~15-30 min/scan on CPU).

**Key outputs** (in `derivatives/tumorsynth/sub-{SUB}/ses-{SES}/`):
- `*_tumorsynth_wholetumor.nii.gz` -- Full segmentation (18 labels)
- `*_tumorsynth_tumor_mask.nii.gz` -- Binary tumor-only mask (label 18)

**Comparison**: NB14 cell "TumorSynth vs Aerts comparison" overlays both
masks on T1w, computes Dice coefficient, and compares volumes.

**Feasibility result (negative)**:

Visual inspection in Freeview and quantitative comparison showed that
**TumorSynth on T1w-only input over-segments** for these glioma cases:

| Subject | Session | TumorSynth | Aerts (p>0.5) | Finding |
|---------|---------|-----------|---------------|---------|
| PAT16   | pre-op  | 53.3 cm³  | 45.4 cm³      | Over-segments into surrounding tissue |
| PAT16   | post-op | 48.3 cm³  | —             | Labels resection cavity as tumor |

Key observations:
- TumorSynth extends beyond visible lesion boundaries into normal tissue
- Post-op scans are incorrectly segmented (resection cavity labeled as tumor)
- The Aerts probabilistic masks (binarized at p > 0.5) produce more anatomically
  plausible delineations for these non-enhancing WHO II–III gliomas

**Conclusion**: For T1w-only input, TumorSynth is **not a viable replacement**
for the Aerts masks.  The Aerts probabilistic masks (binarized at p > 0.5)
remain the more reliable tumor delineation for this project.  This is consistent
with TumorSynth's design, which targets T1ce (contrast-enhanced) as the primary
input modality — without gadolinium contrast, the model has insufficient
information to distinguish non-enhancing tumor from edema and normal tissue.

**Caveats**:
- TumorSynth recommends T1ce as primary input; T1w-only has reduced
  specificity for non-enhancing WHO II–III gliomas (confirmed by this test)
- Post-op scans are incorrectly segmented — the resection cavity is
  misclassified as tumor
- This was an experimental feasibility assessment; the negative result
  validates the existing Aerts-based approach

### Step 5d: Standardized Binary Tumor Masks

**Script**: `scripts/create_binary_masks.sh`

**Purpose**: Convert the Aerts et al. probabilistic tumor masks into clean,
standardized binary masks so all downstream consumers use consistent inputs
rather than ad-hoc thresholding.

**Method**:
1. Threshold at p > 0.5 (configurable via `--threshold`)
2. Fill holes (`scipy.ndimage.binary_fill_holes`)
3. Remove small connected components < 1 cm³ (configurable via `--min-volume`)

**Execution**:
```bash
conda activate finse26
bash scripts/create_binary_masks.sh
```

**Outputs** (alongside the original probabilistic masks):

| Mask | Volume | Components removed |
|------|--------|--------------------|
| `sub-PAT16_space_T1_label-tumor_binary.nii.gz` | 45.4 cm³ | 6 (1-3 voxel noise) |
| `sub-PAT16_space_MNI_label-tumor_binary.nii.gz` | 53.0 cm³ | 1 (1 voxel) |

**QC (Freeview visual inspection)**: PAT16 T1-space binary
masks verified in Freeview overlaid on pre-op T1w — clean boundaries, no
scattered noise voxels, no holes, anatomically plausible delineation.

**Downstream usage**: Scripts and notebooks should load `*_label-tumor_binary.nii.gz`
instead of applying ad-hoc thresholding to the probabilistic `*_label-tumor.nii.gz`.

### Step 6: Pre-op vs Post-op Comparison

**Script**: `scripts/compare_preop_postop.py --subject PAT16`

**Analysis dimensions**:
- **Structural**: ROI volume changes from aparc+aseg
- **Diffusion**: Voxel-wise and ROI-wise delta-FA, delta-MD maps
- **Connectivity**: SC and FC matrix differences
- **Brain mechanics**: Tissue property changes mapped to mechanical
  parameters (stiffness, anisotropy) for FE modeling

## 6. Derivatives Output Structure

```
derivatives/
  freesurfer/
    sub-PAT16_ses-preop/           FreeSurfer recon-all output
    sub-PAT16_ses-postop/
  fmriprep/
    sub-PAT16/
      ses-preop/{anat,func}/       Preprocessed BOLD + anatomical
      ses-postop/{anat,func}/
  qsiprep/
    sub-PAT16/
      ses-preop/{anat,dwi}/        Preprocessed DWI
      ses-postop/{anat,dwi}/
  mrtrix_recon/
    sub-PAT16/
      ses-preop/                   CSD, DTI, tractography
      ses-postop/
  registered_t1w/
    sub-PAT16/
      ses-preop/                   All modalities in T1w space
      ses-postop/
      longitudinal/                SyN warp, Jacobian, displacement, cavity mask
      preop_vs_postop/             Longitudinal comparison outputs
  tumorsynth/                      TumorSynth segmentation (experimental)
    sub-PAT16/
      ses-preop/                   Whole-tumor + healthy tissue segmentation
      ses-postop/
```

## 7. Master Orchestration

**Script**: `scripts/run_pipeline.sh`

```bash
# Recommended: clinical for post-op, standard for pre-op
bash scripts/run_pipeline.sh \
    --clinical-postop \
    --parallel \
    --threads 8 \
    --mem-mb 16000
```

Options:
- `--subjects PAT16` -- limit to specific subjects
- `--sessions preop,postop` -- limit to specific sessions
- `--clinical-postop` -- use recon-all-clinical for post-op, standard for pre-op
- `--clinical-compare` -- post-op: clinical; pre-op: both standard and clinical (recommended)
- `--clinical` -- use recon-all-clinical for all sessions
- `--parallel` -- run fMRIPrep + QSIPrep in parallel
- `--skip-freesurfer`, `--skip-fmriprep`, `--skip-qsiprep`, `--skip-longitudinal` -- skip steps
- `--resseg` -- use RESSEG deep-learning model for cavity masking (Step 5b)
- `--qsiprep-recon` -- include MRtrix3 reconstruction
- `--container docker|singularity|none` -- execution mode

The pipeline generates a QC checklist per subject/session at
`derivatives/pipeline_qc_checklist.md`.

## 8. Quality Control

### Per subject x session:
- [ ] FreeSurfer: pial surface overlay on T1w
- [ ] FreeSurfer: aparc+aseg label boundaries
- [ ] fMRIPrep: HTML report, BOLD-to-T1w registration
- [ ] fMRIPrep: SyN SDC quality in orbitofrontal/temporal regions
- [ ] fMRIPrep: motion parameters (flag FD > 0.5 mm)
- [ ] QSIPrep: HTML report, b0-to-T1w overlay
- [ ] QSIPrep: eddy correction quality, outlier replacement
- [ ] Registration: dwiref-on-T1w overlay
- [ ] Registration: Jacobian determinant (flag |det(J)| > 1.2 or < 0.8)

### Per subject (longitudinal):
- [ ] Cavity mask is focal and covers only the resection void (~20–60 cm³);
      if it covers large parts of the brain (>200 cm³), the rigid pre-alignment
      likely failed — inspect with `freeview_deformation.sh`
- [ ] Warped pre-op T1w aligns with post-op anatomy
- [ ] Displacement magnitude is largest near cavity (expected brain shift)
- [ ] Jacobian near 1.0 far from lesion; J > 1 in expanding ventricles
- [ ] Pre-op vs post-op T1w alignment quality
- [ ] Resection cavity impact on post-op processing
- [ ] Consistency of parcellation labels across timepoints

## 9. Connection to Brain Mechanics

The fully co-registered T1w-space derivatives enable:

1. **Tissue segmentation** (aparc+aseg) provides the geometry for FE mesh
   generation via marching cubes + Gmsh tetrahedral meshing.

2. **DTI scalar maps** (FA, MD) serve as proxies for tissue mechanical
   properties: FA correlates with fiber alignment (anisotropic stiffness),
   MD correlates with tissue density/hydration.

3. **Fiber orientation distributions** (fODFs) provide the local fiber
   architecture for anisotropic constitutive models in the FE framework.

4. **Pre-op vs post-op comparison** quantifies how tumor resection alters
   tissue mechanics: changes in FA/MD around the resection cavity, disrupted
   fiber tracts, and altered connectivity patterns.

5. **Tumor masks** delineate regions requiring special material property
   assignment (tumor tissue is typically softer than normal brain parenchyma).

6. **Deformation fields** (Step 5b) provide empirical displacement and
   volume change data for validating FE model predictions. The Jacobian
   determinant identifies local expansion (ventricles) and contraction
   (cavity margins), and the displacement magnitude quantifies brain shift.

## 10. Scripts Summary

| Script                      | Purpose                                    | New/Modified |
|-----------------------------|--------------------------------------------|--------------|
| `run_freesurfer.sh`         | FreeSurfer recon-all + extra segmentations | Modified     |
| `run_freesurfer_clinical.sh`| FreeSurfer recon-all-clinical (pathology)  | New          |
| `run_fmriprep.sh`           | fMRIPrep BOLD preprocessing               | New          |
| `run_qsiprep.sh`            | QSIPrep DWI preprocessing                 | New          |
| `run_mrtrix_recon.sh`       | MRtrix3 CSD + DTI + tractography          | New          |
| `register_to_t1w.sh`        | Co-register all to T1w space              | New          |
| `register_longitudinal.sh`  | ANTs SyN longitudinal registration        | New          |
| `run_pipeline.sh`           | Master orchestration                       | New          |
| `compare_preop_postop.py`   | Pre-op vs post-op analysis                | New          |
| `transform_tck.py`          | Apply affine to .tck tractogram           | New (from ref)|
| `tck2trk.py`                | Convert .tck to .trk for Freeview         | New (from ref)|
| `dsi_studio_wrapper.sh`     | DSI Studio naming compatibility           | New (from ref)|
| `freeview_freesurfer.sh`    | Freeview: FreeSurfer QC                   | New          |
| `freeview_registration.sh`  | Freeview: registration QC                 | New          |
| `freeview_dti.sh`           | Freeview: DTI scalar maps                 | New          |
| `freeview_all.sh`           | Freeview: all modalities in T1w space     | New          |
| `freeview_preop_postop.sh`  | Freeview: pre/post-op comparison          | New          |
| `freeview_deformation.sh`   | Freeview: displacement/Jacobian QC        | New          |

## 11. Environment Files

| File                                  | Env name       | Purpose            |
|---------------------------------------|----------------|--------------------|
| `environment/environment.yml`         | `finse26`      | General + notebooks|
| `environment/environment_fmriprep.yml`| `cas-fmriprep` | fMRIPrep           |
| `environment/environment_qsiprep.yml` | `cas-qsiprep`  | QSIPrep            |

---

*This plan adapts the pipeline from
[brain-digital-twin-finse2026](https://github.com/arvidl/brain-digital-twin-finse2026)
(single healthy subject, single timepoint) to the glioma longitudinal dataset.*
