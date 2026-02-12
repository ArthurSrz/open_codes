"""Integration tests that fetch data from Xano and validate data quality.

These tests require XANO_BASE_URL to be set. They are run in CI before
pushing to HuggingFace — if any fail, the export is aborted.

Usage:
    XANO_BASE_URL=https://... pytest scripts/tests/test_data_quality.py -v
"""

import os
import sys
import time
from pathlib import Path

import pytest
import requests

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from export_to_hf import (
    dedup_articles,
    dedup_chunks,
    fetch_all_articles,
    fetch_all_chunks,
    fetch_code_names,
    filter_stale_chunks,
)

BASE_URL = os.environ.get("XANO_BASE_URL", "")

pytestmark = pytest.mark.skipif(not BASE_URL, reason="XANO_BASE_URL not set")


@pytest.fixture(scope="module")
def articles():
    return fetch_all_articles(BASE_URL)


@pytest.fixture(scope="module")
def chunks():
    raw = fetch_all_chunks(BASE_URL)
    return filter_stale_chunks(raw)


@pytest.fixture(scope="module")
def active_codes():
    return fetch_code_names(BASE_URL)


# --- Article quality ---


class TestArticleQuality:
    def test_no_duplicate_article_ids(self, articles):
        ids = [a["id_legifrance"] for a in articles]
        dupes = len(ids) - len(set(ids))
        assert dupes == 0, f"{dupes} duplicate article IDs found"

    def test_articles_exist(self, articles):
        assert len(articles) > 0, "No articles fetched from Xano"

    def test_all_active_codes_have_articles(self, articles, active_codes):
        article_codes = {a.get("code") for a in articles}
        for text_id, titre in active_codes.items():
            assert text_id in article_codes, (
                f"Active code {titre} ({text_id}) has no articles"
            )

    def test_article_count_per_code(self, articles, active_codes):
        for text_id in active_codes:
            count = sum(1 for a in articles if a.get("code") == text_id)
            assert count > 0, f"Code {text_id} has 0 articles"


# --- Chunk quality ---


class TestChunkQuality:
    def test_no_duplicate_chunk_pairs(self, chunks):
        pairs = [(c["id_legifrance"], c["chunk_index"]) for c in chunks]
        dupes = len(pairs) - len(set(pairs))
        assert dupes == 0, f"{dupes} duplicate (id_legifrance, chunk_index) pairs"

    def test_no_stale_chunks_in_export(self, chunks):
        stale = [c for c in chunks if c.get("is_stale", False)]
        assert len(stale) == 0, f"{len(stale)} stale chunks found after filtering"

    def test_chunk_text_non_empty(self, chunks):
        empty = [c for c in chunks if not c.get("chunk_text", "").strip()]
        assert len(empty) == 0, f"{len(empty)} chunks have empty text"

    def test_chunk_text_length_bounds(self, chunks):
        MAX_CHUNK_LEN = 100_000
        oversized = [c for c in chunks if len(c.get("chunk_text", "")) > MAX_CHUNK_LEN]
        assert len(oversized) == 0, (
            f"{len(oversized)} chunks exceed {MAX_CHUNK_LEN} chars"
        )

    def test_embedding_dimensions(self, chunks):
        bad = []
        for c in chunks:
            emb = c.get("embedding", [])
            if isinstance(emb, str):
                import json
                emb = json.loads(emb)
            if len(emb) != 1024:
                bad.append((c.get("id_legifrance"), c.get("chunk_index"), len(emb)))
        assert len(bad) == 0, f"{len(bad)} chunks have non-1024 embeddings: {bad[:5]}"


# --- Cross-table integrity ---


class TestCrossTableIntegrity:
    def test_no_orphan_chunks(self, chunks, articles):
        article_ids = {a["id_legifrance"] for a in articles}
        orphans = [c for c in chunks if c["id_legifrance"] not in article_ids]
        assert len(orphans) == 0, (
            f"{len(orphans)} orphan chunks (no matching article)"
        )

    def test_no_empty_articles(self, articles, chunks): 
        article_chunk_counts = {}
        for c in chunks:
            article_chunk_counts[c["id_legifrance"]] = article_chunk_counts.get(c["id_legifrance"], 0) + 1
        empty_articles = [a for a in articles if article_chunk_counts.get(a["id_legifrance"], 0) == 0]
        assert len(empty_articles) == 0, f"{len(empty_articles)} articles have no chunks"
    
    def test_metadata_completeness(self, articles, chunks): 
        article_map = {a["id_legifrance"]: a for a in articles}
        incomplete = []
        for c in chunks:
            article = article_map.get(c["id_legifrance"], {})
            if not article.get("code") or not article.get("num"):
                incomplete.append((c["id_legifrance"], c["chunk_index"]))
        assert len(incomplete) == 0, f"{len(incomplete)} chunks linked to articles with incomplete metadata: {incomplete[:5]}"


# --- Date & applicability ---

# Legifrance dates are Unix timestamps in milliseconds (stored as strings).
# Sentinel: 32472144000000 = year 2999 = "indefinitely in force".
INDEFINITE_DATE_MS = 32472144000000


def _parse_date_ms(val) -> int | None:
    """Parse a Legifrance date field to int (ms) or None if missing/invalid."""
    if val is None or val == "" or val == "null":
        return None
    try:
        return int(val)
    except (ValueError, TypeError):
        return None


class TestDateQuality:
    def test_dateDebut_populated(self, articles):
        """Every article should have a start date."""
        missing = [a["id_legifrance"] for a in articles if _parse_date_ms(a.get("dateDebut")) is None]
        assert len(missing) == 0, f"{len(missing)} articles missing dateDebut: {missing[:5]}"

    def test_dateFin_populated(self, articles):
        """Every article should have an end date (possibly the 2999 sentinel)."""
        missing = [a["id_legifrance"] for a in articles if _parse_date_ms(a.get("dateFin")) is None]
        assert len(missing) == 0, f"{len(missing)} articles missing dateFin: {missing[:5]}"

    def test_vigueur_articles_not_expired(self, articles):
        """VIGUEUR articles should have dateFin in the future or set to 2999 sentinel."""
        now_ms = int(time.time() * 1000)
        expired = []
        for a in articles:
            if a.get("etat") != "VIGUEUR":
                continue
            date_fin = _parse_date_ms(a.get("dateFin"))
            if date_fin is not None and date_fin < now_ms and date_fin != INDEFINITE_DATE_MS:
                expired.append((a["id_legifrance"], a.get("num"), date_fin))
        assert len(expired) == 0, (
            f"{len(expired)} VIGUEUR articles have expired dateFin: {expired[:5]}"
        )

    def test_dateDebut_before_dateFin(self, articles):
        """Start date should be before or equal to end date."""
        inverted = []
        for a in articles:
            debut = _parse_date_ms(a.get("dateDebut"))
            fin = _parse_date_ms(a.get("dateFin"))
            if debut is not None and fin is not None and debut > fin:
                inverted.append((a["id_legifrance"], a.get("num"), debut, fin))
        assert len(inverted) == 0, (
            f"{len(inverted)} articles have dateDebut > dateFin: {inverted[:5]}"
        )

    def test_etat_field_populated(self, articles):
        """Every article must have an etat (VIGUEUR, ABROGE, MODIFIE, etc.)."""
        missing = [a["id_legifrance"] for a in articles if not a.get("etat")]
        assert len(missing) == 0, f"{len(missing)} articles missing etat: {missing[:5]}"
