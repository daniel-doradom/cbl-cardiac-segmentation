from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict
from pathlib import Path

from vtseg.dicom.convert import prepare_series
from vtseg.dicom.series import inventory_report, scan_headers
from vtseg.errors import VTSegError
from vtseg.provenance import write_json
from vtseg.qc.masks import run_case_qc
from vtseg.review import collect_review
from vtseg.segmentation.bivme import BREATHHOLD_SHIFT_MODES, BivMeMRIBackend
from vtseg.segmentation.bivme_lge import align_bivme_to_lge
from vtseg.segmentation.matlab_export import export_matlab_case, preview_matlab_slices
from vtseg.segmentation.matlab_import import import_matlab_case
from vtseg.segmentation.ct_mpr import map_native_ct_masks_to_mpr, promote_ct_candidate
from vtseg.segmentation.totalsegmentator import TotalSegmentatorCTBackend


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _print_inventory(report: dict) -> None:
    print(
        f"Readable instances: {report['readable_instances']} | "
        f"Studies: {len(report['studies'])} | Skipped files: {len(report['skipped_files'])}"
    )
    for study_index, study in enumerate(report["studies"], start=1):
        print(f"\nStudy {study_index}: {study['study_uid']}")
        for series in study["series"]:
            frame_text = (
                str(series["inferred_temporal_frames"])
                if series["temporal_inference_defensible"]
                else "ambiguous"
            )
            print(
                f"  Series {series['series_uid']} | #{series['series_number']} | "
                f"{series['modality']} | {series['number_of_instances']} instances | "
                f"{series['unique_spatial_positions']} positions | frames={frame_text} | "
                f"{series['acquisition_type']} | {series['series_description']}"
            )
            for warning in series["warnings"]:
                print(f"    WARNING: {warning}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="vtseg",
        description="Experimental cardiac DICOM preparation and segmentation evaluation",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    inspect_parser = sub.add_parser("inspect-dicom", help="inventory studies and series")
    inspect_parser.add_argument("dicom_directory", type=Path)
    inspect_parser.add_argument("--json", dest="json_path", type=Path)

    prepare_parser = sub.add_parser("prepare-series", help="prepare an explicitly selected 3-D acquisition")
    prepare_parser.add_argument("dicom_directory", type=Path)
    prepare_parser.add_argument("--series", required=True, help="SeriesInstanceUID from inspect-dicom")
    prepare_parser.add_argument("--frame", type=int, help="zero-based temporal frame index")
    prepare_parser.add_argument("--output", required=True, type=Path, help="ignored case directory")

    check_parser = sub.add_parser("check-ct-backend", help="verify TotalSegmentator discovery only")
    check_parser.add_argument("--json", dest="json_output", action="store_true")

    segment_parser = sub.add_parser("segment-ct", help="run the CT cardiac adapter and QC")
    segment_parser.add_argument("case_directory", type=Path)
    segment_parser.add_argument("--device", default="gpu", choices=("gpu", "cpu", "mps"))
    segment_parser.add_argument("--higher-order-resampling", action="store_true")
    segment_parser.add_argument(
        "--force-split",
        action="store_true",
        help="split a large volume into parts to reduce TotalSegmentator memory use",
    )

    map_ct_parser = sub.add_parser(
        "map-ct-masks-to-mpr",
        help="nearest-neighbor map native CT canonical masks into a prepared short-axis MPR",
    )
    map_ct_parser.add_argument("native_case_directory", type=Path)
    map_ct_parser.add_argument("mpr_case_directory", type=Path)

    promote_ct_parser = sub.add_parser(
        "promote-ct-candidate",
        help="copy a Slicer-approved CT MPR candidate into an explicit best result",
    )
    promote_ct_parser.add_argument("mpr_case_directory", type=Path)
    promote_ct_parser.add_argument("--candidate", required=True, choices=("direct-mpr", "native-mapped"))
    promote_ct_parser.add_argument("--output", required=True, type=Path)

    bivme_check_parser = sub.add_parser(
        "check-bivme-backend",
        help="verify the external biv-me source, environment, and model artifacts",
    )
    bivme_check_parser.add_argument("--bivme-root", type=Path)
    bivme_check_parser.add_argument("--python-executable", type=Path)

    bivme_parser = sub.add_parser(
        "segment-mri-bivme",
        help="run cine-CMR biv-me fitting, canonical rasterization, and QC",
    )
    bivme_parser.add_argument("case_directory", type=Path)
    bivme_parser.add_argument("--dicom-directory", required=True, type=Path)
    bivme_parser.add_argument("--bivme-root", type=Path)
    bivme_parser.add_argument("--python-executable", type=Path)
    bivme_parser.add_argument("--device", default="gpu", choices=("gpu", "cpu"))
    bivme_parser.add_argument("--frame", type=int)
    bivme_parser.add_argument(
        "--view-correction",
        default="automatic",
        choices=("automatic", "adaptive", "manual"),
    )
    bivme_parser.add_argument(
        "--ed-frame",
        type=int,
        default=0,
        help=(
            "temporal phase biv-me anchors breath-hold correction to (default 0). "
            "Raise it when raw/execution.log reports no tricuspid valve points at "
            "the ED phase but later phases are fine."
        ),
    )
    bivme_parser.add_argument(
        "--view-predictions",
        type=Path,
        help=(
            "CSV of view assignments to use instead of biv-me's own classification, "
            "in the format of raw/processing/run/case/view-classification/"
            "view_predictions.csv. Bypasses the correction GUI, so a headless "
            "session can reproduce a corrected view assignment."
        ),
    )
    bivme_parser.add_argument(
        "--breathhold-shift",
        default="derived_from_ed",
        choices=BREATHHOLD_SHIFT_MODES,
        help=(
            "breath-hold slice-shift correction (default derived_from_ed). Use 'none' "
            "when models/case/shift_file.txt shows slices displaced far further than a "
            "breath hold, which happens when the long-axis views are unreliable."
        ),
    )
    bivme_parser.add_argument("--workers", type=int, default=4)
    bivme_parser.add_argument("--plots", action="store_true")

    review_parser = sub.add_parser(
        "collect-review",
        help="copy the reviewable image/mask pairs into <case>/review/",
    )
    review_parser.add_argument("case_directory", type=Path)

    lge_parser = sub.add_parser(
        "align-bivme-lge",
        help="phase-match and rigidly align fitted biv-me meshes to native LGE geometry",
    )
    lge_parser.add_argument("case_directory", type=Path)
    lge_parser.add_argument("--dicom-directory", required=True, type=Path)
    lge_parser.add_argument("--lge-series", help="explicit LGE SeriesInstanceUID")
    lge_parser.add_argument("--mesh-frame", type=int, help="override automatic trigger-time matching")

    matlab_parser = sub.add_parser(
        "export-matlab-seg",
        help="export canonical masks as a MATLAB meshing case (raw/ DICOMs + seg/ stacks)",
    )
    matlab_parser.add_argument("mask_directory", type=Path)
    matlab_parser.add_argument("--reference", required=True, type=Path,
                               help="prepared case whose geometry the masks share")
    matlab_parser.add_argument("--output", required=True, type=Path)
    matlab_parser.add_argument(
        "--slicer-approved",
        action="store_true",
        required=True,
        help="confirm that the image/mask alignment was reviewed and approved in 3D Slicer",
    )
    matlab_parser.add_argument(
        "--slices",
        type=int,
        help="total slices within the selected range; both endpoints are retained",
    )
    matlab_parser.add_argument(
        "--flat",
        action="store_true",
        help=(
            "write the case directly into --output instead of the default layout of an "
            "editable work/ case beside a read-only original/ copy"
        ),
    )

    matlab_import_parser = sub.add_parser(
        "import-matlab-seg",
        help="import corrected MATLAB mask stacks as canonical manual NIfTI masks",
    )
    matlab_import_parser.add_argument("matlab_case_directory", type=Path)
    matlab_import_parser.add_argument("--reference", required=True, type=Path)
    matlab_import_parser.add_argument("--output", required=True, type=Path)
    matlab_parser.add_argument("--start-slice", type=int, default=1, help="one-based start in the chosen slice order")
    matlab_parser.add_argument("--end-slice", type=int, help="one-based end in the chosen slice order")
    matlab_parser.add_argument(
        "--slice-order",
        choices=("base-to-apex", "reference", "reverse-reference"),
        default="base-to-apex",
        help="base-to-apex infers direction from mask area; reference and reverse-reference use explicit NIfTI z order",
    )

    preview_parser = sub.add_parser(
        "preview-matlab-slices",
        help="show MATLAB-export selection positions without copying DICOM files",
    )
    preview_parser.add_argument("mask_directory", type=Path)
    preview_parser.add_argument("--reference", required=True, type=Path)
    preview_parser.add_argument(
        "--slice-order",
        choices=("base-to-apex", "reference", "reverse-reference"),
        default="base-to-apex",
    )

    qc_parser = sub.add_parser("qc-masks", help="recompute QC for normalized masks")
    qc_parser.add_argument("case_directory", type=Path)

    mri_status_parser = sub.add_parser("mri-status", help="report the cine-CMR biv-me backend")
    mri_status_parser.add_argument("--bivme-root", type=Path)
    mri_status_parser.add_argument("--python-executable", type=Path)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        if args.command == "inspect-dicom":
            report = inventory_report(scan_headers(args.dicom_directory))
            _print_inventory(report)
            if args.json_path:
                write_json(args.json_path, report)
                print(f"\nWrote inventory: {args.json_path}")
            return 0

        if args.command == "prepare-series":
            inventory = scan_headers(args.dicom_directory)
            provenance = prepare_series(
                inventory,
                args.series,
                args.output,
                frame=args.frame,
                repo_root=_repo_root(),
            )
            print(
                f"Prepared {provenance['modality']} volume with "
                f"{provenance['source_dicom_count']} spatial slices at "
                f"{args.output.resolve() / 'volume' / 'image.nii.gz'}"
            )
            return 0

        if args.command == "check-ct-backend":
            status = asdict(TotalSegmentatorCTBackend().status())
            print(json.dumps(status, indent=2, sort_keys=True))
            return 0 if status["available"] else 2

        if args.command == "segment-ct":
            provenance = TotalSegmentatorCTBackend().run(
                args.case_directory,
                device=args.device,
                higher_order_resampling=args.higher_order_resampling,
                force_split=args.force_split,
                repo_root=_repo_root(),
            )
            print(
                "Segmentation and QC complete: "
                f"{args.case_directory.resolve() / 'segmentation' / 'totalsegmentator' / 'normalized'}"
            )
            print(json.dumps({"warnings": provenance["warnings"]}, indent=2))
            return 0

        if args.command == "map-ct-masks-to-mpr":
            provenance = map_native_ct_masks_to_mpr(
                args.native_case_directory, args.mpr_case_directory, repo_root=_repo_root()
            )
            print("Native CT masks mapped onto the MPR grid with nearest-neighbor interpolation")
            print(json.dumps({"warnings": provenance["warnings"]}, indent=2))
            return 0

        if args.command == "promote-ct-candidate":
            provenance = promote_ct_candidate(
                args.mpr_case_directory, args.candidate, args.output, repo_root=_repo_root()
            )
            print(f"Promoted {args.candidate} CT candidate to {args.output.resolve()}")
            print(json.dumps({"warnings": provenance["warnings"]}, indent=2))
            return 0

        if args.command == "check-bivme-backend":
            status = asdict(BivMeMRIBackend(
                root=args.bivme_root,
                python_executable=args.python_executable,
            ).status())
            print(json.dumps(status, indent=2, sort_keys=True))
            return 0 if status["available"] else 2

        if args.command == "segment-mri-bivme":
            provenance = BivMeMRIBackend(
                root=args.bivme_root,
                python_executable=args.python_executable,
            ).run(
                args.case_directory,
                dicom_directory=args.dicom_directory,
                device=args.device,
                frame=args.frame,
                correct_mode=args.view_correction,
                ed_frame=args.ed_frame,
                breathhold_shift=args.breathhold_shift,
                view_predictions=args.view_predictions,
                workers=args.workers,
                generate_plots=args.plots,
                repo_root=_repo_root(),
            )
            print("biv-me segmentation, rasterization, and QC complete")
            print(json.dumps({"warnings": provenance["warnings"]}, indent=2))
            return 0

        if args.command == "collect-review":
            manifest = collect_review(args.case_directory)
            print(f"Collected {len(manifest['pairs'])} review pair(s) in {args.case_directory}/review")
            for pair in manifest["pairs"]:
                print(f"  {pair['id']}: frame {pair['frame']} ({pair['space']} space)")
            for skipped in manifest["skipped_pairs"]:
                print(f"  skipped {skipped['id']}: missing {skipped['missing']}")
            for warning in manifest["warnings"]:
                print(f"  WARNING: {warning}")
            return 0

        if args.command == "align-bivme-lge":
            provenance = align_bivme_to_lge(
                args.case_directory,
                dicom_directory=args.dicom_directory,
                lge_series_uid=args.lge_series,
                mesh_frame=args.mesh_frame,
                repo_root=_repo_root(),
            )
            print("biv-me meshes aligned and rasterized on native LGE geometry")
            print(json.dumps({"warnings": provenance["warnings"]}, indent=2))
            return 0

        if args.command == "export-matlab-seg":
            manifest = export_matlab_case(
                args.mask_directory,
                args.reference,
                args.output,
                slices=args.slices,
                start_slice=args.start_slice,
                end_slice=args.end_slice,
                slice_order=args.slice_order.replace("-", "_"),
                slicer_approved=args.slicer_approved,
                keep_original=not args.flat,
                repo_root=_repo_root(),
            )
            case_root = args.output if args.flat else args.output / "work"
            print(f"exported {manifest['slice_count']} slices to {case_root}")
            if not args.flat:
                print(f"read-only copy of the export kept in {args.output / 'original'}")
            print(json.dumps({"mask_dimensions": manifest["mask_dimensions"]}, indent=2))
            return 0

        if args.command == "preview-matlab-slices":
            preview = preview_matlab_slices(
                args.mask_directory,
                args.reference,
                slice_order=args.slice_order.replace("-", "_"),
            )
            print(json.dumps(preview, indent=2))
            return 0

        if args.command == "import-matlab-seg":
            metadata = import_matlab_case(
                args.matlab_case_directory,
                args.reference,
                args.output,
                repo_root=_repo_root(),
            )
            print(f"imported {metadata['selected_slice_count']} corrected MATLAB slices")
            return 0

        if args.command == "qc-masks":
            report = run_case_qc(args.case_directory)
            print(json.dumps({"warnings": report["warnings"]}, indent=2))
            return 0

        if args.command == "mri-status":
            status = asdict(BivMeMRIBackend(
                root=args.bivme_root,
                python_executable=args.python_executable,
            ).status())
            print(json.dumps(status, indent=2, sort_keys=True))
            return 0 if status["available"] else 2
    except VTSegError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
