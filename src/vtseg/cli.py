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
from vtseg.segmentation.mri import UnconfiguredMRIBackend
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

    qc_parser = sub.add_parser("qc-masks", help="recompute QC for normalized masks")
    qc_parser.add_argument("case_directory", type=Path)

    sub.add_parser("mri-status", help="report the intentionally unconfigured MRI backend")
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
                f"{args.case_directory.resolve() / 'segmentation' / 'normalized'}"
            )
            print(json.dumps({"warnings": provenance["warnings"]}, indent=2))
            return 0

        if args.command == "qc-masks":
            report = run_case_qc(args.case_directory)
            print(json.dumps({"warnings": report["warnings"]}, indent=2))
            return 0

        if args.command == "mri-status":
            print(json.dumps(asdict(UnconfiguredMRIBackend().status()), indent=2, sort_keys=True))
            return 2
    except VTSegError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
