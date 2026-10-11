#!/usr/bin/env python3
"""
Pack the project-level derivatives required by the Capstone Notebook Series
(NB_C01–C09) into a single zip file suitable for a GitHub Release asset.

The zip mirrors the directory structure under derivatives/ so that extraction
into the repository root restores the correct paths.

Usage:
    python data/pack_capstone_release.py                  # default output
    python data/pack_capstone_release.py -o my_release.zip
    python data/pack_capstone_release.py --dry-run        # list files only
"""

from __future__ import annotations

import argparse
import logging
import sys
import zipfile
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = REPO_ROOT / "capstone_derivatives_v1.0.0.zip"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Pack capstone derivatives into a release zip",
    )
    parser.add_argument(
        "-o", "--output", type=Path, default=DEFAULT_OUTPUT,
        help=f"Output zip path (default: {DEFAULT_OUTPUT.name})",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="List files that would be included without creating the zip",
    )
    args = parser.parse_args()

    # Import the manifest (handle running from any cwd)
    sys.path.insert(0, str(REPO_ROOT / "data"))
    from capstone_manifest import DERIV_FILES

    deriv_root = REPO_ROOT / "derivatives"
    missing: list[str] = []
    found: list[tuple[str, Path]] = []

    for rel in DERIV_FILES:
        full = deriv_root / rel
        if full.exists():
            found.append((rel, full))
        else:
            missing.append(rel)

    if missing:
        logger.warning(f"{len(missing)} manifest files not found locally:")
        for m in missing:
            logger.warning(f"  MISSING: derivatives/{m}")

    if args.dry_run:
        logger.info(f"Files to include: {len(found)}")
        total_mb = sum(p.stat().st_size for _, p in found) / 1e6
        for rel, p in found:
            logger.info(f"  {rel}  ({p.stat().st_size / 1e6:.1f} MB)")
        logger.info(f"Total uncompressed: {total_mb:.1f} MB")
        return 0

    if not found:
        logger.error("No files found to pack. Run your pipeline first.")
        return 1

    logger.info(f"Packing {len(found)} files into {args.output} ...")
    with zipfile.ZipFile(args.output, "w", zipfile.ZIP_DEFLATED) as zf:
        for rel, full_path in found:
            arcname = f"derivatives/{rel}"
            zf.write(full_path, arcname)
            logger.info(f"  + {arcname}")

    size_mb = args.output.stat().st_size / 1e6
    logger.info(f"Done. Archive: {args.output}  ({size_mb:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
