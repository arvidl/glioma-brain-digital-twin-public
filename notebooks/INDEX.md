# Glioma Brain Digital Twin - Notebook Index

Created: 2026-03-02 | Updated: 2026-03-03  
Target Audience: Applied Mathematicians New to Neuroimaging  
Status: Complete and Validated

---

## Quick Start Guide

### Step 1: Verify Your Environment
Start with **NB00_Setup_and_Verification.ipynb** to ensure all dependencies are installed and your GPU (if available) is detected.

**What you'll learn:**
- How to verify your computing environment
- Which neuroimaging packages you need
- How to load your first NIfTI file

**Time: 10-15 minutes**

---

### Step 2: Understand Your Data Structure
Work through **NB01_BIDS_Exploration.ipynb** to understand how BIDS organizes neuroimaging data and how to programmatically access it.

**What you'll learn:**
- What BIDS (Brain Imaging Data Structure) is and why it matters
- How to query a BIDS dataset using Python
- How to extract acquisition parameters from JSON sidecars
- How to understand b-values and diffusion acquisition

**Time: 20-30 minutes**

---

### Step 3: Analyze Structural Imaging
Use **NB02_Structural_MRI_Analysis.ipynb** to load, visualize, and analyze T1-weighted brain images and tumor segmentations.

**What you'll learn:**
- Brain anatomy fundamentals for mathematicians
- How to visualize 3D MRI data in different planes
- How to compute tumor volumes from segmentation masks
- How to compare pre- and post-operative images

**Time: 30-40 minutes**

---

### Step 4: Understand Diffusion MRI
Complete **NB03_Diffusion_MRI_and_Tractography.ipynb** to learn the mathematical foundations of DTI and compute clinically relevant metrics.

**What you'll learn:**
- How water diffusion reveals tissue microstructure
- The mathematics of the diffusion tensor (eigenvalue decomposition)
- How to compute FA, MD, AD, and RD metrics
- How fiber tractography works and why it matters for surgery

**Time: 45-60 minutes**

---

## Detailed Notebook Descriptions

### NB00: Environment Setup and Verification
**File:** `NB00_Setup_and_Verification.ipynb`  
**Size:** 9.7 KB | **Cells:** 14 (7 markdown, 7 code)  
**Difficulty:** Beginner

#### Topics
1. **GPU Detection and CUDA Support** - Check if your GPU can accelerate computations
2. **Core Package Verification** - Verify all neuroimaging tools are installed
3. **Project Structure Overview** - Navigate the repository
4. **BIDS Data Overview** - Find where your data is located
5. **Load and Inspect Sample NIfTI File** - Load your first MRI image

#### Key Outputs
- Confirmation that your environment is ready
- List of any missing packages
- Information about your first MRI file (shape, intensity range, metadata)

#### Prerequisites
- Python 3.11+ installed
- Jupyter Notebook or JupyterLab

---

### NB01: BIDS Data Exploration
**File:** `NB01_BIDS_Exploration.ipynb`  
**Size:** 14.4 KB | **Cells:** 18 (9 markdown, 9 code)  
**Difficulty:** Beginner to Intermediate

#### Topics
1. **BIDS Standard Overview** - What is BIDS and why it matters
2. **Load BIDS Layout and Summary Statistics** - Programmatically explore your dataset
3. **Explore File Types and Counts** - Inventory your data
4. **Participants Demographics** - Access subject information
5. **Acquisition Parameters from JSON Sidecars** - Read scanner settings
6. **DWI Acquisition Details** - Understand diffusion acquisition
7. **Subject-Level Summary** - See what data you have for each subject
8. **Key Takeaways** - BIDS enables reproducible, machine-readable research

#### Key Outputs
- List of all subjects and sessions
- Summary of file types and counts
- Acquisition parameters (TR, TE, flip angle, b-values, etc.)
- Participants demographic table

#### Prerequisites
- NB00 completed (environment verified)
- BIDS dataset available at expected location
- PyBIDS library installed

#### Key Concept
BIDS is essential for reproducible science. It standardizes how neuroimaging data is organized, enabling automated processing pipelines and data sharing.

---

### NB02: Structural MRI Analysis
**File:** `NB02_Structural_MRI_Analysis.ipynb`  
**Size:** 17.4 KB | **Cells:** 16 (8 markdown, 8 code)  
**Difficulty:** Intermediate

#### Topics
1. **Brain Anatomy Overview for Applied Mathematicians** - Essential anatomy explained for mathematical modeling
2. **Load and Visualize T1-Weighted Images** - Read structural MRI files
3. **Display Orthogonal Slices** - View brain in 3D (sagittal, coronal, axial)
4. **Compare Pre- and Post-operative Images** - Assess surgical changes
5. **Load and Analyze Tumor Masks** - Read segmentation data
6. **Visualize Tumor Overlay** - See tumor in anatomical context
7. **Summary and Key Insights** - Consolidate learning

#### Key Outputs
- Multi-plane visualization of brain MRI
- Tumor volume in cm³
- Statistical comparison of pre/post anatomy
- Visualization of tumor location relative to brain structures

#### Prerequisites
- NB00 and NB01 completed
- T1w images available in BIDS dataset
- Optional: tumor segmentation masks for full analysis

#### Key Mathematical Concepts
- Affine transformations (mapping between coordinate systems)
- 3D image indexing and slicing
- Volume computation from voxel counts: V = n_voxels × voxel_volume
- Image processing (thresholding, connected components)

#### For Modelers
T1-weighted images provide:
- Anatomical geometry for domain discretization
- Tissue classification (gray matter, white matter, CSF)
- Tumor location and extent
- Basis for geometric models of tumor growth

---

### NB03: Diffusion MRI and Tractography
**File:** `NB03_Diffusion_MRI_and_Tractography.ipynb`  
**Size:** 21.2 KB | **Cells:** 18 (9 markdown, 9 code)  
**Difficulty:** Intermediate to Advanced

#### Topics
1. **Diffusion Tensor Theory for Applied Mathematicians** - Mathematical foundations explained
2. **Load DWI Data and b-values/b-vectors** - Read diffusion-weighted images
3. **Visualize DWI Volumes** - See different diffusion weightings
4. **B-value Table and Acquisition Summary** - Understand diffusion protocol
5. **Compute DTI Metrics (Manual Approach)** - Calculate FA, MD, AD, RD by hand
6. **DTI Metrics Maps (DIPY-based)** - Full-brain metric computation
7. **Fiber Tractography Concepts** - Understand how fiber tracking works
8. **Summary and Clinical Applications** - Applications for glioma surgery

#### Key Outputs
- DTI metric maps (FA, MD, AD, RD)
- B-value acquisition summary
- Example eigenvalue decomposition
- Understanding of fiber tractography algorithms

#### Prerequisites
- NB00, NB01, NB02 completed
- DWI images with b-values and b-vectors in BIDS dataset

#### Key Mathematical Concepts

**The Diffusion Equation:**
```
∂P/∂t = D · ∇²P
```
where P is probability density and D is the diffusion tensor.

**The Diffusion Tensor:**
```
D = V · Λ · V^T = [Dxx  Dxy  Dxz]
                  [Dxy  Dyy  Dyz]
                  [Dxz  Dyz  Dzz]
```

**Eigenvalue Decomposition:**
- λ₁ ≥ λ₂ ≥ λ₃ (eigenvalues, ordered)
- v₁, v₂, v₃ (eigenvectors, principal diffusion directions)

**Key Metrics:**

1. **Fractional Anisotropy (FA):**
   ```
   FA = √(3/2) · √[(λ₁-MD)² + (λ₂-MD)² + (λ₃-MD)²] / √(λ₁² + λ₂² + λ₃²)
   Range: [0, 1]
   Interpretation: Degree of directional preference
   ```

2. **Mean Diffusivity (MD):**
   ```
   MD = (λ₁ + λ₂ + λ₃) / 3
   Interpretation: Average diffusion in all directions
   ```

3. **Axial Diffusivity (AD):**
   ```
   AD = λ₁
   Interpretation: Diffusion along fiber axis
   ```

4. **Radial Diffusivity (RD):**
   ```
   RD = (λ₂ + λ₃) / 2
   Interpretation: Diffusion perpendicular to fibers
   ```

#### Clinical Interpretations

| Tissue | FA | MD |
|--------|----|----|
| Healthy WM | 0.7-0.8 | Low |
| Gray matter | 0.2-0.3 | Moderate |
| Tumor core | <0.3 | High |
| Edema | Low | High |
| Infarct | Low | Low |

#### For Modelers
DTI provides:
- Anisotropic diffusion tensor D(x) for tumor growth models
- White matter integrity assessment (FA)
- Connectivity information via tractography
- Barrier effects to tumor growth along white matter

#### Fiber Tractography Concept
Streamline algorithms follow the principal diffusion direction (largest eigenvector) from seed points, reconstructing 3D fiber pathways. Critical for:
- Surgical planning (identifying eloquent pathways)
- Assessing tumor infiltration of white matter
- Connectivity analysis for network models

---

## Three-Track Structure

The notebooks are organized in three tracks:

- **Track A (NB00-NB08)**: Educational/workshop -- uses pre-computed TVB/rsHRF
  derivatives, works in Google Colab
- **Track B (NB09-NB17)**: Full pipeline -- requires local software, computes
  connectivity from pipeline outputs
- **Track C (NB\_C01-NB\_C09)**: Capstone series -- didactic, presentation-grade
  synthesis of the full coupling chain with biological/clinical motivation

NB15-NB17 in Track B parallel NB04-NB06 in Track A, but compute SC and FC
directly from the pipeline's fMRIPrep and MRtrix3 outputs instead of relying
on pre-computed TVB derivatives.

### Track C: Capstone Series (NB\_C01-NB\_C09)

The capstone series traces the full digital twin coupling chain from concept
to validation, with deep didactic treatment of each topic. All derived data
comes from the de novo pipeline (FreeSurfer, fMRIPrep, QSIPrep, MRtrix3).

| Notebook | Topic | Time | Difficulty |
|----------|-------|------|------------|
| NB\_C01 | Digital twin concept and data landscape | 30 min | Introductory |
| NB\_C02 | Clinical, cognitive, and psychosocial data | 30 min | Intermediate |
| NB\_C03 | Structural MRI, segmentation, and lesions | 40 min | Intermediate |
| NB\_C04 | Diffusion MRI, DTI maps, SC, and tractography | 45 min | Intermediate-Advanced |
| NB\_C05 | Resting-state fMRI, rsHRF, and functional connectivity | 45 min | Intermediate-Advanced |
| NB\_C06 | Brain mechanics, mass effect, and displacement | 40 min | Advanced |
| NB\_C07 | Neural dynamics and mechanics-dynamics coupling | 40 min | Advanced |
| NB\_C08 | Closing the loop: predicted vs observed | 30 min | Advanced |
| NB\_C09 | Synthesis and mathematical perspectives | 20 min | All levels |

## Estimated Time Investment

### Track A: Educational / Workshop (NB00-NB08)

| Notebook | Time | Difficulty | Prerequisites |
|----------|------|------------|---|
| NB00 | 10-15 min | Beginner | None |
| NB01 | 20-30 min | Beginner | NB00 |
| NB02 | 30-40 min | Intermediate | NB00, NB01 |
| NB03 | 45-60 min | Intermediate-Advanced | NB00, NB01, NB02 |
| NB04 | 45 min | Intermediate | NB00-NB03, TVB/rsHRF derivatives |
| NB05 | 60 min | Intermediate | NB04, TVB connectomes |
| NB06 | 45 min | Intermediate | NB04-NB05, both sessions |
| NB07 | 90 min | Advanced | NB00-NB03 |
| NB08 | 60 min | Advanced | NB05-NB07 |

### Track B: Full Pipeline (NB09-NB17)

| Notebook | Topic | Time | Prerequisites |
|----------|-------|------|---|
| NB09 | Preprocessing Pipeline Overview | 30-45 min | NB00-NB03 |
| NB10 | FreeSurfer QC | 15-20 min | FreeSurfer outputs |
| NB11 | fMRIPrep QC | 15-20 min | fMRIPrep outputs |
| NB12 | QSIPrep + MRtrix3 QC | 20-30 min | QSIPrep + MRtrix3 outputs |
| NB13 | Registration QC | 15-20 min | Co-registered outputs |
| NB14 | Pre-op vs Post-op Comparison | 30-45 min | All pipeline outputs + Step 5b |
| NB15 | Pipeline Functional Connectivity | 30 min | fMRIPrep + aparc+aseg (parallels NB04) |
| NB16 | Pipeline Structural Connectivity | 30 min | MRtrix3 tractography + SIFT2 (parallels NB05) |
| NB17 | Pipeline Longitudinal Connectomics | 30 min | NB14 + NB15 + NB16 (parallels NB06) |

### Freeview Inspection Scripts

| Script | Purpose |
|--------|---------|
| `freeview_freesurfer.sh` | FreeSurfer surfaces and parcellation |
| `freeview_registration.sh` | DWI-to-T1w registration overlay |
| `freeview_dti.sh` | DTI scalar maps (FA, MD, AD, RD) |
| `freeview_all.sh` | All modalities in T1w space |
| `freeview_preop_postop.sh` | Pre-op vs post-op comparison |
| `freeview_deformation.sh` | Displacement, Jacobian, cavity mask QC |

---

## Package Requirements

### Essential
```
nibabel>=4.0          # Read/write NIfTI files
pandas>=1.5           # Data manipulation
numpy>=1.23           # Numerical computing
matplotlib>=3.6       # Basic plotting
```

### Recommended
```
nilearn>=0.10         # Advanced visualization
dipy>=1.8             # Diffusion imaging
bids>=0.14            # BIDS utilities
scipy>=1.10           # Scientific computing
seaborn>=0.12         # Statistical visualization
```

### Optional
```
torch>=2.0            # GPU acceleration (CUDA-enabled)
jupyter>=1.0          # Notebook environment
```

---

## Data Organization

The notebooks expect BIDS-formatted data:

```
data/BIDS_preop_postop/
├── sub-PAT16/
│   ├── ses-preop/
│   │   ├── anat/
│   │   │   ├── sub-PAT16_ses-preop_T1w.nii.gz
│   │   │   └── sub-PAT16_ses-preop_T1w.json
│   │   └── dwi/
│   │       ├── sub-PAT16_ses-preop_dwi.nii.gz
│   │       ├── sub-PAT16_ses-preop_dwi.bval
│   │       ├── sub-PAT16_ses-preop_dwi.bvec
│   │       └── sub-PAT16_ses-preop_dwi.json
│   └── ses-postop/
│       └── (same structure)
└── participants.tsv
```

Optional derivatives:
```
derivatives/
└── masks/
    ├── sub-PAT16_ses-preop_space-T1_mask.nii.gz
    └── ...
```

---

## Running the Notebooks

### Local Jupyter
```bash
cd notebooks/
jupyter lab NB00_Setup_and_Verification.ipynb
```

### Google Colab
1. Open first notebook in Google Colab
2. Notebooks auto-detect Colab and install packages
3. Repository clones automatically
4. Data path adjusts automatically

### Independent Execution
Each notebook can run independently (with appropriate data), but sequential execution is recommended for learning progression.

---

## Key Learning Progression

### Phase 1: Foundations (30-45 minutes)
- **Goal:** Understand neuroimaging data and BIDS
- **Notebooks:** NB00, NB01
- **Outcome:** Can navigate BIDS datasets and understand acquisition parameters

### Phase 2: Structural Analysis (30-40 minutes)
- **Goal:** Load, visualize, and analyze brain anatomy
- **Notebooks:** NB02
- **Outcome:** Can load T1w images, compute tumor volumes, compare pre/post

### Phase 3: Diffusion Analysis (45-60 minutes)
- **Goal:** Understand DTI and white matter analysis
- **Notebooks:** NB03
- **Outcome:** Can compute DTI metrics, understand fiber tractography

### Phase 4: Integration (self-guided)
- **Goal:** Combine structural and diffusion data for modeling
- **Resources:** README.md, References section
- **Outcome:** Ready to build computational models

---

## Mathematical Preparation

These notebooks assume familiarity with:
- **Linear algebra:** Matrices, eigenvalues, eigenvectors
- **Calculus:** Partial derivatives, divergence, Laplacian
- **PDEs:** Basic diffusion equation (optional but helpful)
- **Python:** NumPy, basic data manipulation

No prior neuroimaging knowledge required!

---

## Common Questions

**Q: Do I need a GPU?**  
A: No. All analyses run on CPU, though GPU acceleration is available for full-brain tensor fitting.

**Q: Can I run notebooks individually?**  
A: Yes, but NB00 should be run first to verify environment, and NB02/NB03 assume you understand BIDS (NB01).

**Q: What if my data is organized differently?**  
A: The notebooks are designed for BIDS-organized data. If your data differs, you'll need to adjust file paths.

**Q: Where do I learn more?**  
A: See README.md for comprehensive references and further reading.

**Q: How do I use this for my own research?**  
A: Each notebook includes code you can adapt for your data. See README.md for extension ideas.

---

## Next Steps After Notebooks

1. **Explore Advanced Diffusion Models**
   - HARDI (High Angular Resolution Diffusion Imaging)
   - CSD (Constrained Spherical Deconvolution)
   - See DIPY documentation for implementation

2. **Build Growth Models**
   - Use structural anatomy as domain
   - Incorporate DTI as anisotropic diffusion coefficient
   - Couple with reaction-diffusion equations

3. **Machine Learning Integration**
   - Automatic segmentation (U-Net, etc.)
   - Outcome prediction
   - Image synthesis (preop to expected postop)

4. **Biomechanical Modeling**
   - Incorporate tissue elasticity
   - Model brain deformation
   - Include tumor mass effects

5. **Uncertainty Quantification**
   - Parameter estimation from clinical data
   - Sensitivity analysis
   - Validation against actual outcomes

---

## References

**BIDS Standard**
- https://bids-standard.github.io/
- Gorgolewski et al. (2016)

**Neuroimaging Libraries**
- Nilearn: https://nilearn.github.io/
- DIPY: https://dipy.org/

**DTI and Tractography**
- Basser & Pierpaoli (1996). MRI Connectives Project
- Le Bihan et al. (2001). Diffusion MRI concepts

**Glioma Modeling**
- Swanson et al. (2008). Quantifying errors in tumor-growth model extractions
- Clatz et al. (2005). Brain tumor segmentation

---

## Citation

If you use these notebooks, please cite:

```
Finse 2026 Glioma Brain Digital Twin Project
Educational Jupyter Notebooks for Applied Mathematicians
https://github.com/arvidl/glioma-brain-digital-twin-public
```

---

**Created:** 2026-03-02 | **Updated:** 2026-03-03  
**Status:** Complete and Validated  
**Notebooks:** NB00-NB03 (educational), NB09-NB17 (preprocessing pipeline + connectivity)
