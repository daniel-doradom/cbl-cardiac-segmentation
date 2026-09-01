from vtseg.segmentation.mri import UnconfiguredMRIBackend
from vtseg.segmentation.totalsegmentator import TotalSegmentatorCTBackend


def test_mri_backend_is_explicitly_unconfigured():
    status = UnconfiguredMRIBackend().status()
    assert not status.available
    assert "No sequence-validated" in status.detail


def test_totalsegmentator_missing_cli_is_precise(monkeypatch):
    monkeypatch.setattr("vtseg.segmentation.totalsegmentator.shutil.which", lambda name: None)
    status = TotalSegmentatorCTBackend().status()
    assert not status.available
    assert status.task == "heartchambers_highres"
    assert "CLI is not installed" in status.detail
