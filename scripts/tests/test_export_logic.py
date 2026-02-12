"""Unit tests for export_to_hf.py dedup, merge, and transform logic.

No Xano connection needed — tests use fixtures from conftest.py.
"""

import json
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

# Add scripts/ to path so we can import export_to_hf
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from export_to_hf import (
    build_dataset_features,
    dedup_articles,
    dedup_chunks,
    filter_stale_chunks,
    merge_chunks_with_articles,
    transform_row,
)


class TestDedupArticles:
    def test_no_duplicates(self, sample_articles):
        result = dedup_articles(sample_articles)
        assert len(result) == 3

    def test_keeps_last_occurrence(self):
        articles = [
            {"id_legifrance": "ART1", "num": "old"},
            {"id_legifrance": "ART1", "num": "new"},
            {"id_legifrance": "ART2", "num": "only"},
        ]
        result = dedup_articles(articles)
        assert len(result) == 2
        art1 = [a for a in result if a["id_legifrance"] == "ART1"][0]
        assert art1["num"] == "new"

    def test_empty_list(self):
        assert dedup_articles([]) == []


class TestDedupChunks:
    def test_no_duplicates(self, sample_chunks):
        result = dedup_chunks(sample_chunks)
        assert len(result) == 3

    def test_keeps_last_by_id_and_index(self):
        chunks = [
            {"id_legifrance": "ART1", "chunk_index": 0, "chunk_text": "old"},
            {"id_legifrance": "ART1", "chunk_index": 0, "chunk_text": "new"},
            {"id_legifrance": "ART1", "chunk_index": 1, "chunk_text": "second"},
        ]
        result = dedup_chunks(chunks)
        assert len(result) == 2
        chunk_0 = [c for c in result if c["chunk_index"] == 0][0]
        assert chunk_0["chunk_text"] == "new"

    def test_empty_list(self):
        assert dedup_chunks([]) == []


class TestFilterStaleChunks:
    def test_removes_stale(self):
        chunks = [
            {"id": 1, "is_stale": False},
            {"id": 2, "is_stale": True},
            {"id": 3, "is_stale": False},
        ]
        result = filter_stale_chunks(chunks)
        assert len(result) == 2
        assert all(not c["is_stale"] for c in result)

    def test_missing_is_stale_treated_as_fresh(self):
        chunks = [{"id": 1}, {"id": 2, "is_stale": False}]
        result = filter_stale_chunks(chunks)
        assert len(result) == 2

    def test_all_stale(self):
        chunks = [{"id": 1, "is_stale": True}]
        assert filter_stale_chunks(chunks) == []


class TestMergeChunksWithArticles:
    @patch("export_to_hf.fetch_code_names")
    def test_basic_merge(self, mock_codes, sample_chunks, sample_articles, sample_code_names):
        mock_codes.return_value = sample_code_names
        result = merge_chunks_with_articles(sample_chunks, sample_articles, "http://fake")
        assert len(result) == 3
        assert all("code_name" in r for r in result)

    @patch("export_to_hf.fetch_code_names")
    def test_orphan_chunks_skipped(self, mock_codes, sample_articles, sample_code_names):
        mock_codes.return_value = sample_code_names
        orphan_chunk = {
            "id_legifrance": "NONEXISTENT",
            "chunk_index": 0,
            "chunk_text": "orphan",
            "code": "LEGITEXT000006070721",
        }
        result = merge_chunks_with_articles([orphan_chunk], sample_articles, "http://fake")
        assert len(result) == 0

    @patch("export_to_hf.fetch_code_names")
    def test_contenu_article_renamed(self, mock_codes, sample_chunks, sample_articles, sample_code_names):
        mock_codes.return_value = sample_code_names
        result = merge_chunks_with_articles(sample_chunks, sample_articles, "http://fake")
        for row in result:
            assert "article_contenu_article" not in row
            assert "article_texte" in row


class TestTransformRow:
    def test_coerces_embedding_string(self):
        features = build_dataset_features()
        raw = {"embedding": json.dumps([0.1] * 1024), "chunk_text": "hello"}
        row = transform_row(raw, features)
        assert isinstance(row["embedding"], list)
        assert len(row["embedding"]) == 1024

    def test_missing_fields_are_none(self):
        features = build_dataset_features()
        row = transform_row({}, features)
        assert row["chunk_text"] is None
        assert row["embedding"] is None
