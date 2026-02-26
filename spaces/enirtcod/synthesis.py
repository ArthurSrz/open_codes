"""
synthesis.py — LLM synthesis with inline French legal citations.
"""

from huggingface_hub import InferenceClient

GENERATION_MODEL = "mistralai/Mistral-7B-Instruct-v0.3"

SYSTEM_PROMPT = """Tu es un assistant juridique français expert. Réponds à la question en te basant UNIQUEMENT sur les extraits numérotés fournis. N'utilise aucune connaissance extérieure.

Pour chaque affirmation, cite la source entre crochets selon le style juridique français :
- Articles de loi : [Code civil, art. 1240] ou [C. trav., art. L.1237-19]
- Décisions de justice : [Cass. 1re civ., 13 avr. 2023, n° 21-20.145] ou [CA Paris, 15 janv. 2024]
- Circulaires : [Circ. n° 2023-045, ministère du Travail]
- Réponses ministérielles : [Q. n° 12345, ministère de la Justice]

Si les extraits ne permettent pas de répondre à la question, réponds exactement : "Aucun résultat pertinent trouvé pour cette requête."
Réponds en français, en 3 à 6 phrases de prose juridique claire et structurée."""


def format_context_for_llm(results_dict: dict) -> str:
    """
    Build a numbered context string from all retrieved chunks.
    Each chunk gets a citation key appropriate to its source type.
    """
    lines = []
    counter = 1

    source_configs = [
        ("articles",      _article_citation_key),
        ("jurisprudence", _decision_citation_key),
        ("circulaires",   _circulaire_citation_key),
        ("reponses",      _reponse_citation_key),
    ]

    for source, key_fn in source_configs:
        for result in results_dict.get(source, []):
            snippet = (result.get("chunk_text") or "")[:500]
            citation = key_fn(result)
            lines.append(f"[{counter}] ({citation})\n{snippet}")
            counter += 1

    return "\n\n".join(lines)


def synthesize(query: str, results_dict: dict, hf_token: str) -> str:
    """
    Generate a prose synthesis with inline citations using Mistral 7B Instruct.
    Returns the no-result message if context is empty.
    """
    all_empty = all(len(v) == 0 for v in results_dict.values())
    if all_empty:
        return "Aucun résultat pertinent trouvé pour cette requête."

    context = format_context_for_llm(results_dict)

    messages = [
        {"role": "system", "content": SYSTEM_PROMPT},
        {"role": "user",   "content": f"Question : {query}\n\nExtraits :\n{context}"},
    ]

    try:
        client = InferenceClient(token=hf_token)
        response = client.chat_completion(
            model=GENERATION_MODEL,
            messages=messages,
            max_tokens=1024,
        )
        return response.choices[0].message.content
    except Exception as e:
        return f"Erreur lors de la synthèse : {e}"


# --- Citation key helpers ---

def _article_citation_key(r: dict) -> str:
    code = r.get("code_name", "Code")
    num  = r.get("num", r.get("id_legifrance", "?"))
    return f"{code}, art. {num}"


def _decision_citation_key(r: dict) -> str:
    juris = r.get("jurisdiction", "Cass.")
    date  = r.get("date_decision", "")
    num   = r.get("source_id", r.get("id_judilibre", ""))
    return f"{juris}, {date}, n° {num}"


def _circulaire_citation_key(r: dict) -> str:
    num  = r.get("numero", r.get("source_id", "?"))
    min_ = r.get("ministere", "")
    return f"Circ. n° {num}, {min_}"


def _reponse_citation_key(r: dict) -> str:
    num = r.get("numero_question", r.get("source_id", "?"))
    return f"Q. n° {num}"
