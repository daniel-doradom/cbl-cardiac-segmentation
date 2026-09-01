import pytest

from vtseg.dicom.temporal import analyze_temporal, select_frame
from vtseg.errors import SeriesSelectionError


def cine_headers(header_factory):
    result = []
    instance = 1
    for z in (0.0, 4.0, 8.0):
        for trigger in (10.0, 20.0):
            result.append(
                header_factory(
                    z,
                    instance,
                    TriggerTime=trigger,
                    CardiacNumberOfImages=2,
                )
            )
            instance += 1
    return result


def test_trigger_time_supports_defensible_frame_selection(header_factory):
    headers = cine_headers(header_factory)
    analysis = analyze_temporal(headers)
    assert analysis.defensible
    assert analysis.inferred_frames == 2
    assert analysis.unique_spatial_positions == 3
    selected, metadata = select_frame(headers, 1)
    assert len(selected) == 3
    assert {h.TriggerTime for h in selected} == {20.0}
    assert metadata["temporal_key"] == "TriggerTime"


def test_cine_requires_explicit_frame(header_factory):
    with pytest.raises(SeriesSelectionError, match="select one explicitly"):
        select_frame(cine_headers(header_factory), None)


def test_repeated_positions_without_temporal_tag_are_ambiguous(header_factory):
    headers = [header_factory(0, 1), header_factory(0, 2)]
    analysis = analyze_temporal(headers)
    assert not analysis.defensible
    with pytest.raises(SeriesSelectionError, match="cannot be inferred safely"):
        select_frame(headers, 0)


def test_static_series_rejects_frame_argument(header_factory):
    headers = [header_factory(0, 1), header_factory(4, 2)]
    with pytest.raises(SeriesSelectionError, match="non-temporal"):
        select_frame(headers, 0)
