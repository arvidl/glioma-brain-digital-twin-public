# Neuroimaging Primer for Applied Mathematicians

A practical introduction to MRI physics, image processing, and software tools for computational modelers working with brain imaging data.

## What is MRI?

Magnetic Resonance Imaging exploits nuclear spin dynamics in a strong magnetic field (~1.5–3 T clinically). By applying radiofrequency pulses and analyzing the signal decay, we measure tissue-specific relaxation times: T1 (spin-lattice) and T2 (spin-spin).

### Standard Anatomical Sequences

- **T1-weighted (T1w)**: Gray matter darker than white matter. Excellent anatomical contrast. Typical TR=500–1000 ms, TE=10–30 ms.
  - Formula: Signal ∝ ρ(1 − e^{−TR/T1}) e^{−TE/T2}
  
- **T2-weighted (T2w)**: White matter darker than gray matter; cerebrospinal fluid (CSF) bright. Good for detecting edema and lesions. TR=2000–3000 ms, TE=80–120 ms.

- **FLAIR (Fluid-Attenuated Inversion Recovery)**: T2w with CSF nulled via inversion recovery. Superior for detecting white matter lesions near ventricles. TI=2000–2700 ms.

- **DWI (Diffusion-Weighted Imaging)**: Sensitized to water diffusion. Restricted diffusion (acute stroke, tumor cellularity) appears bright. Quantified by apparent diffusion coefficient (ADC = S₀ exp(−b·D), where b is diffusion weighting in s/mm²).

- **fMRI (Functional MRI)**: Blood-oxygen-level-dependent (BOLD) contrast via T2*. Echo-planar imaging (EPI) acquires entire brain in 2–3 s with low spatial resolution (~3 mm) and high temporal resolution. BOLD signal indirectly measures neural activity via hemodynamics.

## Voxels and Image Coordinates

MRI data is a 3D rectilinear grid of **voxels** (volumetric pixels). A typical 3 T T1w scan: 256×256×176 voxels at 1×1×1 mm resolution = 256×256×176 mm field of view.

### Voxel Index Space vs. Physical Space

- **Voxel coordinates** (i, j, k): array indices ∈ [0, N_i) × [0, N_j) × [0, N_k).
- **Physical coordinates** (x, y, z): millimeters in patient or scanner space, typically with origin at isocenter.

Conversion via the **affine matrix** (see next section).

### Right-Handed vs. Left-Handed Conventions

NIfTI follows **RAS+ (Right-Anterior-Superior positive)** but stores data in memory as LPI (Left-Posterior-Inferior). Always check the qform/sform codes in the NIfTI header.

## Affine Matrices (4×4 Voxel-to-World Transformation)

The fundamental tool for registering imaging data to anatomical templates. The NIfTI affine matrix M is a 4×4 homogeneous transformation:

```
[x]     [m₀₀  m₀₁  m₀₂  m₀₃] [i]
[y]  =  [m₁₀  m₁₁  m₁₂  m₁₃] [j]
[z]     [m₂₀  m₂₁  m₂₂  m₂₃] [k]
[1]     [0    0    0    1   ] [1]
```

Where:
- **Upper-left 3×3 block**: rotation + scaling + shear
- **Right column**: translation offset
- **Bottom row**: preserves homogeneous coordinates

### Decomposition

Any affine matrix can be decomposed as:

M = T · R · S · H

where T is translation, R is rotation, S is scaling (voxel dimensions), and H is optional shear.

For a diagonal-dominant matrix (typical):
- Diagonal entries ≈ voxel dimensions (mm/voxel)
- Off-diagonal entries encode rotation angles (often small)

### Example: Identity Affine
```
[1  0  0  -127.5]   (center image at origin)
[0  1  0  -127.5]
[0  0  1   -87.5]
[0  0  0     1  ]
```
applies to 256×256×176 voxel grid.

## Common Artifacts

**Motion artifact**: Subject head movement during acquisition → ghosting or blurring along phase-encoding direction.

**Susceptibility artifact**: Field inhomogeneity near air-tissue interfaces (sinuses, ear canals). Worst in EPI.

**Aliasing (wrap-around)**: Undersample FOV → anatomy folds into image. Corrected by zero-padding or GRAPPA.

**Ringing (Gibbs)**: High-frequency truncation at tissue boundaries.

**Geometric distortion**: Non-linear B₀ inhomogeneity. Corrected with field maps or reversed-phase acquisitions (TOPUP in FSL).

**Pulsation artifact**: CSF/blood flow → ghosting. Minimize with flow compensation or saturation bands.

## NIfTI Format (.nii.gz)

The Neuroimaging Informatics Technology Initiative standard format. A gzipped file containing:

1. **Header (348 bytes)**: voxel dimensions, data type, affine matrix, qform/sform codes, description.
2. **Image data**: 3D (or 4D with time) array. Integer or float, endian specified.

### Key Header Fields

- `dim[]`: array dimensions
- `pixdim[]`: voxel sizes (mm, seconds)
- `affine`: 4×4 voxel-to-mm transformation
- `descrip`: up to 80-char description
- `intent_code`: statistical map type (if applicable)

### Nibabel Reading Example

```python
import nibabel as nib
img = nib.load('T1w.nii.gz')
data = img.get_fdata()  # numpy array, float
affine = img.affine
header = img.header
voxel_dims = img.header.get_zooms()
```

## Key Neuroimaging Software

- **FSL (FMRIB Software Library)**: Established toolkit for fMRI preprocessing, DTI, registration, statistics. Command-line focused.
- **SPM (Statistical Parametric Mapping)**: Matlab-based. Gold standard for fMRI GLM and VBM.
- **AFNI (Analysis of Functional NeuroImages)**: Comprehensive fMRI suite, excellent 3D visualization.
- **ANTs (Advanced Normalization Tools)**: State-of-art registration, especially multimodal and longitudinal.
- **FreeSurfer**: Cortical surface extraction, thickness mapping, Desikan-Killiany/Glasser parcellation.
- **fMRIPrep**: Containerized end-to-end fMRI preprocessing (HCP-style outputs).

## Useful Python Packages

- **nibabel**: Read/write NIfTI, DICOM, other formats. Core tool.
- **nilearn**: High-level neuroimaging statistics: GLM, connectivity, plotting. Built on nibabel, scikit-learn.
- **dipy**: Diffusion imaging & tractography. DTI tensor fitting, CSD, streamline algorithms.
- **pybids**: BIDS dataset validation & querying. Parse folder structure automatically.
- **nipype**: Workflow engine wrapping FSL, SPM, AFNI, ANTs. Reproducibility + parallelization.
- **fury**: 3D visualization of tractography, brain surfaces.
- **scipy, numpy**: Fundamental numerical computing.
- **matplotlib, plotly**: 2D/3D plotting.

## Summary Table

| Contrast | Best For | Typical TE (ms) | Typical TR (ms) | SNR |
|----------|----------|---|---|---|
| T1w | Anatomy, lesion borders | 10–30 | 500–1000 | High |
| T2w | Pathology, edema | 80–120 | 2000–3000 | Medium |
| FLAIR | WM lesions, TIA | 100–150 | 9000 | Medium |
| DWI | Acute stroke, tumor | 50–100 | 5000 | Low |
| fMRI (BOLD) | Neural activity | 30 | 2000 | Very low |

