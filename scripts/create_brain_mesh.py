#!/usr/bin/env python3
"""
create_brain_mesh.py
────────────────────
Convert a FreeSurfer aparc+aseg segmentation volume into a tagged
tetrahedral finite-element mesh suitable for DOLFINx.

Pipeline:
  1. Load aparc+aseg NIfTI and remap ~1000 FreeSurfer labels into
     a small set of FE tissue classes (WM, GM, tumor, CSF, …).
  2. Optionally overlay a binary tumor mask (tumor class overrides
     the underlying tissue label).
  3. Extract the brain surface via marching cubes.
  4. Generate a volume tetrahedral mesh with Gmsh.
  5. Tag each tetrahedron from the label volume.
  6. Mark boundary facets (skull outer surface, cavity surface).
  7. Export as XDMF for DOLFINx (cell tags + facet tags).

Usage:
  conda activate cas-fenics
  python scripts/create_brain_mesh.py \\
      --aseg derivatives/registered_t1w/sub-PAT16/ses-postop/aparc+aseg_space-T1w.nii.gz \\
      --tumor data/BIDS_preop_postop/derivatives/tumor_masks/sub-PAT16/anat/sub-PAT16_space_T1_label-tumor_binary.nii.gz \\
      --output derivatives/meshes/sub-PAT16_brain.xdmf \\
      --mesh-size 3.0

Requires: nibabel, numpy, scipy, scikit-image, gmsh, meshio, dolfinx
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

import numpy as np

# ---------------------------------------------------------------------------
# FreeSurfer label → FE tissue class mapping
# ---------------------------------------------------------------------------

# FE tissue tags (integers stored in the mesh)
TAG_WM = 1
TAG_GM = 2
TAG_TUMOR = 3
TAG_CSF = 4
TAG_DEEP = 5  # deep gray nuclei (thalamus, caudate, putamen, …)

TAG_NAMES = {
    TAG_WM: "white_matter",
    TAG_GM: "gray_matter",
    TAG_TUMOR: "tumor",
    TAG_CSF: "csf",
    TAG_DEEP: "deep_nuclei",
}

# FreeSurfer label sets (from FreeSurferColorLUT.txt)
_FS_WM_LABELS = {
    2, 41,        # Left/Right-Cerebral-White-Matter
    77, 78, 79,   # WM-hypointensities
    251, 252, 253, 254, 255,  # Corpus callosum
}

_FS_CORTICAL = set(range(1000, 1036)) | set(range(2000, 2036))

_FS_CSF_LABELS = {
    0,            # Unknown / background (outside brain)
    4, 5,         # Left/Right-Lateral-Ventricle
    14, 15,       # 3rd/4th-Ventricle
    24,           # CSF
    43, 44,       # Left/Right-Inf-Lat-Vent
    72,           # 5th-Ventricle
}

_FS_DEEP_LABELS = {
    10, 11, 12, 13,       # Left thalamus, caudate, putamen, pallidum
    17, 18,               # Left hippocampus, amygdala
    26, 28,               # Left accumbens, ventral DC
    49, 50, 51, 52,       # Right thalamus, caudate, putamen, pallidum
    53, 54,               # Right hippocampus, amygdala
    58, 60,               # Right accumbens, ventral DC
    16,                   # Brain-Stem
}


def remap_aseg(labels: np.ndarray) -> np.ndarray:
    """Remap FreeSurfer aparc+aseg labels to FE tissue tags.

    Unlabeled brain voxels default to GM. Background (0) maps to CSF
    so that the marching-cubes surface sits at the brain boundary.
    """
    out = np.full_like(labels, TAG_GM, dtype=np.int32)

    for lab in _FS_WM_LABELS:
        out[labels == lab] = TAG_WM
    for lab in _FS_CORTICAL:
        out[labels == lab] = TAG_GM
    for lab in _FS_CSF_LABELS:
        out[labels == lab] = TAG_CSF
    for lab in _FS_DEEP_LABELS:
        out[labels == lab] = TAG_DEEP

    # Anything mapped to CSF with label 0 is "outside brain" – keep as CSF
    # so that the isosurface separates brain from non-brain.
    return out


def overlay_tumor(
    tissue_vol: np.ndarray,
    tumor_nii,
    aseg_nii,
) -> np.ndarray:
    """Overlay a binary tumor mask onto the tissue volume.

    The tumor mask may live in a different affine (e.g. native T1 vs
    co-registered T1w). We resample into the aseg voxel grid.
    """
    import nibabel as nib
    from nibabel.processing import resample_from_to

    tumor_resampled = resample_from_to(tumor_nii, aseg_nii, order=0)
    tumor_data = np.asarray(tumor_resampled.dataobj)
    tissue_vol[tumor_data > 0.5] = TAG_TUMOR
    return tissue_vol


# ---------------------------------------------------------------------------
# Surface extraction
# ---------------------------------------------------------------------------

def extract_brain_surface(tissue_vol: np.ndarray, affine: np.ndarray):
    """Extract the outer brain surface using marching cubes.

    Returns vertices (Nx3 in mm) and faces (Mx3).
    """
    from skimage.measure import marching_cubes

    brain_mask = (tissue_vol != TAG_CSF).astype(np.float32)

    verts, faces, _, _ = marching_cubes(brain_mask, level=0.5)

    # Transform voxel coordinates to world (mm) coordinates
    verts_mm = (affine[:3, :3] @ verts.T).T + affine[:3, 3]

    return verts_mm, faces


def simplify_surface(verts, faces, target_faces: int = 80000):
    """Reduce triangle count while preserving geometry.

    Uses vertex clustering via a voxel grid as a simple decimation
    strategy that doesn't require VTK or pyvista.
    """
    if len(faces) <= target_faces:
        return verts, faces

    try:
        import pyvista as pv
        mesh = pv.PolyData(verts, np.column_stack([
            np.full(len(faces), 3, dtype=np.int32), faces
        ]))
        ratio = target_faces / len(faces)
        decimated = mesh.decimate(1.0 - ratio)
        return (
            np.asarray(decimated.points),
            decimated.faces.reshape(-1, 4)[:, 1:].astype(np.int32),
        )
    except (ImportError, Exception):
        # pyvista not available or decimate failed – return original
        return verts, faces


# ---------------------------------------------------------------------------
# Gmsh volume meshing
# ---------------------------------------------------------------------------

def create_volume_mesh(
    verts: np.ndarray,
    faces: np.ndarray,
    mesh_size: float = 3.0,
    verbosity: int = 3,
):
    """Create a tetrahedral volume mesh from a triangulated surface.

    Parameters
    ----------
    verts : (N, 3) float array of vertex coordinates in mm.
    faces : (M, 3) int array of triangle vertex indices.
    mesh_size : target element size in mm.
    verbosity : Gmsh verbosity (0=silent, 5=debug).

    Returns
    -------
    tet_points : (P, 3) float array of node coordinates.
    tet_cells  : (T, 4) int array of tetrahedron node indices.
    """
    import gmsh

    gmsh.initialize()
    gmsh.option.setNumber("General.Verbosity", verbosity)
    gmsh.model.add("brain")

    # Add surface triangulation as a discrete model
    s_tag = 1
    gmsh.model.addDiscreteEntity(2, s_tag)

    node_tags = np.arange(1, len(verts) + 1, dtype=np.int64)
    gmsh.model.mesh.addNodes(
        2, s_tag,
        node_tags,
        verts.ravel(),
    )

    elem_tags = np.arange(1, len(faces) + 1, dtype=np.int64)
    gmsh.model.mesh.addElementsByType(
        s_tag, 2,  # type 2 = 3-node triangle
        elem_tags,
        (faces + 1).ravel().astype(np.int64),  # 1-based
    )

    gmsh.model.mesh.createTopology()

    # Create a volume from the surface
    sl = gmsh.model.geo.addSurfaceLoop([s_tag])
    gmsh.model.geo.addVolume([sl])
    gmsh.model.geo.synchronize()

    # Mesh parameters
    gmsh.option.setNumber("Mesh.MeshSizeMax", mesh_size)
    gmsh.option.setNumber("Mesh.MeshSizeMin", mesh_size * 0.3)
    gmsh.option.setNumber("Mesh.Algorithm3D", 1)  # Delaunay

    print(f"  Generating 3D mesh (target element size = {mesh_size} mm) ...")
    t0 = time.time()
    gmsh.model.mesh.generate(3)
    print(f"  Meshing done in {time.time() - t0:.1f}s")

    # Extract tets
    node_tags_out, coords, _ = gmsh.model.mesh.getNodes()
    tet_types, tet_tags, tet_nodes = gmsh.model.mesh.getElements(dim=3)

    gmsh.finalize()

    # Re-index to 0-based
    coords = coords.reshape(-1, 3)
    tag_to_idx = {int(t): i for i, t in enumerate(node_tags_out)}
    tet_connectivity = tet_nodes[0].reshape(-1, 4)
    tet_cells = np.array(
        [[tag_to_idx[int(n)] for n in row] for row in tet_connectivity],
        dtype=np.int32,
    )

    print(f"  Mesh: {len(coords)} nodes, {len(tet_cells)} tetrahedra")
    return coords, tet_cells


# ---------------------------------------------------------------------------
# Cell tagging from label volume
# ---------------------------------------------------------------------------

def tag_cells_from_volume(
    tet_points: np.ndarray,
    tet_cells: np.ndarray,
    tissue_vol: np.ndarray,
    affine: np.ndarray,
) -> np.ndarray:
    """Assign a tissue tag to each tetrahedron by sampling the label
    volume at each cell centroid.

    Returns an array of int32 tags, one per tetrahedron.
    """
    centroids = tet_points[tet_cells].mean(axis=1)  # (T, 3)

    # World (mm) → voxel coordinates via inverse affine
    inv_affine = np.linalg.inv(affine)
    vox_coords = (inv_affine[:3, :3] @ centroids.T).T + inv_affine[:3, 3]
    vox_ijk = np.round(vox_coords).astype(int)

    tags = np.full(len(tet_cells), TAG_GM, dtype=np.int32)
    for idx in range(len(tet_cells)):
        i, j, k = vox_ijk[idx]
        if (
            0 <= i < tissue_vol.shape[0]
            and 0 <= j < tissue_vol.shape[1]
            and 0 <= k < tissue_vol.shape[2]
        ):
            tags[idx] = tissue_vol[i, j, k]

    # Report tag distribution
    for tag_val, name in TAG_NAMES.items():
        count = int(np.sum(tags == tag_val))
        if count > 0:
            print(f"    {name}: {count} cells ({100*count/len(tags):.1f}%)")

    return tags


# ---------------------------------------------------------------------------
# Boundary facet tagging
# ---------------------------------------------------------------------------

FACET_OUTER = 1   # skull / outer brain surface
FACET_CAVITY = 2  # resection cavity surface

def tag_boundary_facets(
    tet_points: np.ndarray,
    tet_cells: np.ndarray,
    cell_tags: np.ndarray,
):
    """Identify boundary facets and classify them.

    A boundary facet belongs to exactly one tetrahedron. Among those:
    - If the adjacent cell is CSF (TAG_CSF) → cavity/ventricle surface
    - Otherwise → outer brain surface (skull constraint)

    Returns
    -------
    facet_cells : (F, 3) int array of boundary triangle node indices.
    facet_tags  : (F,) int array of facet tags.
    """
    from collections import Counter

    # Build face → cell adjacency
    face_counter = Counter()
    face_cell_map = {}

    for cell_idx, cell in enumerate(tet_cells):
        # 4 faces per tet, each face is a sorted triple
        for face_local in [(0, 1, 2), (0, 1, 3), (0, 2, 3), (1, 2, 3)]:
            face_key = tuple(sorted(cell[list(face_local)]))
            face_counter[face_key] += 1
            face_cell_map[face_key] = cell_idx

    # Boundary faces appear exactly once
    boundary_faces = [f for f, c in face_counter.items() if c == 1]
    print(f"  Boundary facets: {len(boundary_faces)}")

    facet_cells = np.array(boundary_faces, dtype=np.int32)
    facet_tags = np.full(len(boundary_faces), FACET_OUTER, dtype=np.int32)

    for i, face_key in enumerate(boundary_faces):
        adj_cell = face_cell_map[face_key]
        if cell_tags[adj_cell] == TAG_CSF:
            facet_tags[i] = FACET_CAVITY

    n_outer = int(np.sum(facet_tags == FACET_OUTER))
    n_cavity = int(np.sum(facet_tags == FACET_CAVITY))
    print(f"    Outer (skull): {n_outer}, Cavity/ventricle: {n_cavity}")

    return facet_cells, facet_tags


# ---------------------------------------------------------------------------
# Export to XDMF for DOLFINx
# ---------------------------------------------------------------------------

def export_xdmf(
    tet_points: np.ndarray,
    tet_cells: np.ndarray,
    cell_tags: np.ndarray,
    facet_cells: np.ndarray,
    facet_tags: np.ndarray,
    output_path: str | Path,
):
    """Write the tagged mesh to XDMF files readable by DOLFINx.

    Creates:
      <output>.xdmf / .h5  -- volume mesh with cell tags
      <output>_facets.xdmf / .h5 -- boundary facets with facet tags
    """
    import meshio

    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Volume mesh
    vol_mesh = meshio.Mesh(
        points=tet_points,
        cells=[("tetra", tet_cells)],
        cell_data={"tissue_tag": [cell_tags]},
    )
    vol_path = output_path.with_suffix(".xdmf")
    meshio.write(vol_path, vol_mesh)
    print(f"  Volume mesh → {vol_path}")

    # Boundary facets
    facet_mesh = meshio.Mesh(
        points=tet_points,
        cells=[("triangle", facet_cells)],
        cell_data={"boundary_tag": [facet_tags]},
    )
    facet_path = output_path.with_name(output_path.stem + "_facets.xdmf")
    meshio.write(facet_path, facet_mesh)
    print(f"  Facet mesh  → {facet_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Convert FreeSurfer aparc+aseg to tagged FE mesh for DOLFINx",
    )
    parser.add_argument(
        "--aseg", required=True,
        help="Path to aparc+aseg NIfTI (in T1w space)",
    )
    parser.add_argument(
        "--tumor", default=None,
        help="Path to binary tumor mask NIfTI (optional)",
    )
    parser.add_argument(
        "--output", required=True,
        help="Output path (e.g. derivatives/meshes/sub-PAT16_brain.xdmf)",
    )
    parser.add_argument(
        "--mesh-size", type=float, default=3.0,
        help="Target tetrahedral element size in mm (default: 3.0)",
    )
    parser.add_argument(
        "--target-faces", type=int, default=80000,
        help="Target surface triangle count after decimation (default: 80000)",
    )
    parser.add_argument(
        "--subsample", type=int, default=1,
        help="Subsample the label volume by this factor before meshing (default: 1, no subsampling). "
             "Use 2 or 3 for coarser meshes suitable for interactive notebooks.",
    )
    parser.add_argument(
        "--verbosity", type=int, default=3,
        help="Gmsh verbosity level 0-5 (default: 3)",
    )
    args = parser.parse_args()

    import nibabel as nib

    # 1. Load and remap aparc+aseg
    print(f"[1/6] Loading aparc+aseg: {args.aseg}")
    aseg_nii = nib.load(args.aseg)
    aseg_data = np.asarray(aseg_nii.dataobj).astype(np.int32)
    affine = aseg_nii.affine
    print(f"  Shape: {aseg_data.shape}, unique labels: {len(np.unique(aseg_data))}")

    print("[2/6] Remapping labels to FE tissue classes")
    tissue_vol = remap_aseg(aseg_data)

    # 2. Overlay tumor mask
    if args.tumor:
        print(f"  Overlaying tumor mask: {args.tumor}")
        tumor_nii = nib.load(args.tumor)
        tissue_vol = overlay_tumor(tissue_vol, tumor_nii, aseg_nii)
        n_tumor = int(np.sum(tissue_vol == TAG_TUMOR))
        vox_vol = abs(np.linalg.det(affine[:3, :3]))
        print(f"  Tumor voxels: {n_tumor} ({n_tumor * vox_vol / 1000:.1f} cm³)")

    # 2b. Subsample volume for coarser meshes
    if args.subsample > 1:
        s = args.subsample
        print(f"  Subsampling volume by factor {s} (nearest-neighbor)")
        from scipy.ndimage import zoom
        tissue_vol = zoom(tissue_vol, 1.0 / s, order=0).astype(np.int32)
        # Update affine to reflect the larger voxels
        scale = np.diag([s, s, s, 1.0]).astype(float)
        affine = affine @ scale
        print(f"  New shape: {tissue_vol.shape}")

    # 3. Extract brain surface
    print("[3/6] Extracting brain surface (marching cubes)")
    verts, faces = extract_brain_surface(tissue_vol, affine)
    print(f"  Surface: {len(verts)} vertices, {len(faces)} triangles")

    # 4. Simplify surface
    if len(faces) > args.target_faces:
        print(f"[3b]  Simplifying surface to ~{args.target_faces} triangles")
        verts, faces = simplify_surface(verts, faces, args.target_faces)
        print(f"  After simplification: {len(verts)} vertices, {len(faces)} triangles")

    # 5. Volume meshing with Gmsh
    print("[4/6] Generating tetrahedral volume mesh (Gmsh)")
    tet_points, tet_cells = create_volume_mesh(
        verts, faces,
        mesh_size=args.mesh_size,
        verbosity=args.verbosity,
    )

    # 6. Tag cells from label volume
    print("[5/6] Tagging cells from label volume")
    cell_tags = tag_cells_from_volume(tet_points, tet_cells, tissue_vol, affine)

    # 7. Tag boundary facets
    print("[6/6] Tagging boundary facets")
    facet_cells, facet_tags = tag_boundary_facets(tet_points, tet_cells, cell_tags)

    # 8. Export
    print("Exporting XDMF ...")
    export_xdmf(tet_points, tet_cells, cell_tags, facet_cells, facet_tags, args.output)
    print("Done.")


if __name__ == "__main__":
    main()
