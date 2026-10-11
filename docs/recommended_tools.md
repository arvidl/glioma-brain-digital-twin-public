# Recommended Tools for Finse 2026

A curated list of domain-specific software for neuroimaging, registration, mesh generation, and visualization.

---

## MRtrix3

**What it does**: Tractography, fiber orientation estimation from DWI, advanced diffusion analysis.

**Why useful**: Extract white-matter tracts connecting tumor to motor cortex; compute tract integrity metrics (mean FA, MD).

**Installation**:
```bash
# macOS
brew install mrtrix3

# Linux
wget https://www.mrtrix.org/download/mrtrix3-latest.tar.gz
tar xzf mrtrix3-latest.tar.gz && cd mrtrix3
./configure && ./build
export PATH=$PWD/bin:$PATH
```

**Usage hint**:
```bash
# Fiber orientation
dwi2fod tournier dwi.nii gz wm_fod.nii.gz -mask brain_mask.nii.gz

# Whole-brain tractography
tckgen wm_fod.nii.gz 100k.tck -algorithm iFOD2 -select 100k

# Tumor-specific connectivity
tckgen wm_fod.nii.gz tumor_connectivity.tck -seed tumor_mask.nii.gz
```

---

## FSL (FMRIB Software Library)

**What it does**: fMRI preprocessing (motion correction, registration), brain extraction (BET), distortion correction (TOPUP), DTI analysis.

**Why useful**: Standardized preprocessing pipeline; BET automatically extracts brain from T1w (robust even with tumors); TOPUP corrects EPI distortion.

**Installation**:
```bash
# macOS/Linux
# Download from: https://fsl.fmrib.ox.ac.uk/fsldownloads_registration
# or via conda (limited features)
conda install -c conda-forge fsl-core -y
```

**Usage hint**:
```bash
# Brain extraction (handles pathology well)
bet T1w.nii.gz T1w_brain.nii.gz -R

# fMRI preprocessing
feat_model.fsf  # create .fsf design file, run FEAT GUI or:
feat design.fsf &

# Distortion correction (requires reverse-phase EPI)
topup --imain=AP_PA.nii.gz --datain=acqparams.txt --config=b02b0.cnf --out=topup_results
```

---

## ANTs (Advanced Normalization Tools)

**What it does**: Deformable image registration (within-subject, subject-to-template), multimodal registration.

**Why useful**: Register individual T1w to MNI template; longitudinal alignment of preop→postop scans; tumor mask mapping.

**Installation**:
```bash
# conda-forge (recommended)
conda install -c conda-forge ants -y

# or from source
git clone https://github.com/ANTsX/ANTs.git && cd ANTs
mkdir build && cd build && cmake .. && make -j4
```

**Usage hint**:
```bash
# Register to MNI template
antsRegistrationSyN.sh -d 3 -f MNI152_T1_1mm.nii.gz -m T1w.nii.gz -o t1w2mni_

# Transform tumor mask to template space
antsApplyTransforms -d 3 \
  -i tumor_mask.nii.gz \
  -r MNI152_T1_1mm.nii.gz \
  -t t1w2mni_1Warp.nii.gz -t t1w2mni_0GenericAffine.mat \
  -o tumor_mask_mni.nii.gz

# Longitudinal registration (preop → postop)
antsRegistrationSyN.sh -d 3 -f preop_T1w.nii.gz -m postop_T1w.nii.gz -o prepost_
```

---

## fMRIPrep

**What it does**: End-to-end fMRI preprocessing with HCP-style outputs (CIFTI, 91k grayordinates).

**Why useful**: Reproducible, published protocol; handles head motion, distortion, normalization automatically; outputs in BIDS-Derivatives standard.

**Installation**:
```bash
# Conda (used in this project)
conda env create -f environment/environment_fmriprep.yml
conda activate cas-fmriprep

# Docker (alternative)
docker pull nipreps/fmriprep:25.2.4

# Singularity (HPC clusters)
singularity pull docker://nipreps/fmriprep:25.2.4
```

**Usage hint**:
```bash
# This project's wrapper (handles session isolation, FreeSurfer reuse)
bash scripts/run_fmriprep.sh --subject PAT16 --session preop

# Docker alternative
docker run --rm \
  -v /path/to/bids:/bids \
  -v /path/to/output:/out \
  nipreps/fmriprep:25.2.4 \
  /bids /out participant \
  --participant_label PAT16 \
  --fs-license-file license.txt

# Check outputs
ls /path/to/output/sub-PAT*/ses-*/func/*space-T1w*bold.nii.gz
```

---

## FreeSurfer

**What it does**: Cortical surface reconstruction, tissue segmentation, cortical thickness, parcellations (Desikan-Killiany, Glasser).

**Why useful**: Defines gray matter/white matter boundary for tumor extent; atlas-based ROI locations; 7T-quality surfaces even at 3T.

**Installation**:
```bash
# Download from https://surfer.nmr.mgh.harvard.edu/fswiki/DownloadAndInstall
# or via Homebrew (macOS)
brew tap freesurfer/freesurfer
brew install freesurfer

# Set license
cp license.txt $FREESURFER_HOME/license.txt
```

**Usage hint**:
```bash
# Full pipeline (takes ~24 h)
recon-all -i T1w.nii.gz -s PAT16 -all

# Extract cortical parcellation in subject space
mri_aparc2aseg --old-ribbon --s PAT16

# Convert surface to native VoxelSpace
mri_surf2vol --surfval lh.thickness --identity PAT16 \
  --mkmask --fillribbon --o lh_thickness.nii.gz
```

---

## ITK-SNAP

**What it does**: Interactive 3D image segmentation and visualization. Manual or semi-automatic segmentation tools.

**Why useful**: Visualize tumor boundary in 3D; validate automated segmentation; export mask overlays for quality control.

**Installation**:
```bash
# macOS
brew install itksnap

# Linux
wget https://sourceforge.net/projects/itksnap/files/itk-snap-latest-Linux-x86_64.tar.gz
tar xzf itk-snap-latest-Linux-x86_64.tar.gz

# Windows/others
# Download from: http://www.itksnap.org/pmwiki/pmwiki.php?n=Downloads.SNAP3
```

**Usage hint**:
```
1. File → Open Main Image → T1w.nii.gz
2. Segmentation → Initialize from scratch
3. Tools → Paint/Bubble (semi-automatic region growing)
4. File → Export Segmentation → tumor_mask.nii.gz
```

---

## 3D Slicer

**What it does**: 3D visualization, DICOM viewer, segmentation, registration, surgical planning.

**Why useful**: Visualize multimodal stacks (T1w, T2w, FLAIR) in 3D; interactive tumor tracing; deformable registration; surgical trajectory planning.

**Installation**:
```bash
# Download from: https://download.slicer.org/
# macOS: Slicer-5.6.0-macosx-amd64.dmg
# Linux: Slicer-5.6.0-linux-amd64.tar.gz

# Conda (limited, basic install)
conda install -c conda-forge 3dslicer
```

**Usage hint**:
```
1. Load DICOM series: File → Add DICOM Data
2. Segment: Modules → Segmentation → Create segmentation
3. Draw tumour: Paintbrush tool
4. Export: File → Save (exports as .nii.gz)
5. Register: Modules → Registration → Deformable Registration
```

---

## ParaView

**What it does**: Scientific visualization and postprocessing of unstructured mesh data (VTK format).

**Why useful**: Visualize FEniCS outputs (displacement, stress, pressure fields); publication-quality renderings; tensor glyphs for diffusion data.

**Installation**:
```bash
# Conda (recommended)
conda install -c conda-forge paraview -y

# or from source (large build)
wget https://www.paraview.org/files/v5.12/ParaView-v5.12.0.tar.gz
```

**Usage hint**:
```python
# FEniCS → ParaView
from dolfinx.io import XDMFFile

with XDMFFile(domain.comm, "solution.xdmf", "w") as xdmf:
    xdmf.write_mesh(domain)
    xdmf.write_function(uh)  # writes time series if transient

# Then: Open in ParaView GUI
# File → Open solution.xdmf
# Color by field, apply isosurfaces, export to PNG/video
```

---

## Gmsh

**What it does**: 3D mesh generation (tetrahedral/hexahedral), parametric geometry definition, mesh quality control.

**Why useful**: Generate finite element mesh from tumor segmentation; refine near lesion boundary; export to FEniCS format.

**Installation**:
```bash
# Conda (recommended)
conda install -c conda-forge gmsh gmsh-python -y

# Source (full features)
wget https://gmsh.info/bin/Linux/gmsh-4.12.2-Linux64.tgz
```

**Usage hint**:
```python
# Python API: create a simple brain geometry with tumor
import gmsh

gmsh.initialize()
gmsh.model.add("brain_tumor")

# Add a box (brain domain)
brain = gmsh.model.occ.addBox(0, 0, 0, 100, 100, 100, 1)

# Add a sphere (tumor)
tumor = gmsh.model.occ.addSphere(50, 50, 50, 15, 2)

# Mark regions
gmsh.model.occ.synchronize()
gmsh.model.addPhysicalGroup(3, [brain], name="Brain")
gmsh.model.addPhysicalGroup(3, [tumor], name="Tumor")

# Mesh: finer near tumor
gmsh.option.setNumber("Mesh.CharacteristicLengthMin", 5)
gmsh.option.setNumber("Mesh.CharacteristicLengthMax", 15)
gmsh.model.mesh.generate(3)
gmsh.write("brain_tumor_mesh.msh")
gmsh.finalize()

# Import in FEniCS
from dolfinx.io import gmshio
domain, cell_tags, facet_tags = gmshio.read_from_msh("brain_tumor_mesh.msh", rank=2)
```

---

## Pipeline-Internal Scripts (No External Installation)

The following analysis steps are implemented as self-contained Python scripts
within the repository, requiring only standard scientific Python packages
(scipy, numpy, nibabel, nilearn):

| Script | Purpose | Replaces |
|--------|---------|----------|
| `compute_fc.py` | FC matrices from fMRIPrep BOLD | Manual nilearn workflow |
| `compute_rshrf.py` | rsHRF parameter maps (FWHM, Height, Time2peak) | rsHRF BIDS App (unmaintained pyyawt dep) |
| `compute_tvb_connectome.py` | SC matrices from tractography | Manual tck2connectome workflow |

## Summary Table

| Tool | Primary Use | Install Method | Platform Support | Learning Curve |
|------|-------------|-----------------|---|---|
| MRtrix3 | DWI, tractography | brew/download | macOS, Linux | Moderate |
| FSL | fMRI preprocessing, BET, TOPUP | conda/download | macOS, Linux | Moderate |
| ANTs | Registration, warping | conda/source | macOS, Linux, Docker | Moderate |
| fMRIPrep | Standardized fMRI pipeline | Conda/Docker/Singularity | macOS, Linux | Low |
| FreeSurfer | Cortical surfaces, segmentation | download/brew | macOS, Linux | Moderate |
| RESSEG | Post-op cavity segmentation | pip (+ PyTorch) | Any | Low |
| ITK-SNAP | Interactive segmentation | download/brew | macOS, Linux, Windows | Low |
| 3D Slicer | 3D visualization, planning | download/conda | macOS, Linux, Windows | Low |
| ParaView | FEM visualization | conda/source | macOS, Linux, Windows | Moderate |
| Gmsh | Mesh generation | conda/download | Any | Moderate |

