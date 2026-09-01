class VTSegError(RuntimeError):
    """Base class for expected, user-actionable pipeline failures."""


class DicomInspectionError(VTSegError):
    pass


class SeriesSelectionError(VTSegError):
    pass


class GeometryError(VTSegError):
    pass


class UnsupportedModality(VTSegError):
    pass


class BackendUnavailable(VTSegError):
    pass


class NormalizationError(VTSegError):
    pass
