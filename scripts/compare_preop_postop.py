#!/usr/bin/env python3
"""
compare_preop_postop.py -- Pre-op vs post-op longitudinal analysis.

Compares registered T1w-space derivatives between pre-operative and
post-operative sessions for a given subject. Produces:
  - ROI volume changes from aparc+aseg
  - Voxel-wise and ROI-wise delta-FA, delta-MD maps
  - Deformation field analysis (displacement, Jacobian) if Step 5b ran
  - Connectivity matrix differences (if available)
  - Summary report with brain mechanics implications

When longitudinal registration outputs (Step 5b) are available, this
script uses the warped pre-op images (in post-op space) for proper
voxel-wise comparison.  Without Step 5b, it falls back to direct
comparison in each session's native T1w space (approximate).

Usage:
    python scripts/compare_preop_postop.py --subject PAT16 \
        [--project-dir /path/to/project]

Glioma Brain Digital Twin
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np

try:
    import nibabel as nib
except ImportError:
    print("ERROR: nibabel required. Install with: pip install nibabel")
    sys.exit(1)

try:
    from nilearn.image import resample_to_img
except ImportError:
    resample_to_img = None


def _match_grid(
    data: np.ndarray,
    data_img: nib.Nifti1Image,
    ref_img: nib.Nifti1Image,
    interpolation: str = "nearest",
) -> np.ndarray:
    """Resample *data* (with header from *data_img*) onto *ref_img* grid."""
    if data.shape[:3] == ref_img.shape[:3]:
        return data
    if resample_to_img is None:
        raise RuntimeError("nilearn is required for grid resampling")
    src = nib.Nifti1Image(data, data_img.affine, data_img.header)
    resampled = resample_to_img(src, ref_img, interpolation=interpolation)
    return np.asarray(resampled.dataobj)


# FreeSurfer Desikan-Killiany label names for key ROIs
DK_LABELS = {
    2: "Left-Cerebral-WM",
    3: "Left-Cerebral-Cortex",
    4: "Left-Lateral-Ventricle",
    5: "Left-Inf-Lat-Vent",
    7: "Left-Cerebellum-WM",
    8: "Left-Cerebellum-Cortex",
    10: "Left-Thalamus",
    11: "Left-Caudate",
    12: "Left-Putamen",
    13: "Left-Pallidum",
    17: "Left-Hippocampus",
    18: "Left-Amygdala",
    26: "Left-Accumbens-area",
    41: "Right-Cerebral-WM",
    42: "Right-Cerebral-Cortex",
    43: "Right-Lateral-Ventricle",
    44: "Right-Inf-Lat-Vent",
    46: "Right-Cerebellum-WM",
    47: "Right-Cerebellum-Cortex",
    49: "Right-Thalamus",
    50: "Right-Caudate",
    51: "Right-Putamen",
    52: "Right-Pallidum",
    53: "Right-Hippocampus",
    54: "Right-Amygdala",
    58: "Right-Accumbens-area",
}


def load_nifti(path: Path) -> tuple[np.ndarray, nib.Nifti1Image] | None:
    """Load a NIfTI file, return (data, img) or None if missing."""
    if not path.exists():
        print(f"  WARNING: not found: {path}")
        return None
    img = nib.load(str(path))
    return np.asarray(img.dataobj), img


def compute_roi_volumes(aparc_data: np.ndarray, voxel_vol_mm3: float) -> dict[int, float]:
    """Compute volume in mm^3 for each label in the aparc+aseg volume."""
    labels, counts = np.unique(aparc_data.astype(int), return_counts=True)
    return {int(lab): int(cnt) * voxel_vol_mm3 for lab, cnt in zip(labels, counts)}


def compute_dti_roi_stats(
    dti_data: np.ndarray, aparc_data: np.ndarray, labels: list[int]
) -> dict[int, dict[str, float]]:
    """Compute mean and std of a DTI map within each ROI."""
    stats = {}
    for lab in labels:
        mask = aparc_data == lab
        if mask.sum() == 0:
            continue
        vals = dti_data[mask]
        vals = vals[np.isfinite(vals)]
        if len(vals) == 0:
            continue
        stats[lab] = {
            "mean": float(np.mean(vals)),
            "std": float(np.std(vals)),
            "n_voxels": int(mask.sum()),
        }
    return stats


def main():
    parser = argparse.ArgumentParser(description="Compare pre-op vs post-op derivatives")
    parser.add_argument("--subject", required=True, help="Subject ID (e.g. PAT16)")
    parser.add_argument(
        "--project-dir",
        default=None,
        help="Project root (default: auto-detect from script location)",
    )
    args = parser.parse_args()

    if args.project_dir:
        project = Path(args.project_dir)
    else:
        project = Path(__file__).resolve().parent.parent

    sub = args.subject
    reg_dir = project / "derivatives" / "registered_t1w" / f"sub-{sub}"
    preop_dir = reg_dir / "ses-preop"
    postop_dir = reg_dir / "ses-postop"
    long_dir = reg_dir / "longitudinal"
    out_dir = reg_dir / "preop_vs_postop"
    out_dir.mkdir(parents=True, exist_ok=True)

    # Detect whether longitudinal registration (Step 5b) outputs are available
    has_longitudinal = (long_dir / "displacement_magnitude.nii.gz").exists()

    print("=" * 60)
    print(f" Pre-op vs Post-op Comparison: sub-{sub}")
    print("=" * 60)
    print(f" Pre-op dir    : {preop_dir}")
    print(f" Post-op dir   : {postop_dir}")
    print(
        f" Longitudinal  : {'YES (using warped pre-op data)' if has_longitudinal else 'NO (direct comparison)'}"
    )
    print(f" Output dir    : {out_dir}")
    print("=" * 60)

    results: dict = {"subject": sub, "has_longitudinal": has_longitudinal, "analyses": {}}

    # ================================================================
    # 1. Structural: ROI volume changes
    # ================================================================
    print("\n--- 1. Structural ROI volume changes ---")

    aparc_pre = load_nifti(preop_dir / "aparc+aseg_space-T1w.nii.gz")
    aparc_post = load_nifti(postop_dir / "aparc+aseg_space-T1w.nii.gz")

    if aparc_pre is not None and aparc_post is not None:
        vox_pre = np.prod(aparc_pre[1].header.get_zooms()[:3])
        vox_post = np.prod(aparc_post[1].header.get_zooms()[:3])

        vol_pre = compute_roi_volumes(aparc_pre[0], vox_pre)
        vol_post = compute_roi_volumes(aparc_post[0], vox_post)

        volume_changes = {}
        all_labels = sorted(set(vol_pre.keys()) | set(vol_post.keys()))
        for lab in all_labels:
            if lab == 0:
                continue
            v_pre = vol_pre.get(lab, 0.0)
            v_post = vol_post.get(lab, 0.0)
            delta = v_post - v_pre
            pct = (delta / v_pre * 100) if v_pre > 0 else float("nan")
            name = DK_LABELS.get(lab, f"Label-{lab}")
            volume_changes[lab] = {
                "name": name,
                "preop_mm3": v_pre,
                "postop_mm3": v_post,
                "delta_mm3": delta,
                "delta_pct": round(pct, 2),
            }

        results["analyses"]["volume_changes"] = volume_changes

        # Print top changes
        sorted_changes = sorted(
            volume_changes.values(),
            key=lambda x: abs(x["delta_mm3"]),
            reverse=True,
        )
        print(f"  {'ROI':<30s}  {'Pre-op':>10s}  {'Post-op':>10s}  {'Delta':>10s}  {'%':>7s}")
        print("  " + "-" * 72)
        for entry in sorted_changes[:15]:
            print(
                f"  {entry['name']:<30s}  {entry['preop_mm3']:>10.1f}  "
                f"{entry['postop_mm3']:>10.1f}  {entry['delta_mm3']:>10.1f}  "
                f"{entry['delta_pct']:>6.1f}%"
            )
    else:
        print("  Skipped (aparc+aseg not available for both sessions)")

    # ================================================================
    # 2. DTI: delta-FA and delta-MD maps
    # ================================================================
    print("\n--- 2. DTI scalar map differences ---")
    if has_longitudinal:
        print("  (using warped pre-op data from longitudinal registration)")

    for metric in ("fa", "md", "ad", "rd"):
        # Prefer warped pre-op (in post-op space) for proper voxel correspondence
        if has_longitudinal:
            pre_result = load_nifti(long_dir / f"{metric}_preop_in_postop.nii.gz")
        else:
            pre_result = load_nifti(preop_dir / f"{metric}_space-T1w.nii.gz")
        post_result = load_nifti(postop_dir / f"{metric}_space-T1w.nii.gz")

        if pre_result is None or post_result is None:
            print(f"  {metric.upper()}: skipped (not available for both sessions)")
            continue

        data_pre, img_pre = pre_result
        data_post, _ = post_result

        if data_pre.shape != data_post.shape:
            print(
                f"  {metric.upper()}: WARNING -- shape mismatch "
                f"({data_pre.shape} vs {data_post.shape}), skipping"
            )
            continue

        delta = data_post.astype(np.float32) - data_pre.astype(np.float32)

        # Save delta map
        delta_img = nib.Nifti1Image(delta, img_pre.affine, img_pre.header)
        delta_path = out_dir / f"delta_{metric}_space-T1w.nii.gz"
        nib.save(delta_img, str(delta_path))
        print(f"  {metric.upper()}: delta map saved to {delta_path.name}")

        # Brain-masked stats
        brain_mask = np.isfinite(delta) & (np.abs(data_pre) + np.abs(data_post) > 0)
        if brain_mask.sum() > 0:
            masked_delta = delta[brain_mask]
            results["analyses"][f"delta_{metric}"] = {
                "mean": float(np.mean(masked_delta)),
                "std": float(np.std(masked_delta)),
                "min": float(np.min(masked_delta)),
                "max": float(np.max(masked_delta)),
                "n_voxels": int(brain_mask.sum()),
            }
            print(
                f"         mean={np.mean(masked_delta):.4f}, "
                f"std={np.std(masked_delta):.4f}, "
                f"range=[{np.min(masked_delta):.4f}, {np.max(masked_delta):.4f}]"
            )

        # ROI-level stats if aparc+aseg available
        if aparc_pre is not None:
            aparc_for_dti = _match_grid(
                aparc_pre[0], aparc_pre[1], img_pre, interpolation="nearest"
            )
            roi_labels = [lab for lab in DK_LABELS if lab in np.unique(aparc_for_dti.astype(int))]
            pre_roi = compute_dti_roi_stats(data_pre, aparc_for_dti, roi_labels)
            post_roi = compute_dti_roi_stats(data_post, aparc_for_dti, roi_labels)
            roi_delta = {}
            for lab in roi_labels:
                if lab in pre_roi and lab in post_roi:
                    roi_delta[lab] = {
                        "name": DK_LABELS[lab],
                        "preop_mean": pre_roi[lab]["mean"],
                        "postop_mean": post_roi[lab]["mean"],
                        "delta_mean": post_roi[lab]["mean"] - pre_roi[lab]["mean"],
                    }
            results["analyses"][f"delta_{metric}_roi"] = roi_delta

    # ================================================================
    # 3. Deformation field analysis (from Step 5b)
    # ================================================================
    print("\n--- 3. Deformation field analysis ---")

    disp_result = load_nifti(long_dir / "displacement_magnitude.nii.gz")
    jac_result = load_nifti(long_dir / "jacobian_preop_to_postop.nii.gz")
    cavity_result = load_nifti(long_dir / "cavity_mask_postop.nii.gz")

    if disp_result is not None:
        disp_data, disp_img = disp_result
        brain_mask = disp_data > 0.1
        if brain_mask.sum() > 0:
            vals = disp_data[brain_mask]
            results["analyses"]["displacement"] = {
                "mean_mm": round(float(np.mean(vals)), 3),
                "median_mm": round(float(np.median(vals)), 3),
                "max_mm": round(float(np.max(vals)), 3),
                "p95_mm": round(float(np.percentile(vals, 95)), 3),
                "n_voxels_gt_5mm": int(np.sum(vals > 5.0)),
                "n_voxels_gt_10mm": int(np.sum(vals > 10.0)),
            }
            d = results["analyses"]["displacement"]
            print(
                f"  Displacement: mean={d['mean_mm']:.2f} mm, "
                f"max={d['max_mm']:.2f} mm, "
                f"95th pctl={d['p95_mm']:.2f} mm"
            )
            print(f"  Voxels > 5 mm: {d['n_voxels_gt_5mm']}, " f"> 10 mm: {d['n_voxels_gt_10mm']}")
    else:
        print("  Displacement map not available (run register_longitudinal.sh)")

    if jac_result is not None:
        jac_data, jac_img = jac_result
        jac_valid = jac_data[np.isfinite(jac_data) & (jac_data > 0)]
        if len(jac_valid) > 0:
            results["analyses"]["jacobian"] = {
                "mean": round(float(np.mean(jac_valid)), 4),
                "min": round(float(np.min(jac_valid)), 4),
                "max": round(float(np.max(jac_valid)), 4),
                "pct_expanding": round(100 * float(np.sum(jac_valid > 1.05)) / len(jac_valid), 2),
                "pct_contracting": round(100 * float(np.sum(jac_valid < 0.95)) / len(jac_valid), 2),
            }
            j = results["analyses"]["jacobian"]
            print(f"  Jacobian: mean={j['mean']:.4f}, " f"range=[{j['min']:.4f}, {j['max']:.4f}]")
            print(
                f"  Expanding (J>1.05): {j['pct_expanding']:.1f}%, "
                f"Contracting (J<0.95): {j['pct_contracting']:.1f}%"
            )
    else:
        print("  Jacobian map not available")

    if cavity_result is not None:
        cavity_data, cavity_img = cavity_result
        n_cavity = int(cavity_data.sum())
        vox_vol = float(np.abs(np.linalg.det(cavity_img.affine[:3, :3])))
        vol_cm3 = n_cavity * vox_vol / 1000.0
        results["analyses"]["cavity"] = {
            "n_voxels": n_cavity,
            "volume_cm3": round(vol_cm3, 2),
        }
        print(f"  Resection cavity: {n_cavity} voxels, {vol_cm3:.1f} cm3")
    else:
        print("  Cavity mask not available")

    # Load ROI-level displacement stats if available
    roi_stats_path = long_dir / "displacement_roi_stats.json"
    if roi_stats_path.exists():
        with open(roi_stats_path) as f:
            results["analyses"]["displacement_roi"] = json.load(f)

    # ================================================================
    # 4. Connectivity changes (if SC/FC matrices available)
    # ================================================================
    print("\n--- 3. Connectivity changes ---")

    tvb_dir = project / "data" / "BIDS_preop_postop" / "derivatives" / "TVB"
    fc_pre_path = tvb_dir / f"sub-{sub}" / "ses-preop" / "FC.mat"
    fc_post_path = tvb_dir / f"sub-{sub}" / "ses-postop" / "FC.mat"

    if fc_pre_path.exists() and fc_post_path.exists():
        try:
            from scipy.io import loadmat

            fc_pre = loadmat(str(fc_pre_path))
            fc_post = loadmat(str(fc_post_path))
            fc_key = [k for k in fc_pre.keys() if not k.startswith("_")][0]
            fc_pre_mat = fc_pre[fc_key]
            fc_post_mat = fc_post[fc_key]
            delta_fc = fc_post_mat - fc_pre_mat
            results["analyses"]["delta_fc"] = {
                "mean": float(np.mean(delta_fc)),
                "std": float(np.std(delta_fc)),
                "n_connections_weakened": int(np.sum(delta_fc < -0.1)),
                "n_connections_strengthened": int(np.sum(delta_fc > 0.1)),
                "shape": list(delta_fc.shape),
            }
            print(
                f"  FC delta: mean={np.mean(delta_fc):.4f}, "
                f"weakened={np.sum(delta_fc < -0.1)}, "
                f"strengthened={np.sum(delta_fc > 0.1)}"
            )
        except Exception as e:
            print(f"  FC comparison failed: {e}")
    else:
        print("  Skipped (FC matrices not available for both sessions)")

    # ================================================================
    # 5. Brain mechanics implications
    # ================================================================
    print("\n--- 5. Brain mechanics implications ---")

    mechanics_notes = []

    if "delta_fa" in results["analyses"]:
        fa_delta = results["analyses"]["delta_fa"]
        if abs(fa_delta["mean"]) > 0.01:
            direction = "decrease" if fa_delta["mean"] < 0 else "increase"
            mechanics_notes.append(
                f"Mean FA {direction} of {abs(fa_delta['mean']):.4f} suggests "
                f"altered fiber architecture, affecting anisotropic stiffness."
            )

    if "delta_md" in results["analyses"]:
        md_delta = results["analyses"]["delta_md"]
        if abs(md_delta["mean"]) > 1e-5:
            direction = "increase" if md_delta["mean"] > 0 else "decrease"
            mechanics_notes.append(
                f"Mean MD {direction} of {abs(md_delta['mean']):.6f} mm^2/s "
                f"indicates tissue density/hydration changes, "
                f"affecting isotropic compliance."
            )

    if "volume_changes" in results["analyses"]:
        vent_labels = [4, 43]  # lateral ventricles
        for lab in vent_labels:
            if lab in results["analyses"]["volume_changes"]:
                vc = results["analyses"]["volume_changes"][lab]
                if abs(vc["delta_pct"]) > 5:
                    mechanics_notes.append(
                        f"{vc['name']} volume changed by {vc['delta_pct']:.1f}%, "
                        f"affecting CSF boundary conditions in FE model."
                    )

    if "displacement" in results["analyses"]:
        disp = results["analyses"]["displacement"]
        if disp["p95_mm"] > 3.0:
            mechanics_notes.append(
                f"95th percentile displacement of {disp['p95_mm']:.1f} mm "
                f"indicates significant brain shift -- the FE reference "
                f"configuration must account for this deformation."
            )
        if disp["n_voxels_gt_10mm"] > 100:
            mechanics_notes.append(
                f"{disp['n_voxels_gt_10mm']} voxels displaced > 10 mm -- "
                f"large deformation formulation required in these regions."
            )

    if "jacobian" in results["analyses"]:
        jac = results["analyses"]["jacobian"]
        if jac["pct_expanding"] > 5:
            mechanics_notes.append(
                f"{jac['pct_expanding']:.1f}% of voxels show expansion (J > 1.05), "
                f"consistent with CSF space enlargement post-surgery."
            )

    if "cavity" in results["analyses"]:
        cavity = results["analyses"]["cavity"]
        mechanics_notes.append(
            f"Resection cavity volume: {cavity['volume_cm3']:.1f} cm3 -- "
            f"creates a non-simply-connected FE domain requiring "
            f"zero-stiffness / CSF boundary condition treatment."
        )

    if not mechanics_notes:
        mechanics_notes.append("No significant changes detected (or data unavailable).")

    results["analyses"]["mechanics_notes"] = mechanics_notes
    for note in mechanics_notes:
        print(f"  - {note}")

    # ================================================================
    # Save results
    # ================================================================
    report_path = out_dir / "comparison_report.json"
    with open(report_path, "w") as f:
        json.dump(results, f, indent=2, default=str)
    print(f"\nReport saved to: {report_path}")

    print("\n" + "=" * 60)
    print(f" Comparison complete for sub-{sub}")
    print("=" * 60)


if __name__ == "__main__":
    main()
