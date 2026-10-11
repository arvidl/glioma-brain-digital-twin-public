"""
Populate the BIDS dataset with imaging files.

Supports multiple modes:
  (default)      Download the release zip from GitHub Releases
  --capstone     Also download project-level derivatives for NB_C01–C09
  --local PATH   Copy binary files from a local folder (e.g. MyStuff/)
  --method aws   Download raw data from OpenNeuro via AWS S3
  --method datalad  Download raw data from OpenNeuro via datalad

Usage examples:
    # Download from GitHub Release (default, recommended):
    python data/download_data.py

    # Download BIDS data + capstone derivatives (for Colab / NB_C series):
    python data/download_data.py --capstone

    # Copy from a local complete BIDS folder:
    python data/download_data.py --local MyStuff/BIDS_preop_postop

    # Download from OpenNeuro (advanced):
    python data/download_data.py --method aws

    # Only a single subject:
    python data/download_data.py --subject PAT16
"""

from __future__ import annotations

import argparse
import io
import logging
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

# ── Configuration ────────────────────────────────────────────────────────────

GITHUB_REPO = "arvidl/glioma-brain-digital-twin-public"
RELEASE_TAG = "glioma-data-v2.0.0"
RELEASE_ZIP = "BIDS_preop_postop_v2.0.0.zip"
RELEASE_URL = (
    f"https://github.com/{GITHUB_REPO}/releases/download/{RELEASE_TAG}/{RELEASE_ZIP}"
)

# OpenNeuro dataset identifiers (Brain Tumor Connectomics, Aerts & Marinazzo)
DATASETS = {
    "ds001226": "BTC_preop – Brain Tumor Connectomics pre-operative (v5.0.0)",
    "ds002080": "BTC_postop – Brain Tumor Connectomics post-operative (v4.0.0)",
}

SUBJECTS = ["PAT16"]

BINARY_SUFFIXES = {".nii", ".nii.gz", ".mgh", ".mgz", ".trk", ".tck", ".mif", ".mat"}

# Capstone derivatives release (project-level derivatives for NB_C01–C09)
CAPSTONE_REPO = "arvidl/glioma-brain-digital-twin-public"
CAPSTONE_TAG = "capstone-data-v1.0.0"
CAPSTONE_ZIP = "capstone_derivatives_v1.0.0.zip"
CAPSTONE_URL = (
    f"https://github.com/{CAPSTONE_REPO}/releases/download/"
    f"{CAPSTONE_TAG}/{CAPSTONE_ZIP}"
)


def _is_binary_data(path: Path) -> bool:
    """Return True if the file is a large binary imaging file."""
    name = path.name
    return any(name.endswith(s) for s in BINARY_SUFFIXES)


# ── GitHub Release download ─────────────────────────────────────────────────

def download_from_github(dest: Path, url: str = RELEASE_URL) -> bool:
    """Download and extract the BIDS zip from a GitHub Release."""
    dest.mkdir(parents=True, exist_ok=True)

    logger.info(f"Downloading from: {url}")
    logger.info("This may take a few minutes (~200 MB)...")

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "finse26-download/1.0"})
        with urllib.request.urlopen(req) as resp:
            total = int(resp.headers.get("Content-Length", 0))
            data = io.BytesIO()
            downloaded = 0
            block = 1024 * 256
            while True:
                chunk = resp.read(block)
                if not chunk:
                    break
                data.write(chunk)
                downloaded += len(chunk)
                if total > 0:
                    pct = downloaded * 100 // total
                    mb = downloaded / 1e6
                    print(f"\r  {mb:.0f} / {total/1e6:.0f} MB ({pct}%)", end="", flush=True)
            print()
    except Exception as e:
        logger.error(f"Download failed: {e}")
        logger.info("You can manually download the zip from:")
        logger.info(f"  {url}")
        logger.info("Then extract it into data/BIDS_preop_postop/")
        return False

    logger.info("Extracting zip...")
    data.seek(0)
    with zipfile.ZipFile(data) as zf:
        # The zip contains a top-level BIDS_preop_postop/ folder.
        # Strip that prefix so contents go directly into dest.
        prefix = "BIDS_preop_postop/"
        for member in zf.infolist():
            if member.filename.startswith(prefix):
                rel = member.filename[len(prefix):]
                if not rel:
                    continue
                target = dest / rel
                # Metadata and sidecars tracked in git are newer than the zip copies.
                if target.exists() and not rel.endswith((".nii", ".nii.gz")):
                    continue
                if member.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with zf.open(member) as src, open(target, "wb") as dst:
                        shutil.copyfileobj(src, dst)

    logger.info("Extraction complete.")
    return True


# ── Local copy mode ──────────────────────────────────────────────────────────

def copy_from_local(source: Path, dest: Path, subjects: list[str]) -> bool:
    """Copy binary imaging files from a local BIDS folder into dest.

    Only copies files with imaging suffixes (.nii, .nii.gz, .mat, etc.)
    that do not already exist at the destination.
    """
    if not source.is_dir():
        logger.error(f"Source directory does not exist: {source}")
        return False

    copied = 0
    skipped = 0

    for src_file in sorted(source.rglob("*")):
        if not src_file.is_file():
            continue
        if not _is_binary_data(src_file):
            continue

        rel = src_file.relative_to(source)
        rel_str = str(rel)
        if subjects != SUBJECTS:
            if not any(f"sub-{s}" in rel_str for s in subjects):
                continue

        dst_file = dest / rel
        if dst_file.exists() and dst_file.stat().st_size == src_file.stat().st_size:
            skipped += 1
            continue

        dst_file.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src_file, dst_file)
        logger.info(f"  copied: {rel}")
        copied += 1

    logger.info(f"Local copy complete: {copied} files copied, {skipped} already present.")
    return True


# ── OpenNeuro download modes ────────────────────────────────────────────────

def check_aws_cli() -> bool:
    try:
        subprocess.run(["aws", "--version"], check=True, capture_output=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        logger.warning("AWS CLI not found. Install with: pip install awscli")
        return False


def check_datalad() -> bool:
    try:
        subprocess.run(["datalad", "--version"], check=True, capture_output=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        logger.warning("datalad not found. Install with: pip install datalad")
        return False


def download_with_aws(dest: Path, subjects: list[str]) -> bool:
    """Download BIDS data using AWS S3 sync."""
    if not check_aws_cli():
        return False

    dest.mkdir(parents=True, exist_ok=True)
    s3_bucket = "openneuro.org"

    for dataset_id in DATASETS:
        logger.info(f"Downloading {dataset_id} ({DATASETS[dataset_id]})...")
        for subject in subjects:
            s3_path = f"s3://{s3_bucket}/{dataset_id}/sub-{subject}"
            dest_path = dest / f"sub-{subject}"
            cmd = [
                "aws", "s3", "sync",
                s3_path, str(dest_path),
                "--no-sign-request", "--region", "us-west-2",
            ]
            logger.info(f"Running: {' '.join(cmd)}")
            try:
                subprocess.run(cmd, check=True)
            except subprocess.CalledProcessError as e:
                logger.error(f"Failed to download sub-{subject}: {e}")
                return False
    return True


def download_with_datalad(dest: Path, subjects: list[str]) -> bool:
    """Download BIDS data using datalad."""
    if not check_datalad():
        return False

    dest.mkdir(parents=True, exist_ok=True)

    for dataset_id in DATASETS:
        logger.info(f"Cloning {dataset_id} with datalad...")
        dataset_path = dest / dataset_id
        try:
            subprocess.run(
                ["datalad", "clone",
                 f"https://github.com/OpenNeuroDatasets/{dataset_id}",
                 str(dataset_path)],
                check=True,
            )
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to clone {dataset_id}: {e}")
            return False

        for subject in subjects:
            logger.info(f"Getting sub-{subject}...")
            try:
                subprocess.run(
                    ["datalad", "get", str(dataset_path / f"sub-{subject}"), "-r"],
                    check=True, cwd=str(dataset_path),
                )
            except subprocess.CalledProcessError as e:
                logger.error(f"Failed to get sub-{subject}: {e}")
                return False
    return True


# ── Capstone derivatives download ────────────────────────────────────────────

def download_capstone_derivatives(repo_root: Path, url: str = CAPSTONE_URL) -> bool:
    """Download and extract capstone project-level derivatives."""
    deriv_dir = repo_root / "derivatives"
    marker = deriv_dir / ".capstone_downloaded"
    if marker.exists():
        logger.info("Capstone derivatives already present (skipping).")
        return True

    logger.info(f"Downloading capstone derivatives from: {url}")
    logger.info("This may take a few minutes ...")

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "finse26-download/1.0"})
        with urllib.request.urlopen(req) as resp:
            total = int(resp.headers.get("Content-Length", 0))
            data = io.BytesIO()
            downloaded = 0
            block = 1024 * 256
            while True:
                chunk = resp.read(block)
                if not chunk:
                    break
                data.write(chunk)
                downloaded += len(chunk)
                if total > 0:
                    pct = downloaded * 100 // total
                    mb = downloaded / 1e6
                    print(
                        f"\r  {mb:.0f} / {total/1e6:.0f} MB ({pct}%)",
                        end="", flush=True,
                    )
            print()
    except Exception as e:
        logger.error(f"Capstone download failed: {e}")
        logger.info("You can manually download the zip from:")
        logger.info(f"  {url}")
        logger.info("Then extract it into the repository root.")
        return False

    logger.info("Extracting capstone derivatives ...")
    data.seek(0)
    with zipfile.ZipFile(data) as zf:
        for member in zf.infolist():
            if member.is_dir():
                (repo_root / member.filename).mkdir(parents=True, exist_ok=True)
            else:
                target = repo_root / member.filename
                target.parent.mkdir(parents=True, exist_ok=True)
                with zf.open(member) as src, open(target, "wb") as dst:
                    shutil.copyfileobj(src, dst)

    marker.parent.mkdir(parents=True, exist_ok=True)
    marker.write_text("capstone-data-v1.0.0\n")
    logger.info("Capstone derivatives extraction complete.")
    return True


# ── Compress uncompressed NIfTI files ────────────────────────────────────────

def compress_nifti(dest: Path) -> int:
    """Gzip any .nii files that don't already have a .nii.gz counterpart."""
    import gzip

    compressed = 0
    for nii_file in sorted(dest.rglob("*.nii")):
        if nii_file.name.endswith(".nii.gz"):
            continue
        gz_file = nii_file.with_suffix(".nii.gz")
        if gz_file.exists():
            logger.debug(f"  skip (gz exists): {nii_file.relative_to(dest)}")
            continue
        size_before = nii_file.stat().st_size
        with open(nii_file, "rb") as f_in, gzip.open(gz_file, "wb") as f_out:
            shutil.copyfileobj(f_in, f_out)
        size_after = gz_file.stat().st_size
        nii_file.unlink()
        ratio = size_before / size_after if size_after else 0
        logger.info(
            f"  compressed: {nii_file.relative_to(dest)}"
            f"  ({size_before/1024:.0f} KB → {size_after/1024:.0f} KB, {ratio:.0f}x)"
        )
        compressed += 1
    return compressed


# ── Verify ───────────────────────────────────────────────────────────────────

def verify_data(dest: Path, subjects: list[str]) -> None:
    """Print a summary of what is present after populating."""
    logger.info("─── Data verification ───")
    for subject in subjects:
        for session in ("ses-preop", "ses-postop"):
            base = dest / f"sub-{subject}" / session
            for modality, pattern in [
                ("T1w", "anat/*T1w.nii.gz"),
                ("DWI-AP", "dwi/*acq-AP_dwi.nii.gz"),
                ("DWI-PA", "dwi/*acq-PA_dwi.nii.gz"),
                ("BOLD", "func/*bold.nii.gz"),
            ]:
                files = list(base.glob(pattern))
                status = "OK" if files else "MISSING"
                logger.info(f"  sub-{subject}/{session}/{modality}: {status}")

    deriv = dest / "derivatives"
    for d in ("tumor_masks", "rsHRF", "TVB"):
        n = len(list((deriv / d).rglob("*"))) if (deriv / d).exists() else 0
        logger.info(f"  derivatives/{d}: {n} files")


# ── Main ─────────────────────────────────────────────────────────────────────

def _default_dest() -> Path:
    here = Path(__file__).resolve().parent
    return here / "BIDS_preop_postop"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Populate BIDS dataset for the Finse 2026 glioma digital twin project",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--dest", type=Path, default=_default_dest(),
        help="Destination BIDS directory (default: data/BIDS_preop_postop)",
    )
    parser.add_argument(
        "--subject", type=str, nargs="*", default=SUBJECTS,
        help=f"Subject IDs to process (default: {' '.join(SUBJECTS)})",
    )
    parser.add_argument(
        "--local", type=Path, default=None, metavar="PATH",
        help="Copy binary files from a local BIDS folder instead of downloading",
    )
    parser.add_argument(
        "--method", choices=["github", "aws", "datalad", "auto"], default="github",
        help="Download method when --local is not used (default: github)",
    )
    parser.add_argument(
        "--capstone", action="store_true",
        help="Also download project-level derivatives for capstone notebooks (NB_C01–C09)",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Show what would be done without copying/downloading",
    )

    args = parser.parse_args()

    logger.info(f"Destination: {args.dest}")
    logger.info(f"Subjects:    {args.subject}")

    # ── Local copy mode ──
    if args.local:
        source = args.local.resolve()
        logger.info(f"Local source: {source}")
        if args.dry_run:
            n = sum(1 for f in source.rglob("*") if f.is_file() and _is_binary_data(f))
            logger.info(f"[dry-run] Would copy up to {n} binary files")
            return 0
        success = copy_from_local(source, args.dest, args.subject)

    # ── GitHub Release (default) ──
    elif args.method == "github":
        if args.dry_run:
            logger.info(f"[dry-run] Would download from {RELEASE_URL}")
            return 0
        success = download_from_github(args.dest)

    # ── OpenNeuro methods ──
    else:
        if args.dry_run:
            logger.info(f"[dry-run] Would download from OpenNeuro via {args.method}")
            return 0
        success = False
        if args.method in ("aws", "auto"):
            success = download_with_aws(args.dest, args.subject)
        if not success and args.method in ("datalad", "auto"):
            logger.info("Attempting datalad fallback...")
            success = download_with_datalad(args.dest, args.subject)

    if success:
        n = compress_nifti(args.dest)
        if n:
            logger.info(f"Compressed {n} uncompressed NIfTI file(s) to .nii.gz")
        verify_data(args.dest, args.subject)

        if args.capstone:
            repo_root = args.dest.parent.parent  # data/BIDS_preop_postop -> repo root
            cap_ok = download_capstone_derivatives(repo_root)
            if not cap_ok:
                logger.error("Capstone derivatives download failed.")
                return 1

        logger.info("Done.")
        return 0
    else:
        logger.error("Data population failed.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
