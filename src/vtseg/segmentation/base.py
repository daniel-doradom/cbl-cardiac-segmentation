"""Small backend contract; downstream code sees only canonical masks."""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class BackendStatus:
    name: str
    available: bool
    version: str | None
    task: str | None
    detail: str
    capabilities: dict[str, Any]


class SegmentationBackend(ABC):
    @abstractmethod
    def status(self) -> BackendStatus:
        raise NotImplementedError

    @abstractmethod
    def run(self, case_dir: Path, **options: Any) -> dict[str, Any]:
        raise NotImplementedError
