"""Shared Qdrant SDK adapter for the memory-engine package.

Loads the third-party qdrant-client package without colliding with the local
apps/memory-engine/qdrant_client.py module name. Falls back to lightweight
in-memory stubs when the external dependency is unavailable.
"""

from __future__ import annotations

import importlib
import sys
from dataclasses import dataclass, field
from pathlib import Path
from types import SimpleNamespace
from typing import Any, List


def _load_external_qdrant_sdk():
    current_dir = Path(__file__).resolve().parent
    removed_paths: list[tuple[int, str]] = []
    for index in range(len(sys.path) - 1, -1, -1):
        entry = sys.path[index] or "."
        try:
            resolved = Path(entry).resolve()
        except OSError:
            continue
        if resolved == current_dir:
            removed_paths.append((index, sys.path.pop(index)))

    current_qdrant_module = sys.modules.pop("qdrant_client", None)
    try:
        package = importlib.import_module("qdrant_client")
        models = importlib.import_module("qdrant_client.http.models")
        return package, models
    finally:
        if current_qdrant_module is not None:
            sys.modules["qdrant_client"] = current_qdrant_module
        for index, entry in reversed(removed_paths):
            sys.path.insert(index, entry)


try:
    _qdrant_package, _qdrant_models = _load_external_qdrant_sdk()
except Exception:
    _qdrant_package = None
    _qdrant_models = None


if _qdrant_package is not None and _qdrant_models is not None:
    QdrantClient = _qdrant_package.QdrantClient
    Distance = _qdrant_models.Distance
    VectorParams = _qdrant_models.VectorParams
    PointStruct = _qdrant_models.PointStruct
    Filter = _qdrant_models.Filter
    FieldCondition = _qdrant_models.FieldCondition
    MatchValue = _qdrant_models.MatchValue
    HasIdCondition = getattr(_qdrant_models, "HasIdCondition", None)
    PayloadSchemaType = _qdrant_models.PayloadSchemaType
    PayloadIndexParams = getattr(_qdrant_models, "PayloadIndexParams", None)
else:
    class Distance:
        COSINE = "Cosine"


    @dataclass
    class VectorParams:
        size: int
        distance: str
        on_disk: bool = False


    @dataclass
    class PointStruct:
        id: int
        vector: List[float]
        payload: dict[str, Any]


    @dataclass
    class MatchValue:
        value: Any


    @dataclass
    class FieldCondition:
        key: str
        match: MatchValue | None = None


    @dataclass
    class Filter:
        must: list[FieldCondition] = field(default_factory=list)


    @dataclass
    class HasIdCondition:
        has_id: list[int] = field(default_factory=list)


    class PayloadSchemaType:
        KEYWORD = "keyword"
        INTEGER = "integer"
        FLOAT = "float"
        DATETIME = "datetime"


    @dataclass
    class PayloadIndexParams:
        field_type: str | None = None


    class _CollectionInfo:
        def __init__(self, points_count: int = 0):
            self.points_count = points_count


    class _CollectionsResponse:
        def __init__(self, names: list[str]):
            self.collections = [SimpleNamespace(name=name) for name in names]


    class QdrantClient:
        def __init__(self, host: str = "localhost", port: int = 6333):
            self.host = host
            self.port = port
            self._collections: dict[str, _CollectionInfo] = {}

        def get_collection(self, collection_name: str):
            if collection_name not in self._collections:
                raise KeyError(collection_name)
            return self._collections[collection_name]

        def create_collection(self, collection_name: str, vectors_config=None, **kwargs):
            self._collections[collection_name] = _CollectionInfo()
            return True

        def upsert(self, collection_name: str, points=None, **kwargs):
            self._collections.setdefault(collection_name, _CollectionInfo())
            return True

        def search(self, collection_name: str, query_vector=None, limit: int = 10, **kwargs):
            return []

        def get_collections(self):
            return _CollectionsResponse(list(self._collections))

        def delete_collection(self, collection_name: str):
            self._collections.pop(collection_name, None)
            return True

        def create_payload_index(self, collection_name: str, field_name: str, field_schema=None, **kwargs):
            return True
