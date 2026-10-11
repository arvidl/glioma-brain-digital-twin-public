#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# Create a clean zip of BIDS_preop_postop for uploading as a GitHub Release asset.
#
# Usage:
#   bash scripts/create_data_release.sh            # default version v1.0.0
#   bash scripts/create_data_release.sh v1.1.0     # custom version tag
#
# Output:
#   BIDS_preop_postop_<version>.zip  in the repo root
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIDS_DIR="${REPO_ROOT}/data/BIDS_preop_postop"
VERSION="${1:-v2.0.0}"
OUTFILE="${REPO_ROOT}/BIDS_preop_postop_${VERSION}.zip"

if [[ ! -d "${BIDS_DIR}" ]]; then
    echo "ERROR: BIDS directory not found: ${BIDS_DIR}"
    exit 1
fi

echo "Creating release zip from: ${BIDS_DIR}"
echo "Version:                   ${VERSION}"
echo "Output:                    ${OUTFILE}"
echo ""

cd "${REPO_ROOT}/data"

zip -r "${OUTFILE}" BIDS_preop_postop/ \
    -x "*.DS_Store" \
    -x "*__pycache__*" \
    -x "*.ipynb_checkpoints*"

SIZE_MB=$(du -m "${OUTFILE}" | cut -f1)
echo ""
RELEASE_TAG="glioma-data-${VERSION}"
TARGET_REPO="arvidl/glioma-brain-digital-twin-public"

echo "──────────────────────────────────────────────"
echo "Created: ${OUTFILE}"
echo "Size:    ${SIZE_MB} MB"
echo ""
echo "The data release is hosted on the public repo: ${TARGET_REPO}"
echo ""
echo "Next steps:"
echo "  1. Create a GitHub release on ${TARGET_REPO}:"
echo "     gh release create ${RELEASE_TAG} '${OUTFILE}' \\"
echo "        --repo ${TARGET_REPO} \\"
echo "        --title 'Glioma BIDS data ${VERSION}' \\"
echo "        --notes 'BIDS dataset (sub-PAT16, pre+post-op) for the glioma-brain-digital-twin project.
The full 25-patient BTC cohort is available on OpenNeuro:
  - ds001226 (BTC_preop, v5.0.0)
  - ds002080 (BTC_postop, v4.0.0)'"
echo ""
echo "  2. Verify the download URL:"
echo "     https://github.com/${TARGET_REPO}/releases/download/${RELEASE_TAG}/$(basename ${OUTFILE})"
echo "──────────────────────────────────────────────"
