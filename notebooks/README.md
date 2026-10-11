# Glioma Brain Digital Twin - Educational Notebooks

A comprehensive set of Jupyter notebooks teaching applied mathematicians how to work with neuroimaging data for brain tumor digital twin modeling.

## Notebook Overview

### NB00: Environment Setup and Verification (14 cells)
**Goal**: Establish the computational environment and verify all dependencies

**Key Topics**:
- GPU detection and CUDA availability
- Core package verification (nibabel, nilearn, dipy, bids, etc.)
- Project repository structure
- BIDS data overview
- NIfTI file metadata inspection

**Learning Outcomes**:
- Understand the computational requirements
- Verify all tools are properly installed
- Navigate the BIDS data structure
- Load and inspect a sample MRI file

**Target Audience**: Applied mathematicians new to neuroimaging computing

---

### NB01: BIDS Data Exploration (22 cells)
**Goal**: Understand and navigate the Brain Imaging Data Structure (BIDS)

**Key Topics**:
- BIDS standard explanation and advantages
- PyBIDS layout initialization and querying
- Subject and session management
- File inventory by modality (T1w, T2w, DWI)
- Participants demographics (including height, weight, fMRI TR)
- Session-level clinical & cognitive data (`*_sessions.tsv`)
  - Psychosocial questionnaires: STAI, PSWQ, ERQ, UCLA Loneliness
  - CANTAB cognitive battery: MOT, RTI, RVP, SOC, SSP
  - Pre-op vs post-op comparison with visualisation
- JSON sidecars and acquisition parameters
- DWI-specific parameters and b-value information

**Learning Outcomes**:
- Understand BIDS as a standardized data format
- Programmatically query BIDS datasets
- Interpret acquisition parameters from JSON metadata
- Explore session-level phenotypic data and cognitive outcomes
- Assess data completeness and quality

**Mathematical Context**: BIDS enables reproducible, machine-readable data management essential for validated computational models.

---

### NB02: Structural MRI Analysis (16 cells)
**Goal**: Load, visualize, and analyze T1-weighted structural images and tumor segmentations

**Key Topics**:
- Brain anatomy fundamentals for mathematicians
- T1-weighted image characteristics and interpretation
- Orthogonal slice visualization (sagittal, coronal, axial)
- Pre- and post-operative image comparison
- Tumor mask loading and analysis
- Tumor volume computation
- Intensity-based statistics and tissue classification

**Learning Outcomes**:
- Understand brain anatomy in mathematical context
- Load NIfTI images and interpret spatial geometry
- Visualize volumetric data
- Compute tumor volumes from segmentation masks
- Compare serial imaging for treatment assessment

**Mathematical Concepts**:
- Affine transformations and coordinate systems
- 3D image indexing and slicing
- Volume computation from voxel counts
- Image processing fundamentals (thresholding, connected components)

---

### NB03: Diffusion MRI and Tractography (18 cells)
**Goal**: Understand and compute diffusion tensor imaging (DTI) metrics

**Key Topics**:
- Diffusion tensor theory and eigenvalue decomposition
- DWI image loading and b-value/b-vector interpretation
- Multi-shell diffusion acquisition
- DTI metric definitions:
  - Fractional Anisotropy (FA)
  - Mean Diffusivity (MD)
  - Axial Diffusivity (AD)
  - Radial Diffusivity (RD)
- Full-brain DTI metric maps (using DIPY)
- Fiber tractography concepts and algorithms
- Clinical applications for glioma surgery

**Learning Outcomes**:
- Understand water diffusion in biological tissue
- Interpret the diffusion tensor as a 3×3 symmetric matrix
- Compute eigenvalues and eigenvectors from diffusion data
- Visualize DTI metrics and identify white matter
- Understand fiber tractography for surgical planning

**Mathematical Framework**:
The diffusion equation governs water movement in tissue:
```
∂P/∂t = D · ∇²P
```

The diffusion tensor D is a 3×3 symmetric matrix:
```
D = V · Λ · V^T
```

where eigenvalues λ₁ ≥ λ₂ ≥ λ₃ describe directional diffusivities.

**Key Metrics**:
- FA = √(3/2) · √[(λ₁-MD)² + (λ₂-MD)² + (λ₃-MD)²] / √(λ₁² + λ₂² + λ₃²)
- MD = (λ₁ + λ₂ + λ₃) / 3
- AD = λ₁ (diffusion along fiber axis)
- RD = (λ₂ + λ₃) / 2 (diffusion perpendicular to fibers)

---

## Usage

### Prerequisites
- Python 3.11+
- Jupyter Notebook or JupyterLab
- BIDS dataset with preoperative and postoperative T1w and DWI scans

### Required Packages
```
nibabel>=4.0
nilearn>=0.10
dipy>=1.8
bids>=0.14
pandas>=1.5
numpy>=1.23
scipy>=1.10
matplotlib>=3.6
seaborn>=0.12
torch>=2.0  (for GPU support)
```

### Installation (Google Colab)
The notebooks automatically detect Colab environment and install packages:
```python
if 'google.colab' in sys.modules:
    # Colab setup code runs automatically
    !git clone https://github.com/finse/glioma-brain-digital-twin /content/finse-2026-glioma-dtwin
```

### Running the Notebooks
1. Start with **NB00** to verify your environment
2. Progress through **NB01** to understand your data structure
3. Use **NB02** for structural analysis and tumor segmentation
4. Complete with **NB03** for diffusion analysis and white matter assessment

Each notebook builds on previous knowledge but can be run independently.

---

## Data Requirements

The notebooks expect data organized in BIDS format:
```
data/BIDS_preop_postop/
├── participants.tsv
├── sub-PAT16/
│   ├── sub-PAT16_sessions.tsv
│   ├── ses-preop/
│   │   ├── anat/
│   │   │   ├── sub-PAT16_ses-preop_T1w.nii.gz
│   │   │   ├── sub-PAT16_ses-preop_T1w.json
│   │   │   └── ...
│   │   └── dwi/
│   │       ├── sub-PAT16_ses-preop_dwi.nii.gz
│   │       ├── sub-PAT16_ses-preop_dwi.bval
│   │       ├── sub-PAT16_ses-preop_dwi.bvec
│   │       └── ...
│   └── ses-postop/
│       └── ... (same structure)
└── participants.tsv
```

### Optional (for tumor analysis)
Tumor segmentation masks in derivatives:
```
derivatives/
└── masks/
    ├── sub-PAT16_ses-preop_space-T1_mask.nii.gz
    └── ...
```

---

## Learning Path for Applied Mathematicians

### Week 1: Data Foundations
- **NB00**: Understand the computational environment
- **NB01**: Learn BIDS and explore your dataset

### Week 2: Structural Analysis
- **NB02**: Load and visualize structural MRI
- Understand brain anatomy and tumor location
- Compute tumor volumes

### Week 3: Diffusion Analysis
- **NB03**: Learn diffusion tensor theory
- Compute DTI metrics and white matter integrity
- Understand fiber tractography

### Week 4: Integration
- Combine structural and diffusion information
- Prepare data for mathematical modeling
- Consider extensions to advanced models (HARDI, CSD)

---

## Key Mathematical Concepts

### 1. Coordinate Systems
- **Voxel coordinates**: Integer indices (i, j, k)
- **Physical coordinates**: (x, y, z) in millimeters
- **Stereotactic space**: Standard brain atlas (MNI152, ICBM)
- Affine transformations map between coordinate systems

### 2. Image as Data
- MRI images: 3D arrays of intensity values
- Voxel: Volume element (typically 1-2 mm³)
- NIfTI format: Compressed data + spatial information
- Metadata: Acquisition parameters in JSON sidecars

### 3. Diffusion Tensor Mathematics
- Water diffusion follows Einstein's equation
- Diffusion tensor: Symmetric positive-definite 3×3 matrix
- Eigendecomposition: Reveals principal diffusion directions
- FA quantifies directional preference [0, 1]

### 4. Five-Layer Digital Twin Architecture
- **Layer 1 (Geometric):** Patient-specific FE mesh from T1w segmentation
- **Layer 2 (Constitutive):** Heterogeneous material properties from dMRI
- **Layer 3 (Functional):** SC/FC connectivity from tractography and fMRI
- **Layer 4 (Simulation):** PDE solver (displacement, stress, strain) + neural dynamics
- **Layer 5 (Clinical Outcome):** CANTAB cognitive battery + psychosocial questionnaires
  validate whether predicted disruption translates to measured cognitive change

---

## Extending the Notebooks

### Advanced Topics
1. **Multi-shell diffusion**: HARDI, CSD, q-ball
2. **Functional MRI**: BOLD signal and task-based activation
3. **Perfusion imaging**: Cerebral blood flow and volume
4. **Network analysis**: Connectivity between brain regions
5. **Machine learning**: Automatic segmentation, outcome prediction

### Integration with Modeling
```python
# Example: Using DTI in tumor growth model
# du/dt = div(D(x) · grad(u)) + ρ·u(1-u)
# where D(x) is anisotropic diffusion tensor from DTI
# ρ is growth rate
# u is tumor cell density
```

---

## References and Further Reading

### BIDS Standard
- https://bids-standard.github.io/
- Gorgolewski et al. (2016). Brain Imaging Data Structure standard

### Neuroimaging Processing
- Nilearn: https://nilearn.github.io/
- DIPY: https://dipy.org/

### DTI Theory
- Basser & Pierpaoli (1996). Microstructural and physiological features of tissues elucidated by quantitative-diffusion-tensor MRI
- Le Bihan et al. (2001). Diffusion magnetic resonance imaging: A useful tool for neuroscience

### Glioma Modeling
- Clatz et al. (2005). Brain tumor segmentation with Deep Neural Networks
- Swanson et al. (2008). Quantifying errors in tumor-growth model extractions

### White Matter Anatomy
- Catani & Thiebaut de Schotten (2008). A diffusion tensor imaging tractography atlas for virtual in vivo dissections

---

## Authors and Citation

Created for the Finse 2026 Glioma Brain Digital Twin Project

**Educational Materials for Applied Mathematicians Learning Neuroimaging**

If using these notebooks, please cite:
```
Finse 2026 Glioma Brain Digital Twin Project
Jupyter Educational Notebooks
Data: BIDS-formatted preoperative and postoperative MRI
```

---

## Support and Issues

For questions about:
- **BIDS format**: See https://bids-standard.github.io/
- **nibabel/nilearn**: Check documentation or community forums
- **DIPY**: Visit https://dipy.org/documentation/stable/examples_index
- **DTI theory**: Consult Diffusion MRI textbooks and reviews

---

## License

These educational notebooks are provided as learning materials for the neuroimaging and applied mathematics communities.

