import numpy as np
import pytest

from vtseg.dicom.geometry import (
    LPS_TO_RAS,
    affine_spacing,
    dicom_affine_lps,
    dicom_affine_ras,
    geometry_compatible,
    spatial_order,
)
from vtseg.errors import GeometryError


def test_spatial_order_uses_patient_position_not_instance_number(header_factory):
    headers = [header_factory(8, 1), header_factory(0, 3), header_factory(4, 2)]
    assert [h.ImagePositionPatient[2] for h in spatial_order(headers)] == [0, 4, 8]


def test_affine_preserves_dicom_geometry_and_converts_lps_to_ras(header_factory):
    headers = [header_factory(0, 1), header_factory(4, 2)]
    lps = dicom_affine_lps(headers)
    assert np.allclose(lps[:3, 0], [0, 2, 0])
    assert np.allclose(lps[:3, 1], [3, 0, 0])
    assert np.allclose(lps[:3, 2], [0, 0, 4])
    assert np.allclose(lps[:3, 3], [10, 20, 0])
    assert np.allclose(dicom_affine_ras(headers), LPS_TO_RAS @ lps)
    assert affine_spacing(lps) == pytest.approx((2, 3, 4))


def test_inconsistent_orientation_fails(header_factory):
    headers = [
        header_factory(0, 1),
        header_factory(4, 2, ImageOrientationPatient=[0, 1, 0, 1, 0, 0]),
    ]
    with pytest.raises(GeometryError, match="inconsistent"):
        spatial_order(headers)


def test_geometry_compatibility_checks_shape_and_affine():
    affine = np.eye(4)
    assert geometry_compatible((2, 3, 4), affine, (2, 3, 4), affine.copy())
    assert not geometry_compatible((2, 3, 4), affine, (2, 3, 5), affine)
    shifted = affine.copy()
    shifted[0, 3] = 1
    assert not geometry_compatible((2, 3, 4), affine, (2, 3, 4), shifted)
