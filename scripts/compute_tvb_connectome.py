#!/usr/bin/env python3
"""
compute_tvb_connectome.py
─────────────────────────
Build a TVB-ready structural connectivity (SC) matrix from a tractogram
using a Desikan-Killiany parcellation.

Uses MRtrix3 (tck2connectome) under the hood.

Usage
-----
python scripts/compute_tvb_connectome.py \
    --tck     mrtrix_outputs/sub-PAT16_ses-preop/tracks_10000000.tck \
    --weights mrtrix_outputs/sub-PAT16_ses-preop/sift2_weights.txt \
    --parc    /path/to/dk_atlas_in_dwi_space.nii.gz \
    --out     outputs/sub-PAT16_ses-preop_SC.csv \
    [--n-nodes 84]
"""

import argparse
import subprocess
import sys
from pathlib import Path

import numpy as np


def run(cmd: str, dry_run: bool = False):
    print(f"[CMD] {cmd}")
    if not dry_run:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"[ERROR] {result.stderr}")
            sys.exit(1)
        return result.stdout
    return ""


def compute_connectome(
    tck_path: Path,
    parc_path: Path,
    out_path: Path,
    weights_path: Path | None = None,
    symmetric: bool = True,
    dry_run: bool = False,
) -> np.ndarray | None:
    """Run tck2connectome and return the SC matrix."""
    out_path.parent.mkdir(parents=True, exist_ok=True)

    tck2con_cmd = f"tck2connectome {tck_path} {parc_path} {out_path} " f"-symmetric -zero_diagonal "
    if weights_path:
        tck2con_cmd += f"-tck_weights_in {weights_path} "
    tck2con_cmd += "-force"

    run(tck2con_cmd, dry_run)

    if not dry_run and out_path.exists():
        SC = np.loadtxt(str(out_path), delimiter=",")
        print(f"[INFO] SC matrix shape: {SC.shape}, max={SC.max():.3f}")
        return SC
    return None


def normalise_sc(SC: np.ndarray) -> np.ndarray:
    """Log-normalise SC for TVB (values in [0, 1])."""
    SC = SC.copy()
    SC[SC > 0] = np.log1p(SC[SC > 0])
    if SC.max() > 0:
        SC /= SC.max()
    return SC


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--tck", required=True, type=Path)
    parser.add_argument("--parc", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--weights", type=Path, default=None)
    parser.add_argument("--n-nodes", type=int, default=84)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    # Check MRtrix3
    result = subprocess.run("tck2connectome --version", shell=True, capture_output=True, text=True)
    if result.returncode != 0:
        print("ERROR: tck2connectome not found – install MRtrix3.")
        sys.exit(1)

    SC = compute_connectome(
        args.tck,
        args.parc,
        args.out,
        weights_path=args.weights,
        dry_run=args.dry_run,
    )

    if SC is not None:
        SC_norm = normalise_sc(SC)
        norm_path = args.out.with_name(args.out.stem + "_normalised.csv")
        np.savetxt(str(norm_path), SC_norm, delimiter=",", fmt="%.6f")
        print(f"[DONE] Normalised SC saved: {norm_path}")


if __name__ == "__main__":
    main()
