"""Conservative temporal-frame detection for classic single-frame DICOM."""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass

from vtseg.dicom.geometry import slice_coordinate
from vtseg.errors import SeriesSelectionError


@dataclass(frozen=True)
class TemporalAnalysis:
    repeated_spatial_positions: int
    unique_spatial_positions: int
    inferred_frames: int | None
    temporal_key: str | None
    defensible: bool
    reason: str


def _position_key(dataset: object, tolerance_mm: float = 1e-3) -> int:
    coordinate = slice_coordinate(
        dataset.ImagePositionPatient, dataset.ImageOrientationPatient
    )
    return round(coordinate / tolerance_mm)


def _temporal_value(dataset: object, key: str) -> float | int | None:
    value = getattr(dataset, key, None)
    if value in (None, ""):
        return None
    try:
        return int(value) if key == "TemporalPositionIdentifier" else float(value)
    except (TypeError, ValueError):
        return None


def analyze_temporal(datasets: list[object]) -> TemporalAnalysis:
    groups: dict[int, list[object]] = defaultdict(list)
    try:
        for dataset in datasets:
            groups[_position_key(dataset)].append(dataset)
    except Exception:
        return TemporalAnalysis(0, 0, None, None, False, "spatial positions are unavailable")

    repeated = sum(len(group) > 1 for group in groups.values())
    if repeated == 0:
        return TemporalAnalysis(0, len(groups), 1, None, True, "one instance per spatial position")

    counts = {len(group) for group in groups.values()}
    if len(counts) != 1:
        return TemporalAnalysis(
            repeated,
            len(groups),
            None,
            None,
            False,
            "spatial positions contain different instance counts",
        )

    for key in ("TemporalPositionIdentifier", "TriggerTime"):
        value_sets = []
        for group in groups.values():
            values = [_temporal_value(ds, key) for ds in group]
            if any(value is None for value in values) or len(set(values)) != len(values):
                break
            value_sets.append(tuple(sorted(values)))
        else:
            if value_sets and len(set(value_sets)) == 1:
                return TemporalAnalysis(
                    repeated,
                    len(groups),
                    len(value_sets[0]),
                    key,
                    True,
                    f"consistent {key} values across spatial positions",
                )

    return TemporalAnalysis(
        repeated,
        len(groups),
        None,
        None,
        False,
        "repeated positions lack a consistent supported temporal identifier",
    )


def select_frame(datasets: list[object], frame: int | None) -> tuple[list[object], dict[str, object]]:
    analysis = analyze_temporal(datasets)
    if analysis.repeated_spatial_positions == 0:
        if frame is not None:
            raise SeriesSelectionError("--frame was supplied for a non-temporal series")
        return datasets, {"frame": None, "temporal_key": None}
    if not analysis.defensible or not analysis.temporal_key or analysis.inferred_frames is None:
        raise SeriesSelectionError(
            "series has repeated spatial positions but a coherent 3-D frame cannot be "
            f"inferred safely: {analysis.reason}"
        )
    if frame is None:
        raise SeriesSelectionError(
            f"series has {analysis.inferred_frames} inferred frames; select one explicitly with --frame"
        )
    if frame < 0 or frame >= analysis.inferred_frames:
        raise SeriesSelectionError(
            f"frame index {frame} is outside 0..{analysis.inferred_frames - 1}"
        )

    groups: dict[int, list[object]] = defaultdict(list)
    for dataset in datasets:
        groups[_position_key(dataset)].append(dataset)
    selected = []
    selected_values = set()
    for group in groups.values():
        ordered = sorted(group, key=lambda ds: _temporal_value(ds, analysis.temporal_key))
        item = ordered[frame]
        selected.append(item)
        selected_values.add(_temporal_value(item, analysis.temporal_key))
    if len(selected_values) != 1:
        raise SeriesSelectionError(
            "frame indices do not correspond to one consistent temporal value across slices"
        )
    return selected, {
        "frame": frame,
        "temporal_key": analysis.temporal_key,
        "temporal_value": next(iter(selected_values)),
    }
