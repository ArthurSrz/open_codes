"""Shared pytest fixtures for data quality and export logic tests."""

import pytest


@pytest.fixture
def sample_articles():
    """Minimal article records for testing."""
    return [
        {
            "id": 1,
            "id_legifrance": "LEGIARTI000006900001",
            "code": "LEGITEXT000006070721",
            "num": "1",
            "contenu_article": "Le texte de l'article 1.",
            "content_hash": "abc123",
            "last_sync_at": "2026-01-01",
            "etat": "VIGUEUR",
        },
        {
            "id": 2,
            "id_legifrance": "LEGIARTI000006900002",
            "code": "LEGITEXT000006070721",
            "num": "2",
            "contenu_article": "Le texte de l'article 2.",
            "content_hash": "def456",
            "last_sync_at": "2026-01-01",
            "etat": "VIGUEUR",
        },
        {
            "id": 3,
            "id_legifrance": "LEGIARTI000006900003",
            "code": "LEGITEXT000006070633",
            "num": "L2121-1",
            "contenu_article": "Article du CGCT.",
            "content_hash": "ghi789",
            "last_sync_at": "2026-01-01",
            "etat": "VIGUEUR",
        },
    ]


@pytest.fixture
def sample_chunks():
    """Minimal chunk records for testing."""
    return [
        {
            "id": 10,
            "id_legifrance": "LEGIARTI000006900001",
            "code": "LEGITEXT000006070721",
            "num": "1",
            "etat": "VIGUEUR",
            "fullSectionsTitre": "Livre I > Titre I",
            "chunk_index": 0,
            "chunk_text": "Le texte de l'article 1.",
            "start_position": 0,
            "end_position": 24,
            "embedding": [0.1] * 1024,
            "is_stale": False,
        },
        {
            "id": 11,
            "id_legifrance": "LEGIARTI000006900002",
            "code": "LEGITEXT000006070721",
            "num": "2",
            "etat": "VIGUEUR",
            "fullSectionsTitre": "Livre I > Titre I",
            "chunk_index": 0,
            "chunk_text": "Le texte de l'article 2.",
            "start_position": 0,
            "end_position": 24,
            "embedding": [0.2] * 1024,
            "is_stale": False,
        },
        {
            "id": 12,
            "id_legifrance": "LEGIARTI000006900003",
            "code": "LEGITEXT000006070633",
            "num": "L2121-1",
            "etat": "VIGUEUR",
            "fullSectionsTitre": "Partie legislative > Livre I",
            "chunk_index": 0,
            "chunk_text": "Article du CGCT.",
            "start_position": 0,
            "end_position": 16,
            "embedding": [0.3] * 1024,
            "is_stale": False,
        },
    ]


@pytest.fixture
def sample_code_names():
    return {
        "LEGITEXT000006070721": "Code civil",
        "LEGITEXT000006070633": "Code general des collectivites territoriales",
    }
