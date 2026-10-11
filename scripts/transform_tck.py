#!/usr/bin/env python3
"""
transform_tck.py — Apply a MRtrix3 linear transform to a .tck tractogram.

Directly transforms each streamline vertex by the 4x4 affine matrix,
avoiding the warp-field approach (which requires careful handling of
forward vs backward mapping directions).

Usage:
    python transform_tck.py <input.tck> <transform.txt> <output.tck>

The transform file should be in MRtrix3 format (4x4 matrix as produced
by transformconvert ... flirt_import ...).

CAS Brain Mechanics MRI — Finse 2026
"""

import sys
import struct
import numpy as np
import math


def read_mrtrix_transform(path):
    """Read a MRtrix3 linear transform file (4x4 affine matrix)."""
    rows = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            vals = line.split()
            try:
                rows.append([float(v) for v in vals])
            except ValueError:
                continue
    mat = np.array(rows)
    if mat.shape == (3, 4):
        mat = np.vstack([mat, [0, 0, 0, 1]])
    assert mat.shape == (4, 4), f"Expected 4x4 matrix, got {mat.shape}"
    return mat


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <input.tck> <transform.txt> <output.tck>")
        sys.exit(1)

    input_tck = sys.argv[1]
    transform_path = sys.argv[2]
    output_tck = sys.argv[3]

    # Read transform
    # MRtrix3 linear transforms store the BACKWARD mapping (output→input)
    # used for image resampling. To transform streamline vertices FROM
    # source TO target, we need the INVERSE (forward mapping).
    print(f"  Reading transform: {transform_path}")
    affine_backward = read_mrtrix_transform(transform_path)
    print(f"  Backward (image resampling) matrix:\n{affine_backward}")
    affine = np.linalg.inv(affine_backward)
    print(f"  Forward (streamline) matrix (inverted):\n{affine}")
    R = affine[:3, :3].astype(np.float32)
    t = affine[:3, 3].astype(np.float32)

    # Read .tck file
    print(f"  Reading tractogram: {input_tck}")
    with open(input_tck, 'rb') as f:
        # Read header
        header_bytes = bytearray()
        while True:
            line = f.readline()
            header_bytes.extend(line)
            if line.strip() == b'END':
                break

        # Parse data offset
        offset = None
        for line in header_bytes.decode('latin-1').split('\n'):
            line = line.strip()
            if line.startswith('file:'):
                parts = line.split()
                offset = int(parts[-1])
                break

        if offset is None:
            raise ValueError("Could not find 'file:' offset in .tck header")

        # Read all track data
        f.seek(offset)
        data = f.read()

    # Parse as float32 triplets
    floats = np.frombuffer(data, dtype='<f4').copy()
    coords = floats.reshape(-1, 3)

    print(f"  Total coordinate triplets: {len(coords)}")

    # Find vertex vs separator indices
    # NaN = end-of-streamline, Inf = end-of-file, else = vertex
    is_nan = np.isnan(coords[:, 0])
    is_inf = np.isinf(coords[:, 0])
    is_vertex = ~(is_nan | is_inf)

    n_streamlines = int(np.sum(is_nan))
    n_vertices = int(np.sum(is_vertex))
    print(f"  {n_vertices} vertices in {n_streamlines} streamlines")

    # Transform only the vertex coordinates (leave NaN/Inf markers)
    vertex_mask = is_vertex
    vertices = coords[vertex_mask]  # (N, 3)

    # Apply affine: new = vertices @ R.T + t
    transformed = vertices @ R.T + t

    # Write back
    coords[vertex_mask] = transformed

    # Write output .tck
    print(f"  Writing: {output_tck}")
    with open(output_tck, 'wb') as f:
        f.write(bytes(header_bytes))

        # Pad to offset
        current_pos = f.tell()
        if current_pos < offset:
            f.write(b'\x00' * (offset - current_pos))

        # Write transformed data
        f.write(coords.astype('<f4').tobytes())

    print(f"  Done — {n_streamlines} streamlines, {n_vertices} vertices transformed")


if __name__ == '__main__':
    main()
