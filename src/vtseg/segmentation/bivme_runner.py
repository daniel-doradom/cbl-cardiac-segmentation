"""Launch biv-me with narrowly scoped adapter compatibility fixes."""

from __future__ import annotations

import importlib
import runpy
import sys
from pathlib import Path


def remove_ambiguous_loc_filter(terms: list[str]) -> list[str]:
    """Keep biv-me filters except the substring that rejects valid cardiac cines."""
    return [term for term in terms if term != "loc"]


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("biv-me main script path is required")

    runner_directory = Path(__file__).resolve().parent
    sys.path = [
        entry
        for entry in sys.path
        if Path(entry or ".").resolve() != runner_directory
    ]
    extract_cines = importlib.import_module(
        "bivme.preprocessing.dicom.extract_cines"
    )

    extract_cines.EXCLUSION_TERMS = remove_ambiguous_loc_filter(
        extract_cines.EXCLUSION_TERMS
    )
    main_script = sys.argv[1]
    sys.argv = [main_script, *sys.argv[2:]]
    runpy.run_path(main_script, run_name="__main__")


if __name__ == "__main__":
    main()
