"""
data_loader.py — Dataset loading + FAISS index construction + query embedding.

Runs at Space startup (once). Each dataset gets a FAISS index built in memory.
Graceful degradation: if one source fails, the others continue.
"""

import os
import numpy as np
from datasets import load_dataset
from huggingface_hub import InferenceClient

DATASET_REPO = "ArthurSrz/open_codes"
EMBED_MODEL = "mistral-embed"
EMBED_DIM = 1024

# Tracks which sources loaded successfully
LOADING_STATUS: dict[str, bool] = {
    "articles": False,
    "jurisprudence": False,
    "circulaires": False,
    "reponses": False,
}

_datasets: dict = {}


def load_all_datasets() -> dict:
    """
    Load all four configs from ArthurSrz/open_codes and build FAISS indexes.
    Returns dict with keys: articles, jurisprudence, circulaires, reponses.
    Missing sources have value None.
    """
    configs = [
        ("articles",      "default"),
        ("jurisprudence", "jurisprudence"),
        ("circulaires",   "circulaires"),
        ("reponses",      "reponses_legis"),
    ]

    result: dict = {}

    for key, config_name in configs:
        try:
            print(f"[data_loader] Loading {config_name}…")
            ds = load_dataset(DATASET_REPO, name=config_name, split="train")
            ds.add_faiss_index(column="embedding")
            result[key] = ds
            LOADING_STATUS[key] = True
            print(f"[data_loader] ✓ {config_name}: {len(ds)} rows, FAISS index built")
        except Exception as e:
            print(f"[data_loader] ✗ {config_name} failed: {e}")
            result[key] = None
            LOADING_STATUS[key] = False

    _datasets.update(result)
    return result


def embed_query(query_text: str, hf_token: str) -> list[float]:
    """
    Embed a query string using Mistral mistral-embed via HF Inference API.
    Returns a 1024-dim float list.
    Raises ValueError with user-readable message on failure.
    """
    try:
        client = InferenceClient(token=hf_token)
        response = client.feature_extraction(
            text=query_text,
            model=EMBED_MODEL,
        )
        # feature_extraction returns np.ndarray — flatten to 1D list
        embedding = np.array(response).flatten().tolist()
        if len(embedding) != EMBED_DIM:
            raise ValueError(
                f"Embedding dimension mismatch: expected {EMBED_DIM}, got {len(embedding)}"
            )
        return embedding
    except Exception as e:
        raise ValueError(
            f"Impossible d'encoder la requête : {e}. "
            "Vérifiez que HF_TOKEN est configuré et que le quota API n'est pas dépassé."
        ) from e
