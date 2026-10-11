# Glioma Brain Digital Twin — Finse 2026 Workshop

## Multimodal MRI Analysis & Computational Neuromodeling for Glioma Patient Management

Contribution by Arvid Lundervold, BSc, MD, PhD  (co-developed with Cursor 2.5.26 and Opus 4.6)

[![Code: MIT](https://img.shields.io/badge/Code-MIT-green.svg)](./LICENSE)
[![Content: CC-BY-4.0](https://img.shields.io/badge/Content-CC--BY--4.0-blue.svg)](https://creativecommons.org/licenses/by/4.0/)
[![Python: 3.10+](https://img.shields.io/badge/Python-3.10%2B-blue)](https://www.python.org/)
[![Platform: macOS | Linux | Windows](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey)](https://www.python.org/)
[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/arvidl/glioma-brain-digital-twin-public/blob/main/notebooks/NB_C01_Digital_Twin_Concept_and_Data.ipynb)

> **Project status:** research prototype. The capstone notebook series
> (`NB_C01`–`NB_C09`) demonstrates a complete, patient-specific modelling
> chain -- MRI → brain mechanics → structural connectivity → neural dynamics
> → cognitive outcome -- on **one patient** (sub-PAT16, OpenNeuro BTC dataset).
> It is a methods demonstrator, not a validated predictive model.
>
> **Not for clinical use.** This software is not a medical device and must not
> be used for diagnosis, prognosis, or treatment decisions.

**Interactive presentation** for clinicians, clinical neuroscientists and
neuropsychologists: <https://arvidl.github.io/glioma-brain-digital-twin-public/>
(source in [`presentation/`](presentation/)).

---

## Table of Contents

1. [Overview](#overview)
2. [Scientific Context](#scientific-context)
3. [Dataset](#dataset)
4. [Notebook Overview](#notebook-overview)
5. [Quick Start](#quick-start)
6. [Repository Structure](#repository-structure)
7. [Software Environment](#software-environment)
8. [Data Provenance & Citation](#data-provenance--citation)
9. [References](#references)
10. [Contributing](#contributing)
11. [License](#license)

---

## Overview

This repository contains a comprehensive computational workflow for integrating **multimodal MRI data** (structural T1-weighted, diffusion-weighted imaging, resting state fMRI) with **digital twin technologies** to model brain mechanics and tumor impacts in glioma patients. 

The project (being work in progress) integrates classical neuroimaging analysis pipelines with modern computational neuroscience tools, bridging **structural connectivity** (from tractography), **functional connectivity**, **network dynamics** (using The Virtual Brain), and **biomechanical simulations** (using FEniCSx). This provides a holistic digital twin representation of glioma-affected brains.

---

## Scientific Context

### What is a Brain Digital Twin?

A **brain digital twin** is a computational replica of an individual patient's brain that integrates anatomical, functional, and biomechanical properties into a unified model. This enables **patient-specific simulations** of neural dynamics, tumor growth, and treatment outcomes — moving beyond population-level neuroscience toward **precision medicine**.

We employ a **five-layer architecture**:

| Layer | Name | Data source | Role |
|-------|------|-------------|------|
| 1 | **Geometric** | T1w segmentation | Patient-specific FE mesh |
| 2 | **Constitutive** | dMRI (FA, fODFs) | Heterogeneous, anisotropic material properties |
| 3 | **Functional** | fMRI + tractography | SC/FC connectivity, hemodynamic priors |
| 4 | **Simulation** | FEniCSx / TVB | PDE solver → displacement, stress, strain; neural dynamics |
| 5 | **Clinical Outcome** | CANTAB + questionnaires | Cognitive/psychosocial validation (pre- vs post-op) |

Layers 1–4 predict *where* tissue deforms and *which* connections are disrupted. Layer 5 closes the loop by asking whether predicted disruption translates to **measurable cognitive change** — turning the model into a clinically relevant tool.

### Why Glioma?

**Gliomas** are the most common primary malignant brain tumors. Pre-operative assessment requires understanding not only tumor location and morphology, but also its **functional impact** on neighboring brain networks. Digital twins enable:
- Prediction of eloquent cortex infiltration risk
- Network-level functional consequences of tumor location
- Biomechanical strain induced by the lesion
- Personalized prognostication and surgical planning

### Why Multimodal MRI?

A single MRI contrast is insufficient for comprehensive digital twin construction, we need mpMRI:
- **T1-weighted**: Gray matter anatomy, tumor boundaries
- **T2/FLAIR/CT1** (*not present in this study*): Edema extent, white matter pathology, contrast-enhancing tumor 
- **Diffusion MRI (dMRI)**: White matter tract integrity, whole-brain connectome
- **Functional MRI (fMRI)**: Resting-state networks, functional connectivity changes
- **Structural MRI geometry**: Substrate for biomechanical finite-element modeling

This multimodal integration is essential for clinically relevant patient-specific models.

---

## Dataset

### Subjects

This project uses **sub-PAT16** as a representative case from the Brain Tumor Connectomics (BTC) dataset (data openly available from https://openneuro.org):

| Subject | Diagnosis | Sex | Age | Location | Imaging |
|---------|-----------|-----|-----|----------|---------|
| **sub-PAT16** | Anaplastic Astrocytoma (WHO II-III) | Male | 39 | Fronto-temporal | Pre-op + Post-op |

> **Full BTC cohort**: The full 25-patient cohort is available on OpenNeuro: [ds001226 (BTC_preop, v5.0.0)](https://openneuro.org/datasets/ds001226/versions/5.0.0) and [ds002080 (BTC_postop, v4.0.0)](https://openneuro.org/datasets/ds002080/versions/4.0.0).

### Data Structure

Data follows the **Brain Imaging Data Structure (BIDS)** standard:

```
sub-PAT16
└── ses-preop
    ├── anat
    │   ├── sub-PAT16_ses-preop_T1w.json
    │   └── sub-PAT16_ses-preop_T1w.nii.gz
    ├── dwi
    │   ├── sub-PAT16_ses-preop_acq-AP_dwi.bval
    │   ├── sub-PAT16_ses-preop_acq-AP_dwi.bvec
    │   ├── sub-PAT16_ses-preop_acq-AP_dwi.json
    │   ├── sub-PAT16_ses-preop_acq-AP_dwi.nii.gz
    │   ├── sub-PAT16_ses-preop_acq-PA_dwi.bval
    │   ├── sub-PAT16_ses-preop_acq-PA_dwi.bvec
    │   ├── sub-PAT16_ses-preop_acq-PA_dwi.json
    │   └── sub-PAT16_ses-preop_acq-PA_dwi.nii.gz
    └── func
        ├── sub-PAT16_ses-preop_task-rest_bold.json
        └── sub-PAT16_ses-preop_task-rest_bold.nii.gz
└── ses-postop
    ├── anat
    │   ├── sub-PAT16_ses-postop_T1w.json
    │   └── sub-PAT16_ses-postop_T1w.nii.gz
    ├── dwi
    │   ├── sub-PAT16_ses-postop_acq-AP_dwi.bval
    │   ├── sub-PAT16_ses-postop_acq-AP_dwi.bvec
    │   ├── sub-PAT16_ses-postop_acq-AP_dwi.json
    │   ├── sub-PAT16_ses-postop_acq-AP_dwi.nii.gz
    │   ├── sub-PAT16_ses-postop_acq-PA_dwi.bval
    │   ├── sub-PAT16_ses-postop_acq-PA_dwi.bvec
    │   ├── sub-PAT16_ses-postop_acq-PA_dwi.json
    │   └── sub-PAT16_ses-postop_acq-PA_dwi.nii.gz
    └── func
        ├── sub-PAT16_ses-postop_task-rest_bold.json
        └── sub-PAT16_ses-postop_task-rest_bold.nii.gz


```


**Note**: Pre-operative and post-operative imaging enables longitudinal analysis of tumor evolution and post-resection changes.

---

## Notebook Overview

The notebooks are organized in **two tracks**:

- **Track A (NB00-NB08)**: "Fast" track. Uses pre-computed TVB/rsHRF
  derivatives with synthetic data fallbacks, **runs in Google Colab**,
  teaches neuroimaging and digital twin concepts.
- **Track B (NB09-NB17)**: Full pipeline track. **Requires local installation**
  (FreeSurfer, fMRIPrep, QSIPrep, MRtrix3), produces its own derivatives, QCs them,
  and computes connectivity from pipeline outputs.

Both tracks are self-contained. Track A is recommended for illustration,
downloading data from a GitHub Release (~200 MB); Track B for research
and explorative use with full control over the processing pipeline.

### Track A: Educational / Workshop (NB00-NB08)

| # | Notebook | Topic | Duration | Key Tools |
|---|----------|-------|----------|-----------|
| **00** | Setup and Verification | Environment validation, dependency checks | 15 min | `nibabel`, `nilearn` |
| **01** | BIDS Data Exploration | Dataset structure, metadata, clinical & cognitive data | 30 min | `pybids`, `matplotlib` |
| **02** | Structural MRI Analysis | T1/T2 segmentation, tissue classification, tumor masking | 45 min | `nibabel`, `nilearn`, `pyvista` |
| **03** | Diffusion MRI & Tractography | DTI metrics, fiber tract reconstruction, connectome generation | 60 min | `dipy`, `MRtrix3` |
| **04** | Functional MRI Analysis | BOLD/HRF concepts, ROI time series, FC (pipeline rsHRF) | 45 min | `nilearn`, `nibabel` |
| **05** | Structural & Functional Connectivity | Graph metrics, SC-FC coupling (pipeline or pre-computed TVB) | 60 min | `networkx` |
| **06** | Tumor Impact Analysis | Pre/post network comparison (pre-computed TVB derivatives) | 45 min | `nibabel`, `scipy` |
| **07** | Brain Mechanics with FEniCSx | Mesh generation, finite-element biomechanical modeling | 90 min | `FEniCSx`, `UFL`, `gmsh` |
| **08** | Glioma Digital Twin Integration | Five-layer architecture, TVB-FEniCSx simulation, CANTAB outcome validation | 60 min | `TVB`, `FEniCSx`, `networkx` |

### Track B: Full Pipeline (NB09-NB17)

| # | Notebook | Topic | Parallels | Duration |
|---|----------|-------|-----------|----------|
| **09** | Preprocessing Pipeline Overview | Didactic walkthrough of the 9-step pipeline | -- | 45 min |
| **10** | FreeSurfer QC | Verify cortical surfaces, parcellation | -- | 20 min |
| **11** | fMRIPrep QC | Verify BOLD preprocessing, motion, registration | -- | 20 min |
| **12** | QSIPrep + MRtrix3 QC | Verify DWI preprocessing, DTI, CSD, tractography | -- | 30 min |
| **13** | Registration QC | Verify co-registration to T1w space | -- | 20 min |
| **14** | Pre-op vs Post-op Comparison | Deformation fields, delta-FA/MD, ROI volumes | extends NB06 | 45 min |
| **15** | Pipeline Functional Connectivity | FC from fMRIPrep BOLD + aparc+aseg | parallels NB04 | 30 min |
| **16** | Pipeline Structural Connectivity | SC from MRtrix3 tractography + SIFT2 | parallels NB05 | 30 min |
| **17** | Pipeline Longitudinal Connectomics | Network-level pre/post SC+FC comparison | parallels NB06 | 30 min |

### Freeview Inspection Scripts

| Script | Purpose |
|--------|---------|
| `scripts/freeview_freesurfer.sh` | Inspect FreeSurfer surfaces and parcellation |
| `scripts/freeview_registration.sh` | Verify DWI-to-T1w registration quality |
| `scripts/freeview_dti.sh` | Inspect DTI scalar maps (FA, MD, AD, RD) |
| `scripts/freeview_all.sh` | Unified viewer: all modalities in T1w space |
| `scripts/freeview_preop_postop.sh` | Pre-op vs post-op side-by-side comparison |
| `scripts/freeview_deformation.sh` | Displacement, Jacobian, and cavity mask QC |
| `scripts/freeview_resseg.sh` | Inspect RESSEG cavity segmentation |
| `scripts/freeview_tumor_vs_cavity.sh` | Compare pre-op tumor with post-op cavity (side-by-side or overlay) |

---

## Quick Start

### Option A: Google Colab (1-click, no local installation)

Each notebook has a **Colab badge** at the top. Click to open in your browser:

- **[NB00: Setup & Verification](https://colab.research.google.com/github/arvidl/glioma-brain-digital-twin-public/blob/main/notebooks/NB00_Setup_and_Verification.ipynb)**
- **[NB01: BIDS Exploration](https://colab.research.google.com/github/arvidl/glioma-brain-digital-twin-public/blob/main/notebooks/NB01_BIDS_Exploration.ipynb)**
- **[NB02: Structural MRI](https://colab.research.google.com/github/arvidl/glioma-brain-digital-twin-public/blob/main/notebooks/NB02_Structural_MRI_Analysis.ipynb)**
- **[NB03: Diffusion MRI](https://colab.research.google.com/github/arvidl/glioma-brain-digital-twin-public/blob/main/notebooks/NB03_Diffusion_MRI_and_Tractography.ipynb)**
- **[NB04: Functional MRI](https://colab.research.google.com/github/arvidl/glioma-brain-digital-twin-public/blob/main/notebooks/NB04_Functional_MRI_Analysis.ipynb)**
- **[NB05: SC & FC](https://colab.research.google.com/github/arvidl/glioma-brain-digital-twin-public/blob/main/notebooks/NB05_Structural_and_Functional_Connectivity.ipynb)**
- **[NB06: Tumor Impact](https://colab.research.google.com/github/arvidl/glioma-brain-digital-twin-public/blob/main/notebooks/NB06_Tumor_Impact_Analysis.ipynb)**
- **[NB08: Digital Twin](https://colab.research.google.com/github/arvidl/glioma-brain-digital-twin-public/blob/main/notebooks/NB08_Glioma_Digital_Twin_Integration.ipynb)**

Each Track A notebook auto-installs dependencies and downloads data (~200 MB) on first run.
NB07 (FEniCSx) has a Colab badge but FEniCSx installation is fragile;
NB09--NB17 require the local processing pipeline.
GPU is available via `Runtime → Change runtime type → T4 GPU`.

### Option B: Local Setup (Recommended for full development)

**Requirements**: Git, Miniforge/Mambaforge, ~15 GB disk space

```bash
# Clone the repository
git clone https://github.com/arvidl/glioma-brain-digital-twin-public.git
cd glioma-brain-digital-twin

# Download imaging data (~400 MB)
python data/download_data.py

# Create conda environment
conda env create -f environment/environment.yml

# Activate environment
conda activate finse26

# Launch Jupyter Lab
jupyter lab notebooks/
```

Then open `notebooks/NB00_Setup_and_Verification.ipynb` to verify all dependencies.

### Option C: Docker (Coming Soon)

Docker image with all dependencies pre-installed will be available soon:

```bash
docker pull arvidl/glioma-brain-digital-twin-public:latest
docker run -it -p 8888:8888 arvidl/glioma-brain-digital-twin-public:latest jupyter lab --ip=0.0.0.0
```

For full installation guidance (platform-specific, CUDA setup, etc.), see **[INSTALLATION.md](./INSTALLATION.md)**.

---

## Repository Structure

```
glioma-brain-digital-twin/
├── README.md                          # This file
├── INSTALLATION.md                    # Detailed setup guide (platform-specific)
├── LICENSE                            # MIT license (code)
├── CITATION.cff                       # How to cite this repository
├── environment/
│   ├── environment.yml                # Conda environment (finse26) -- general + notebooks
│   ├── environment_fmriprep.yml       # Conda environment (cas-fmriprep) -- fMRIPrep
│   ├── environment_qsiprep.yml        # Conda environment (cas-qsiprep) -- QSIPrep
│   ├── requirements-colab.txt          # pip-only for Colab
│   └── setup_env.sh                   # Automated environment setup script
│
├── notebooks/                         # Main tutorial notebooks
│   ├── NB00_Setup_and_Verification.ipynb
│   ├── NB01_BIDS_Exploration.ipynb
│   ├── NB02_Structural_MRI_Analysis.ipynb
│   ├── NB03_Diffusion_MRI_and_Tractography.ipynb
│   ├── NB04_Functional_MRI_Analysis.ipynb
│   ├── NB05_Structural_and_Functional_Connectivity.ipynb
│   ├── NB06_Tumor_Impact_Analysis.ipynb
│   ├── NB07_Brain_Mechanics_FEniCSx.ipynb
│   ├── NB08_Glioma_Digital_Twin_Integration.ipynb  [if available]
│   ├── NB09_Preprocessing_Pipeline_Overview.ipynb   # Didactic pipeline walkthrough
│   ├── NB10_FreeSurfer_QC.ipynb                     # FreeSurfer QC
│   ├── NB11_fMRIPrep_QC.ipynb                       # fMRIPrep QC
│   ├── NB12_QSIPrep_MRtrix3_QC.ipynb                # QSIPrep + MRtrix3 QC
│   ├── NB13_Registration_QC.ipynb                    # Co-registration QC
│   ├── NB14_Preop_vs_Postop.ipynb                    # Longitudinal comparison
│   ├── NB15_Pipeline_Functional_Connectivity.ipynb   # FC from fMRIPrep (Track B)
│   ├── NB16_Pipeline_Structural_Connectivity.ipynb   # SC from MRtrix3 (Track B)
│   ├── NB17_Pipeline_Longitudinal_Connectomics.ipynb # Pre/post SC+FC (Track B)
│   └── INDEX.md                       # Notebook index
│
├── data/                              # BIDS dataset
│   ├── BIDS_preop_postop/             # Populate via: python data/download_data.py
│   │   ├── sub-PAT16/
│   │   │   └── sub-PAT16_sessions.tsv # Session-level clinical & cognitive data (48 cols)
│   │   ├── participants.tsv           # Demographics, tumor info, anthropometrics
│   │   ├── derivatives/               # Tumor masks (Aerts), pre-computed TVB/rsHRF (reference)
│   │   └── dataset_description.json
│   ├── download_data.py               # Data download/copy utility
│   ├── README                         # Data provenance & metadata
│   └── CHANGES                        # Dataset versions
│
├── scripts/                           # Processing scripts
│   ├── run_pipeline.sh                # Master orchestration (--clinical-postop)
│   ├── run_freesurfer.sh              # FreeSurfer recon-all + extra segmentations
│   ├── run_freesurfer_clinical.sh     # FreeSurfer recon-all-clinical (tumor/resection)
│   ├── freesurfer_recon.sh            # Simplified FreeSurfer wrapper
│   ├── run_fmriprep.sh                # fMRIPrep BOLD preprocessing
│   ├── run_qsiprep.sh                 # QSIPrep DWI preprocessing
│   ├── run_mrtrix_recon.sh            # MRtrix3 CSD + DTI + tractography
│   ├── dwi_preprocess_mrtrix.sh       # Alternative DWI preprocessing via MRtrix3
│   ├── register_to_t1w.sh            # Co-register all to T1w space
│   ├── register_longitudinal.sh       # ANTs SyN longitudinal registration (Step 5b)
│   ├── compare_preop_postop.py        # Pre-op vs post-op analysis
│   ├── compute_fc.py                  # FC matrices from fMRIPrep BOLD
│   ├── compute_rshrf.py               # rsHRF parameter maps (point-process deconvolution)
│   ├── compute_tvb_connectome.py      # SC matrix from tractogram
│   ├── transform_tck.py               # Apply affine to .tck tractograms
│   ├── tck2trk.py                     # Convert .tck to .trk (Freeview)
│   ├── dsi_studio_wrapper.sh          # DSI Studio naming compatibility
│   ├── create_data_release.sh         # Package data for release
│   ├── freeview_freesurfer.sh         # Freeview: FreeSurfer surfaces + parcellation
│   ├── freeview_registration.sh       # Freeview: DWI-to-T1w registration QC
│   ├── freeview_dti.sh                # Freeview: DTI scalar maps
│   ├── freeview_all.sh                # Freeview: all modalities in T1w space
│   ├── freeview_preop_postop.sh       # Freeview: pre-op vs post-op comparison
│   ├── freeview_deformation.sh        # Freeview: displacement/Jacobian QC
│   ├── freeview_resseg.sh             # Freeview: RESSEG cavity segmentation
│   ├── freeview_tumor_vs_cavity.sh    # Freeview: tumor vs cavity comparison
│   ├── check_env.py                   # Dependency verification
│   ├── config.py                      # Centralized path configuration
│   └── utils/
│       ├── bids_utils.py
│       ├── mri_utils.py
│       ├── connectivity_utils.py
│       └── mechanics_utils.py
│
├── examples/                          # Example outputs & figures
│   ├── connectome_example.json
│   └── example_outputs/
│       └── [sample visualizations]
│
├── tests/                             # Unit tests
│   ├── test_data_loading.py
│   └── test_processing_pipelines.py
│
├── beamer/                            # Beamer (LaTeX) slide deck for Finse workshop
│   ├── main.tex                       # Master document
│   ├── preamble.tex                   # Theme, macros, packages
│   ├── references.bib                 # Bibliography
│   ├── Makefile                       # Build: make pdf / make clean / make watch
│   ├── sections/                      # Modular section files (01-11)
│   ├── figures/                       # Static figures and diagrams
│   └── gslides/                       # Google Slides exports (Freeview illustrations)
│
├── docs/                              # Additional documentation
│   ├── processing_pipeline.md         # Full pipeline: raw MRI → TVB derivatives
│   ├── preprocessing_pipeline_plan.md # Multi-subject preprocessing plan
│   └── [primers, platform notes]
│
├── .github/workflows/                 # CI/CD (GitHub Actions)
│   └── tests.yml
│
└── .gitattributes                     # Git LFS configuration

```

### Presentation (Beamer + Google Slides)

The `beamer/` folder contains a LaTeX/Beamer slide deck for the Finse workshop presentation (~60-70 frames, designed for ~90 min but modular for shorter talks). The deck covers problem formulation, neuro-oncological challenges, mpMRI opportunities, the processing pipeline, longitudinal registration, the digital twin concept, and mathematical challenges in brain mechanics.

**Two-medium strategy:**
- **Beamer:** Structured content, equations, tables, TikZ workflow diagrams
- **Google Slides:** High-quality Freeview screenshots and dynamic visualizations, exported as PNG into `beamer/gslides/`

**Build the slides:**
```bash
cd beamer && make pdf     # single build
cd beamer && make watch   # continuous rebuild on save
```

---

## Software Environment

The full processing pipeline requires the following tools (all tested on Apple Silicon / ARM64):

| Tool | Version | Notes |
|------|---------|-------|
| FreeSurfer | 8.1.0 | Native ARM64 |
| FSL | 6.0.7.19 | Official installer |
| AFNI | 26.0.09 | Built from source |
| MRtrix3 | 3.0.8 | Built from source (bundled Eigen 3.4) |
| Connectome Workbench | 2.1.0 | Built from source (Qt 6) |
| DSI Studio | Hou (2025.04.16) | Official ARM64 build |
| fMRIPrep | 25.2.4 | conda env `cas-fmriprep` |
| QSIPrep | 1.1.1 | conda env `cas-qsiprep` |
| ANTs | >= 2.5 | conda-forge (osx-arm64) |

### Conda Environments

Three separate environments are used (fMRIPrep and QSIPrep have conflicting dependencies):

| Environment | File | Purpose |
|-------------|------|---------|
| `finse26` | `environment/environment.yml` | General analysis, notebooks, ANTs CLI (`conda install -c conda-forge ants`) |
| `cas-fmriprep` | `environment/environment_fmriprep.yml` | fMRIPrep BOLD preprocessing |
| `cas-qsiprep` | `environment/environment_qsiprep.yml` | QSIPrep DWI preprocessing |
| `nnUNet_v1.7` | `scripts/install_tumorsynth.sh` | TumorSynth tumor segmentation (optional, experimental) |

### Processing Pipeline

The full pipeline is orchestrated by `scripts/run_pipeline.sh`.

#### Pipeline Options

| Option | Description |
|--------|-------------|
| `--subjects PAT16` | Comma-separated subject IDs (default: `PAT16`) |
| `--sessions preop,postop` | Comma-separated session labels (default: `preop,postop`) |
| `--threads N` | CPU threads per job (default: 8) |
| `--mem-mb M` | Memory limit in MB (default: 16000) |
| `--parallel` | Run fMRIPrep + QSIPrep in parallel (Steps 2 & 3) |
| `--clinical` | Use `recon-all-clinical` for all sessions |
| `--clinical-postop` | Use `recon-all-clinical` for post-op, standard `recon-all` for pre-op |
| `--clinical-compare` | Post-op: clinical; pre-op: **both** standard and clinical (with `_clinical` suffix) for comparison (recommended) |
| `--resseg` | Use RESSEG deep learning model for cavity masking in Step 5b |
| `--skip-freesurfer` | Skip Step 1 |
| `--skip-fmriprep` | Skip Step 2 |
| `--skip-qsiprep` | Skip Step 3 |
| `--skip-mrtrix` | Skip Step 4 |
| `--skip-register` | Skip Step 5 |
| `--skip-longitudinal` | Skip Step 5b |
| `--skip-compare` | Skip Step 6 |

#### Usage Examples

```bash
# Full pipeline for all subjects (recommended for glioma)
bash scripts/run_pipeline.sh --clinical-compare --parallel --threads 8

# Only FreeSurfer for PAT16 pre-op (trial run)
bash scripts/run_pipeline.sh --subjects PAT16 --sessions preop --threads 8 \
  --skip-fmriprep --skip-qsiprep --skip-mrtrix --skip-register \
  --skip-longitudinal --skip-compare

# Steps 1-5 for one subject, both sessions
bash scripts/run_pipeline.sh --subjects PAT16 --clinical-postop --threads 8 \
  --skip-longitudinal --skip-comparison

# Resume from Step 4 onward (Steps 1-3 already done)
bash scripts/run_pipeline.sh --clinical-postop --threads 8 \
  --skip-freesurfer --skip-fmriprep --skip-qsiprep
```

#### Pipeline Steps

| Step | Script | Tool | Time |
|------|--------|------|------|
| 1. T1w segmentation | `run_freesurfer.sh` / `run_freesurfer_clinical.sh` | FreeSurfer 8.1.0 | ~6-8h / ~1-2h |
| 2. BOLD preprocessing | `run_fmriprep.sh` | fMRIPrep 25.2.4 | ~1-2 h |
| 3. DWI preprocessing | `run_qsiprep.sh` | QSIPrep 1.1.1 | ~2-4 h |
| 4. CSD + tractography | `run_mrtrix_recon.sh` | MRtrix3 3.0.8 | ~1-2 h |
| 5. Co-register to T1w | `register_to_t1w.sh` | FSL + MRtrix3 + ANTs | ~10 min |
| 5b. Longitudinal registration | `register_longitudinal.sh` | ANTs SyN + RESSEG | ~30-90 min |
| 6. Pre/post comparison | `compare_preop_postop.py` | Python | ~5 min |
| 7. Structural connectivity | `compute_tvb_connectome.py` | MRtrix3 `tck2connectome` | ~30 s |
| 8. Functional connectivity | `compute_fc.py` | Python (nilearn) | ~30 s |
| 9. rsHRF estimation | `compute_rshrf.py` | Python (point-process deconvolution) | ~30 s |

The pipeline is **fully self-contained**: the only external inputs are the raw BIDS NIfTI files and the Aerts tumor delineation. All derivatives (FreeSurfer, fMRIPrep, QSIPrep, MRtrix3, RESSEG, SC, FC, rsHRF) are computed from these inputs.

All per-session steps detect already-completed outputs and skip them, so the pipeline is safe to re-run without redoing finished work. Steps 2 and 3 can run in parallel (`--parallel`). Steps 1-5 run per (subject, session) pair. Steps 5b-9 run per subject after both sessions are processed. Step 5b performs diffeomorphic (ANTs SyN) registration between pre-op and post-op T1w, with automatic resection cavity masking (SynthSeg-based by default; `--resseg` for RESSEG deep-learning masking). Step 9 replaces the external rsHRF BIDS App with a self-contained point-process deconvolution implementation (Wu et al. 2013). See [docs/preprocessing_pipeline_plan.md](docs/preprocessing_pipeline_plan.md) for the full plan.

#### Running Long Steps in the Background

Several pipeline steps take hours (FreeSurfer ~6 h, QSIPrep ~2-4 h). Use `nohup` to run them in the background so they survive terminal closure:

```bash
mkdir -p logs

# Example: only FreeSurfer for PAT16 pre-op (~6 h)
nohup bash scripts/run_pipeline.sh --subjects PAT16 --sessions preop --threads 8 \
  --skip-fmriprep --skip-qsiprep --skip-mrtrix --skip-registration \
  --skip-longitudinal --skip-compare \
  > logs/pipeline_PAT16_preop_step1.log 2>&1 &
echo "PID: $!"

# Example: full pipeline for all subjects (~24-48 h)
nohup bash scripts/run_pipeline.sh --clinical-postop --parallel --threads 8 \
  > logs/pipeline_full.log 2>&1 &
echo "PID: $!"
```

Monitor progress and check status:

```bash
tail -f logs/pipeline_PAT16_preop_step1.log   # live follow (Ctrl-C to stop watching)
tail -20 logs/pipeline_PAT16_preop_step1.log  # quick status check
ps aux | grep recon-all | grep -v grep        # is FreeSurfer still running?
```

#### TumorSynth (experimental — negative feasibility result)

A feasibility test of [TumorSynth](https://surfer.nmr.mgh.harvard.edu/fswiki/TumorSynth)
(Wu et al. 2026, nnUNet v1.7) was conducted to assess whether CNN-based segmentation
produces sharper tumor boundaries than the existing Aerts et al. probabilistic masks.

**Result**: TumorSynth on T1w-only input **over-segments** for these non-enhancing
WHO II–III gliomas — extending beyond visible lesion boundaries and producing
contralateral false positives.  The Aerts probabilistic masks (binarized at p > 0.5)
remain the more reliable tumor delineation.  See
[docs/preprocessing_pipeline_plan.md](docs/preprocessing_pipeline_plan.md#step-5c)
for the full comparison table and rationale.

<details>
<summary>How to re-run TumorSynth (for reference)</summary>

```bash
mkdir -p logs
nohup bash -c 'eval "$(conda shell.bash hook)" && conda activate nnUNet_v1.7 && bash scripts/test_tumorsynth.sh --threads 8' \
  > logs/tumorsynth.log 2>&1 &
echo "PID: $!"
tail -f logs/tumorsynth.log
```
</details>

The `logs/` directory is git-ignored.

---

## Data Provenance & Citation

### Data Attribution

The BIDS datasets in this project are based on:
The imaging data for sub-PAT16 is from the Brain Tumor Connectomics (BTC) dataset by Aerts et al. This project uses sub-PAT16 as a representative case. The full 25-patient cohort is available on OpenNeuro: [ds001226 (BTC_preop, v5.0.0)](https://openneuro.org/datasets/ds001226/versions/5.0.0) and [ds002080 (BTC_postop, v4.0.0)](https://openneuro.org/datasets/ds002080/versions/4.0.0).

### Data Access

- **Workshop data** (~400 MB): Download via `python data/download_data.py` or from the [data release](https://github.com/arvidl/glioma-brain-digital-twin-public/releases/tag/glioma-data-v2.0.0)
- **Full datasets** (25 patients + 11 controls): [OpenNeuro ds001226](https://openneuro.org/datasets/ds001226), [OpenNeuro ds002080](https://openneuro.org/datasets/ds002080)
- **Processing pipeline**: See [docs/processing_pipeline.md](docs/processing_pipeline.md) for reproducing derivatives from raw data

### How to Cite

If you use this material or methods in your research, please cite:

```bibtex
@workshop{Finse2026,
  title={Glioma Brain Digital Twin: Multimodal MRI \& Computational Neuromodeling},
  author={Arvid Lundervold},
  year={2026},
  organization={CAS: Mathematical Challenges in Brain Mechanics, Finse Workshop, March 9-11, 2026}
}
```

and the contributors of the original data:

[**BTC_preop**](https://openneuro.org/datasets/ds001226/versions/5.0.0)
```bibtex
@dataset{ds001226:5.0.0,
  author = {Aerts, H AND Marinazzo, D},
  title = {"BTC_preop"},
  year = {2022},
  doi = {doi:10.18112/openneuro.ds001226.v5.0.0},
  publisher = {OpenNeuro}
}
```

[**BTC_postop**](https://openneuro.org/datasets/ds002080/versions/4.0.0)
```bibtex
@dataset{ds002080:4.0.0,
  author = {Hannelore Aerts AND Daniele Marinazzo},
  title = {"BTC_postop"},
  year = {2022},
  doi = {doi:10.18112/openneuro.ds002080.v4.0.0},
  publisher = {OpenNeuro}
}
```

---

## References

- Aerts, H., Schirner, M., Jeurissen, B., Van Roost, P., Achten, E., Ritter, P., & Marinazzo, D. (2018). "Modeling brain dynamics in brain tumor patients using The Virtual Brain." eNeuro, 2018 Jun 4;5(3)  (https://www.eneuro.org/content/5/3/ENEURO.0083-18.2018)
- Esteban, O., Markiewicz, C. J., Blair, R. W., Moodie, C. A., … , Poldrack, R. A., & Gorgolewski, K. J. (2019). "**fMRIPrep**: a robust preprocessing pipeline for functional MRI." Nature Methods, 16(1), 111–116. (https://doi.org/10.1038/s41592-018-0235-4)
- Cieslak, M., Cook, P. A., He, X., … , Grafton, S. T., & Satterthwaite, T. D. (2021). "**QSIPrep**: an integrative platform for preprocessing and reconstructing diffusion MRI data." Nature Methods, 18(7), 775–778. (https://doi.org/10.1038/s41592-021-01185-5)
- Sanz-Leon, P., Knock, S. A., Spiegler, A., & Jirsa, V. K. (2015). "Mathematical framework of the **Virtual Brain**." NeuroImage, 111, 385–430.  ([The Virtual Brain Project](https://www.thevirtualbrain.org/))
- Alnaes, M. S., Logg, A., Ølgaard, K. B., Rognes, M. E., & Wells, G. N. (2014). "Unified Form Language: A domain-specific language for weak formulations and partial differential equations." ACM Transactions on Mathematical Software, 40(2), 9.   ([FEniCSx Documentation](https://fenicsproject.org/))
- Tournier, J. D., Smith, R., Raffelt, D., et al. (2019). "**MRtrix3**: A fast, flexible and open software framework for medical image processing and visualisation." NeuroImage, 202, 116137.(https://www.sciencedirect.com/science/article/pii/S1053811919307281)
- Garyfallidis, E., Brett, M., Amirbekian, B., et al. (2014). "**Dipy**: A library for the analysis of diffusion MRI data." Frontiers in Neuroinformatics, 8, 8. ([DIPY Documentation](https://dipy.org))
- Abraham, A., Pedregosa, F., Eickenberg, M., et al. (2014). "Machine learning for neuroimaging with scikit-learn." Frontiers in Neuroinformatics, 8, 14.  ([Nilearn Documentation](https://nilearn.github.io))


---

## Contributing

We welcome contributions! Please:

1. Fork this repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit changes: `git commit -m "Add descriptive message"`
4. Push to branch: `git push origin feature/your-feature`
5. Open a Pull Request with a clear description

For significant changes, please open an **Issue** first to discuss.

---

## License

- **Code** (Python, shell scripts, notebook code cells) is licensed under the
  **MIT License** -- see [`LICENSE`](./LICENSE).
- **Text, figures, and slides** (Markdown documentation, notebook narrative,
  generated figures, Beamer sources) are licensed under the
  **Creative Commons Attribution 4.0 International License**
  ([CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/)).
- **Imaging and phenotypic data** derive from the OpenNeuro Brain Tumor
  Connectomics datasets ([ds001226](https://openneuro.org/datasets/ds001226),
  [ds002080](https://openneuro.org/datasets/ds002080)), released under CC0.
  Please cite Aerts et al. (2018, 2022) when using the data.

## Citation

If you use this repository, please cite it via [`CITATION.cff`](./CITATION.cff)
(GitHub shows a "Cite this repository" button).

---

**Last Updated**: March 3, 2026  
**Finse 2026 Workshop: Mathematical Challenges in Brain Mechanics**

