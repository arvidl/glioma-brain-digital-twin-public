#!/usr/bin/env python3
"""
tck2trk.py — Convert MRtrix3 .tck to TrackVis .trk for Freeview.

TrackVis .trk files store streamline coordinates in "voxmm" space
(voxel indices × voxel sizes), which Freeview expects. MRtrix3 .tck
files store coordinates in scanner (world/RAS) space.

This script converts between the two using the reference image's
affine to map world → voxel coordinates.

Usage:
    python tck2trk.py <input.tck> <reference.nii.gz> <output.trk>

Requires: numpy, nibabel (both available in cas-qsiprep conda env)

CAS Brain Mechanics MRI — Finse 2026
"""

import struct
import sys

import nibabel as nib
import numpy as np


def read_tck(path):
    """Read a MRtrix3 .tck file. Returns list of (N,3) arrays."""
    with open(path, "rb") as f:
        header_bytes = bytearray()
        while True:
            line = f.readline()
            header_bytes.extend(line)
            if line.strip() == b"END":
                break

        offset = None
        for line in header_bytes.decode("latin-1").split("\n"):
            line = line.strip()
            if line.startswith("file:"):
                parts = line.split()
                offset = int(parts[-1])
                break

        if offset is None:
            raise ValueError("Could not find 'file:' offset in .tck header")

        f.seek(offset)
        data = f.read()

    floats = np.frombuffer(data, dtype="<f4").copy()
    coords = floats.reshape(-1, 3)

    # Split at NaN markers (end-of-streamline)
    streamlines = []
    current_start = 0
    for i in range(len(coords)):
        if np.isnan(coords[i, 0]):
            if i > current_start:
                streamlines.append(coords[current_start:i].copy())
            current_start = i + 1
        elif np.isinf(coords[i, 0]):
            if i > current_start:
                streamlines.append(coords[current_start:i].copy())
            break

    return streamlines


def scanner_to_trackvis(streamlines, ref_img):
    """Convert streamline coordinates from scanner RAS to TrackVis voxmm.

    TrackVis "voxmm" = voxel_index * voxel_size, where voxel_index is
    computed from the reference image affine. The TrackVis convention
    also places the origin at the corner of voxel (0,0,0), not its center,
    so we add 0.5 voxel shift.
    """
    affine = ref_img.affine
    voxel_sizes = ref_img.header.get_zooms()[:3]
    inv_affine = np.linalg.inv(affine)

    converted = []
    for sl in streamlines:
        # World (scanner RAS) → voxel indices
        ones = np.ones((len(sl), 1), dtype=np.float32)
        world_homo = np.hstack([sl, ones])
        voxel = (inv_affine @ world_homo.T).T[:, :3]

        # Voxel indices → TrackVis "voxmm" (shift by +0.5 for corner origin)
        voxmm = (voxel + 0.5) * np.array(voxel_sizes, dtype=np.float32)
        converted.append(voxmm.astype(np.float32))

    return converted


def write_trk(path, streamlines, ref_img):
    """Write a TrackVis .trk file (low-level binary approach for compatibility)."""
    shape = ref_img.shape[:3]
    voxel_sizes = ref_img.header.get_zooms()[:3]

    # Write using low-level approach for compatibility
    with open(path, "wb") as f:
        # Write TRK header (1000 bytes)
        hdr = bytearray(1000)

        # id_string (6 bytes)
        hdr[0:6] = b"TRACK\x00"

        # dim (3 x int16, offset 6)
        struct.pack_into("<3h", hdr, 6, *shape)

        # voxel_size (3 x float32, offset 12)
        struct.pack_into("<3f", hdr, 12, *voxel_sizes)

        # origin (3 x float32, offset 24) — set to 0
        struct.pack_into("<3f", hdr, 24, 0.0, 0.0, 0.0)

        # n_scalars (int16, offset 36)
        struct.pack_into("<h", hdr, 36, 0)

        # n_properties (int16, offset 238)
        struct.pack_into("<h", hdr, 238, 0)

        # vox_to_ras (4x4 float32, offset 440)
        vox_to_ras = ref_img.affine.astype(np.float32).flatten()
        struct.pack_into("<16f", hdr, 440, *vox_to_ras)

        # voxel_order (3 bytes, offset 948)
        hdr[948:951] = b"RAS"

        # image_orientation_patient (6 x float32, offset 956)
        # Store the first two columns of the rotation matrix
        R = ref_img.affine[:3, :3]
        norms = np.sqrt(np.sum(R**2, axis=0))
        R_norm = R / norms
        struct.pack_into(
            "<6f",
            hdr,
            956,
            R_norm[0, 0],
            R_norm[1, 0],
            R_norm[2, 0],
            R_norm[0, 1],
            R_norm[1, 1],
            R_norm[2, 1],
        )

        # n_count (int32, offset 988)
        struct.pack_into("<i", hdr, 988, len(streamlines))

        # version (int32, offset 992)
        struct.pack_into("<i", hdr, 992, 2)

        # hdr_size (int32, offset 996)
        struct.pack_into("<i", hdr, 996, 1000)

        f.write(bytes(hdr))

        # Write streamline data
        for sl in streamlines:
            n_pts = len(sl)
            # Write number of points (int32)
            f.write(struct.pack("<i", n_pts))
            # Write coordinates (n_pts x 3 x float32)
            f.write(sl.astype("<f4").tobytes())


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <input.tck> <reference.nii.gz> <output.trk>")
        sys.exit(1)

    input_tck = sys.argv[1]
    ref_path = sys.argv[2]
    output_trk = sys.argv[3]

    print(f"  Reading reference: {ref_path}")
    ref_img = nib.load(ref_path)
    print(f"  Shape: {ref_img.shape[:3]}, voxel sizes: {ref_img.header.get_zooms()[:3]}")

    print(f"  Reading .tck: {input_tck}")
    streamlines = read_tck(input_tck)
    print(f"  Loaded {len(streamlines)} streamlines")

    print("  Converting scanner RAS → TrackVis voxmm ...")
    trk_streamlines = scanner_to_trackvis(streamlines, ref_img)

    print(f"  Writing .trk: {output_trk}")
    write_trk(output_trk, trk_streamlines, ref_img)
    print(f"  Done — {len(trk_streamlines)} streamlines written")


if __name__ == "__main__":
    main()
