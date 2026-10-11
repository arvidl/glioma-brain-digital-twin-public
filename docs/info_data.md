## The Best Match: Aerts et al. (2022) — Brain Tumor Connectome Dataset

This is the dataset most directly relevant to your project. It was explicitly designed for TVB-style whole-brain modeling in brain tumor patients:

- **25 brain tumor patients** (11 glioma WHO II–III, 14 meningioma) + 11 healthy controls
- **Modalities**: T1w, dMRI (for tractography/connectome), resting-state fMRI (BOLD)
- **Pre- and post-surgery** scans (6 months apart) — enabling modeling of how resection changes dynamics and mechanics
- **TVB-ready outputs already provided**: structural connectivity matrices, region-wise BOLD time series, hemodynamic response functions per ROI
- **Available on OpenNeuro**: [ds002080](https://doi.org/10.18112/openneuro.ds002080.v4.0.0) (BIDS format)
- **Also on EBRAINS** with TVB-formatted connectomes

This dataset is almost tailor-made for what you're envisioning: you could run both TVB (neural dynamics around a tumor) and a mechanics twin (how the tumor alters tissue stiffness and deformation) on the same subjects, and compare pre- vs. post-surgery.



The **Aerts et al. (2022)** dataset on OpenNeuro is the clear winner for your Finse project. Here's why it's compelling:

1. It has all three modalities you need (sMRI, dMRI, fMRI) — matching your own healthy-subject data
2. TVB connectomes are already computed, so you can compare your TVB pipeline output against published results
3. The pre/post-surgery design lets you ask a unique mechanics question: *how does surgical resection change the mechanical stress distribution?* — the tumor cavity creates a new boundary condition
4. The glioma cases (WHO II–III) involve infiltrating tumors that alter white matter fiber architecture — directly relevant to your dMRI-derived anisotropic constitutive laws
5. It's BIDS-formatted, so your existing fMRIPrep/QSIPrep/MRtrix3 pipeline should work with minimal modification

This could become a second test bed alongside your healthy-subject data, demonstrating the framework on a clinically relevant case where both neural dynamics (TVB: how does the tumor disrupt functional connectivity?) and mechanics (FEniCSx: how does the tumor's altered stiffness affect the stress field?) are relevant questions.

Would you like me to draft a section for the concept note on this, or start scripting the download and pipeline adaptation?

Sources:
- [Aerts et al. (2022) — Pre- and post-surgery brain tumor multimodal MRI data for computational modelling](https://www.nature.com/articles/s41597-022-01806-4)
- [OpenNeuro ds002080 — BTC_postop dataset](https://doi.org/10.18112/openneuro.ds002080.v4.0.0)


## BTC_preop (ds001226  version 5.0.0 2022-09-11)

aws s3 sync --no-sign-request s3://openneuro.org/ds001226 ds001226-download/

References and Links

https://doi.org/10.1523/ENEURO.0083-18.2018

https://pubmed.ncbi.nlm.nih.gov/32194282/

https://openfmri.org/dataset/ds001226/



Aerts, H and Marinazzo, D (2022). BTC_preop. OpenNeuro. [Dataset] doi: doi:10.18112/openneuro.ds001226.v5.0.0

{
    "Name": "BTC_preop",
    "License": "CC0",
    "Authors": [
        "Aerts, H",
        "Marinazzo, D"
    ],
    "Acknowledgements": "We would like to thank Prof. Dr. Van Roost and Prof. Dr. Eric Achten for their support in recruiting and testing patients at the Ghent University Hospital. We are also grateful to Stephanie Bogaert, Pieter Vandemaele and Ben Jeurissen for their technical assistance in setting up the scanning protocols. Further, we would like to thank Stephanie Bogaert, Robby De Pauw, Iris Coppieters, Jeroen Kregel, Mireille Augustijn, Helena Verhelst, and Hannes Almgren for their help in acquiring the data.",
    "HowToAcknowledge": "This dataset was obtained from the OpenNeuro database.",
    "Funding": [
        "Special Research Funds (BOF) of the University of Ghent (01MR0210 and 01J10715)",
        "Interuniversity Attraction Poles Program of the Belgian Federal Government (P7/11)"
    ],
    "ReferencesAndLinks": [
        "https://doi.org/10.1523/ENEURO.0083-18.2018",
        "https://pubmed.ncbi.nlm.nih.gov/32194282/",
        "https://openfmri.org/dataset/ds001226/"
    ],
    "BIDSVersion": "1.0.2",
    "DatasetDOI": "doi:10.18112/openneuro.ds001226.v5.0.0"
}

README
Brain Tumor Connectomics Data

Pre-operative data of 11 glioma patients, 14 meningioma patients and 11 control subjects that were used in the papers

Aerts H, Schirner M, Jeurissen B, Van Roost D, Achten E, Ritter P, Marinazzo D. Modeling Brain Dynamics in Brain Tumor Patients Using the Virtual Brain. eNeuro. 2018 Jun 4;5(3):ENEURO.0083-18.2018. doi: 10.1523/ENEURO.0083-18.2018. PMID: 29911173; PMCID: PMC6001263.

and

Aerts H, Schirner M, Dhollander T, Jeurissen B, Achten E, Van Roost D, Ritter P, Marinazzo D. Modeling brain dynamics after tumor resection using The Virtual Brain. Neuroimage. 2020 Jun;213:116738. doi: 10.1016/j.neuroimage.2020.116738. Epub 2020 Mar 16. PMID: 32194282.

Contact information: Name: Hannelore Aerts & Daniele Marinazzo Email: daniele.marinazzo@ugent.be

Compared to the initial database, 6 patients were excluded: 2 because of glioma grade 4, 3 because of subtentorial tumor, 1 because of absence of MRI data (subdural grid).

Of all subjects the following data were acquired:

T1w MPRAGE anatomical scan (anat)
resting-state fMRI (func)
multi-shell HARDI diffusion-weighted MRI (dwi, acq=AP)
short DWI with reverse phase encoding directions (dwi, acq=PA)
cognitive assessment using the Cambridge Neuropsychological Test Automated Battery (CANTAB): MOT, RVP, RTI, SSP & SOC
questionnaires assessing demographic information, lifestyle habits & emotional functioning
The "derivatives" folder contains

tumor masks, obtained with a combination of manual delineation and disconnectome
time series, structural and functional connectivity matrices, and resting state HRF for each ROI. The structural connectivity (SC) is derived with the TVB pipeline (https://github.com/BrainModes/TVB-empirical-data-pipeline) with manual segmentation when necessary. The regions are according to the Desikan-Killiany atlas. The resting state HRF is obtained with the toolbox described here Wu GR, Colenbier N, Van Den Bossche S, Clauw K, Johri A, Tandon M, Marinazzo D. rsHRF: A toolbox for resting-state HRF estimation and deconvolution. Neuroimage. 2021 Dec 1;244:118591. doi: 10.1016/j.neuroimage.2021.118591. Epub 2021 Sep 21. PMID: 34560269.
A companion dataset, containing the postoperatory data, is accessible at https://openneuro.org/datasets/ds002080




## BTC_postop  (ds002080  version 5.0.0 2022-09-11)

Hannelore Aerts and Daniele Marinazzo (2022). BTC_postop. OpenNeuro. [Dataset] doi: doi:10.18112/openneuro.ds002080.v4.0.0

aws s3 sync --no-sign-request s3://openneuro.org/ds002080 ds002080-download/

README

Brain Tumor Connectomics Data

Post-operative data of 7 glioma patients, 12 meningioma patients (1 [sub-PAT11] with bad data quality) and 10 control subjects. Out of the 11 glioma patients, 14 meningioma patients, and 11 healthy controls that were included pre-surgically ("BTC_preop, ds001226" on OpenNeuro), 7 glioma patients (1 drop-out, 1 no resection, 2 end of study), 12 meningioma patients (1 drop-out, 1 MRI not possible because of cochlear implant), and 10 healthy controls (1 drop-out) agreed to participate post-operatively.

Data used in the papers

Aerts H, Schirner M, Jeurissen B, Van Roost D, Achten E, Ritter P, Marinazzo D. Modeling Brain Dynamics in Brain Tumor Patients Using the Virtual Brain. eNeuro. 2018 Jun 4;5(3):ENEURO.0083-18.2018. doi: 10.1523/ENEURO.0083-18.2018. PMID: 29911173; PMCID: PMC6001263.

and

Aerts H, Schirner M, Dhollander T, Jeurissen B, Achten E, Van Roost D, Ritter P, Marinazzo D. Modeling brain dynamics after tumor resection using The Virtual Brain. Neuroimage. 2020 Jun;213:116738. doi: 10.1016/j.neuroimage.2020.116738. Epub 2020 Mar 16. PMID: 32194282.

Contact information: Name: Hannelore Aerts & Daniele Marinazzo Email: daniele.marinazzo@ugent.be

Compared to the initial database, 6 patients were excluded: 2 because of glioma grade 4, 3 because of subtentorial tumor, 1 because of absence of MRI data (subdural grid).

Of all subjects the following data were acquired:

T1w MPRAGE anatomical scan (anat)
resting-state fMRI (func)
multi-shell HARDI diffusion-weighted MRI (dwi, acq=AP)
short DWI with reverse phase encoding directions (dwi, acq=PA)
cognitive assessment using the Cambridge Neuropsychological Test Automated Battery (CANTAB): MOT, RVP, RTI, SSP & SOC
questionnaires assessing demographic information, lifestyle habits & emotional functioning
The "derivatives" folder contains

tumor masks, obtained with a combination of manual delineation and disconnectome
time series, structural and functional connectivity matrices, and resting state HRF for each ROI.
rsHRF parameters obtained with the rsHRF toolbox described here Wu GR, Colenbier N, Van Den Bossche S, Clauw K, Johri A, Tandon M, Marinazzo D. rsHRF: A toolbox for resting-state HRF estimation and deconvolution. Neuroimage. 2021 Dec 1;244:118591. doi: 10.1016/j.neuroimage.2021.118591. Epub 2021 Sep 21. PMID: 34560269.
fMRI quality control: Esteban O, Birman D, Schaer M, Koyejo OO, Poldrack RA, Gorgolewski KJ; MRIQC: Advancing the Automatic Prediction of Image Quality in MRI from Unseen Sites; PLOS ONE 12(9):e0184661; doi:10.1371/journal.pone.0184661.
diffusion quality control Bastiani M, Cottaar M, Fitzgibbon SP, Suri S, Alfaro-Almagro F, Sotiropoulos SN, Jbabdi S, Andersson JLR. Automated quality control for within and between studies diffusion MRI data using a non-parametric framework for movement and distortion correction. Neuroimage. 2019 Jan 1;184:801-812. doi: 10.1016/j.neuroimage.2018.09.073. Epub 2018 Sep 26. PMID: 30267859; PMCID: PMC6264528. The structural connectivity (SC) is derived with the TVB pipeline (https://github.com/BrainModes/TVB-empirical-data-pipeline) with manual segmentation when necessary. The regions are according to the Desikan-Killiany atlas.

A companion dataset, containing the preoperatory data, is accessible at https://openneuro.org/datasets/ds001226

{
    "Name": "BTC_preop",
    "License": "CC0",
    "Authors": [
        "Aerts, H",
        "Marinazzo, D"
    ],
    "Acknowledgements": "We would like to thank Prof. Dr. Van Roost and Prof. Dr. Eric Achten for their support in recruiting and testing patients at the Ghent University Hospital. We are also grateful to Stephanie Bogaert, Pieter Vandemaele and Ben Jeurissen for their technical assistance in setting up the scanning protocols. Further, we would like to thank Stephanie Bogaert, Robby De Pauw, Iris Coppieters, Jeroen Kregel, Mireille Augustijn, Helena Verhelst, and Hannes Almgren for their help in acquiring the data.",
    "HowToAcknowledge": "This dataset was obtained from the OpenNeuro database.",
    "Funding": [
        "Special Research Funds (BOF) of the University of Ghent (01MR0210 and 01J10715)",
        "Interuniversity Attraction Poles Program of the Belgian Federal Government (P7/11)"
    ],
    "ReferencesAndLinks": [
        "https://doi.org/10.1523/ENEURO.0083-18.2018",
        "https://pubmed.ncbi.nlm.nih.gov/32194282/",
        "https://openfmri.org/dataset/ds001226/"
    ],
    "BIDSVersion": "1.0.2",
    "DatasetDOI": "doi:10.18112/openneuro.ds001226.v5.0.0"
}

References and Links

https://www.eneuro.org/content/5/3/ENEURO.0083-18.2018

https://pubmed.ncbi.nlm.nih.gov/32194282/


Available Derivatives

Acknowledgements

These derivatives were generated on the Texas Advanced Computing Center Frontera computing system [1] through their Pathways allocation. This work was also funded by the NIH BRAIN Initiative.

[1]: Dan Stanzione, John West, R. Todd Evans, Tommy Minyard, Omar Ghattas, and Dhabaleswar K. Panda. 2020. Frontera: The Evolution of Leadership Computing at the National Science Foundation. In Practice and Experience in Advanced Research Computing (PEARC ’20), July 26–30, 2020, Portland, OR, USA. ACM, New York, NY, USA, 11 pages.https://doi.org/10.1145/3311790.3396656

ds002080-mriqc

Download from S3

aws s3 sync --no-sign-request s3://openneuro-derivatives/mriqc/ds002080-mriqc ds002080-mriqc

-----

## Subject selection

_I want to target two patients occurring in both ds001226-download (preop) and in ds002080-download (post) that has the diagnose of glioma. Can you select such pair of patients?_


Let me explore your workspace to find these datasets and identify patients with glioma that appear in both.I found the overlap. Let me summarize what I see.

There are **7 glioma patients** present in both the preop (ds001226) and postop (ds002080) datasets:

| Subject | Tumor type & grade | Sex | Age | Location |
|---|---|---|---|---|
| sub-PAT05 | Oligo-astrocytoma II | F | 40 | Frontal |
| sub-PAT07 | Ependymoma II | M | 55 | Temporal |
| sub-PAT16 | Anaplastic astrocytoma II-III | M | 39 | Fronto-temporal |
| sub-PAT20 | Anaplastic astrocytoma III | F | 70 | Parietal |
| sub-PAT26 | Anaplastic astrocytoma III | M | 61 | Temporal |
| sub-PAT28 | Oligodendroglioma II | M | 44 | Frontal |

(Note: sub-PAT22, PAT27, PAT29, PAT31 are glioma patients in preop only — they didn't participate postop.)

This project uses **sub-PAT16** (Anaplastic astrocytoma II-III, fronto-temporal) as a representative case from the Brain Tumor Connectomics (BTC) dataset. The full 25-patient cohort is available on OpenNeuro: [ds001226 (BTC_preop, v5.0.0)](https://openneuro.org/datasets/ds001226/versions/5.0.0) and [ds002080 (BTC_postop, v4.0.0)](https://openneuro.org/datasets/ds002080/versions/4.0.0).

Here's a quick summary of your selected pair:

**sub-PAT16** — Male, 39 years old, Anaplastic astrocytoma grade II-III, fronto-temporal location, tumor size 50.24 cm³

Both have complete data (T1w, fMRI, dMRI) and derivatives (tumor masks, structural connectivity, functional connectivity, HRF) in both the preop and postop datasets. Would you like me to do anything further with these two patients — for example, inspect their available imaging data or derivatives in more detail?


## BIDS_preop_postop validation

Good — the data is already cleanly organized with `ses-preop` and `ses-postop` session labels. Now let me check the existing dataset-level files and JSON sidecars.Now let me build the BIDS dataset. I'll create the folder structure, copy the raw data and derivatives, and create the metadata files.Now let me create the BIDS metadata files.Now let me copy the derivatives and then install/run bids-validator.The dataset passes BIDS validation. Let me also check if there are any warnings by running with verbose output.The **BIDS_preop_postop** folder is ready and passes BIDS validation with **0 errors and 0 warnings**.

Here's what it contains:

```
BIDS_preop_postop/
├── dataset_description.json
├── participants.tsv / .json
├── README
├── CHANGES
├── sub-PAT16/
│   ├── ses-preop/   (anat, func, dwi)
│   └── ses-postop/  (anat, func, dwi)
└── derivatives/
    ├── TVB/          (SC, FC, ROI time series, HRF — preop)
    ├── tumor_masks/  (T1-space and MNI-space tumor masks)
    └── rsHRF/        (resting-state HRF maps — both sessions)
```

Each subject × session has T1w anatomy, resting-state fMRI, and two DWI acquisitions (AP + PA phase encoding). The derivatives include pre-computed TVB connectivity matrices, tumor masks, and rsHRF parameter maps.


## Context: Finse 2026 Workshop

Now, I want to put these data (in the BIDS_preop_postop folder) into my contribution at the Finse 2026 Workshop,  entitled:
"Multiparametric MRI (sMRI, dMRI, fMRI) as data for a  Glioma Brain Digital Twin  in the context of mathematical challenges in brain mechanics". For this, I want to make a GitHub repo with both Python and Bash scripts and didactic Jupyter notebooks in Python. I want to define a proper environment.yml for a conda environment. The code and data should be available and executable on both a local MBP M4 Max with 128 GB unified memory (Apple silicon), on a local DELL Precision laptop running Ubuntu 24.04, with a Xeon W-11955M x 16, 128 GB RAM, and an NVIDIA RTX A5000 Laptop GPU with 16 GB VRAM (CUDA), and also be able to run in Google Colab as 1-click notebooks. Locally, I have Freesurfer,  Latex (TexShop), and I am open to install other tools that is recommended. Please advice.


Now write all the base files in parallel:Now write the environment files and setup scripts in parallel with utility modules:Now write all Python utility modules in parallel:Now write the bash scripts and check_env.py together:Now create all 8 notebooks. I'll use parallel Task agents for the two groups:Write four Jupyter notebooks (as .ipynb JSON files) to the following paths. Each should be a fully-formed, didactic notebook with markdown explanations, code cells, and learning objectives. The audience is applied mathematicians who may be new to neuroimaging.

Target paths:
- <REPO_ROOT>/notebooks/NB00_Setup_and_Verification.ipynb
- <REPO_ROOT>/notebooks/NB01_BIDS_Exploration.ipynb
- <REPO_ROOT>/notebooks/NB02_Structural_MRI_Analysis.ipynb
- <REPO_ROOT>/notebooks/NB03_Diffusion_MRI_and_Tractography.ipynb

Write each notebook using Python to generate the JSON. Here's a script to create all four:

```python
import json, os

REPO = "<REPO_ROOT>"
NB_DIR = f"{REPO}/notebooks"
os.makedirs(NB_DIR, exist_ok=True)

def nb(cells):
    return {
        "nbformat": 4, "nbformat_minor": 5,
        "metadata": {
            "kernelspec": {"display_name": "Python 3 (finse26)", "language": "python", "name": "finse26"},
            "language_info": {"name": "python", "version": "3.11.0"}
        },
        "cells": cells
    }

def md(source):
    return {"cell_type": "markdown", "metadata": {}, "source": source}

def code(source):
    return {"cell_type": "code", "execution_count": None, "metadata": {}, "outputs": [], "source": source}
```

Then create each notebook. Make each one substantial with:
- A title markdown cell
- A Colab setup cell (detects if in Colab, installs packages, clones repo, sets DATA_ROOT)
- Multiple sections with markdown explanations and working code
- At least 10-15 cells per notebook

NB00 content: Environment verification, GPU detection, load one NIfTI from data/BIDS_preop_postop, display metadata, test imports, show project structure.

NB01 content: Load BIDSLayout from pybids, summarize subjects/sessions/modalities, read participants.tsv, display acquisition parameters from JSON sidecars, show file tree, explain BIDS standard.

NB02 content: Load T1w NIfTIs for PAT16 (preop and postop), display slices with nilearn, load and overlay tumor masks, compute tumor volume, compare pre vs post anatomy, explain brain anatomy for mathematicians.

NB03 content: Load DWI data (bvals, bvecs), explain diffusion tensor model mathematically (the diffusion tensor D, eigenvalues, FA formula), compute DTI metrics with dipy (FA, MD, AD, RD), display maps, explain tractography concept, show b-value table.

The paths for data in the notebooks should use:
```python
import os, sys
from pathlib import Path
# Detect environment
if 'google.colab' in sys.modules:
    REPO_ROOT = Path('/content/finse-2026-glioma-dtwin')
    DATA_ROOT = REPO_ROOT / 'data' / 'BIDS_preop_postop'
else:
    REPO_ROOT = Path(__file__).parent.parent if '__file__' in dir() else Path('..') 
    DATA_ROOT = REPO_ROOT / 'data' / 'BIDS_preop_postop'
sys.path.insert(0, str(REPO_ROOT))
```

Write the notebooks as valid JSON files. Make them detailed and didactic. Save all four files.Write four Jupyter notebooks (as .ipynb JSON files) to the following paths. Each should be a fully-formed, didactic notebook aimed at applied mathematicians new to neuroimaging and brain modeling.

Target paths:
- <REPO_ROOT>/notebooks/NB04_Functional_MRI_Analysis.ipynb
- <REPO_ROOT>/notebooks/NB05_Structural_and_Functional_Connectivity.ipynb
- <REPO_ROOT>/notebooks/NB06_Tumor_Impact_Analysis.ipynb
- <REPO_ROOT>/notebooks/NB07_Brain_Mechanics_FEniCSx.ipynb

Use this Python to create notebooks:

```python
import json, os
from pathlib import Path

REPO = "<REPO_ROOT>"
NB_DIR = f"{REPO}/notebooks"
os.makedirs(NB_DIR, exist_ok=True)

def nb(cells):
    return {"nbformat": 4, "nbformat_minor": 5,
            "metadata": {"kernelspec": {"display_name": "Python 3 (finse26)", "language": "python", "name": "finse26"},
                         "language_info": {"name": "python", "version": "3.11.0"}},
            "cells": cells}

def md(source):
    return {"cell_type": "markdown", "metadata": {}, "source": source}

def code(source):
    return {"cell_type": "code", "execution_count": None, "metadata": {}, "outputs": [], "source": source}
```

NB04 - Functional MRI Analysis:
Content: Load rsHRF parameter maps (FWHM, Height, Time2peak), load ROI time series from derivatives/TVB/ROIts.dat, compute power spectrum (FFT), visualize BOLD time series for selected ROIs, compare pre vs post-op rsHRF parameters, explain hemodynamic response function and BOLD physics, functional connectivity matrix from ROI correlations.

NB05 - Structural and Functional Connectivity:
Content: Load SC and FC matrices from derivatives/TVB using scipy.io.loadmat, visualize as heatmaps, compute graph metrics (degree, clustering, path length, global efficiency) using networkx, compare SC vs FC (structure-function coupling), show network visualization with networkx, explain connectome mathematics.

NB06 - Tumor Impact Analysis (Pre vs Post-op Comparison):
Content: Multi-modal comparison of pre vs post-op for both patients. Compare tumor volume from masks (nibabel), compare FA in peritumoral region, compare FC matrices pre vs post, compare rsHRF parameters, bar charts and statistics, clinical interpretation. Note: PAT16 only has TVB derivatives for preop (postop TVB not available - explain why and what this means).

NB07 - Brain Mechanics with FEniCSx:
Content: This is the key mathematical notebook. Structure:
1. Mathematical background: governing equations (equilibrium equation, strain tensor definition, constitutive law for isotropic linear elasticity, Lame parameters)
2. FEniCSx installation check with clear Colab instructions
3. Create a simple 3D box mesh representing brain tissue
4. Define material properties (Young's modulus ~2500 Pa for brain, Poisson ratio ~0.45)
5. Solve static linear elasticity under gravity loading
6. Visualize displacement field
7. Extend to inhomogeneous case: add a spherical "tumor" subregion with different stiffness (8000 Pa)
8. Compare stress distribution with/without tumor
9. Discuss: What does elevated stress near a tumor mean biologically?
10. Brief intro to growth models and Terzaghi consolidation for brain

For the Colab FEniCSx installation, include:
```python
# In Colab, FEniCSx must be installed via apt/pip:
# !apt-get install -y libopenmpi-dev
# !pip install fenics-dolfinx mpi4py petsc4py -q
```

Make all notebooks at least 12-15 cells, with rich markdown explanations and equations (using LaTeX in markdown cells, e.g. $\sigma = \mathbf{C} : \varepsilon$). Save all four files.
