---
title: enirtcod
emoji: ⚖️
colorFrom: blue
colorTo: indigo
sdk: gradio
sdk_version: "4.44.0"
app_file: app.py
pinned: true
license: apache-2.0
---

# enirtcod.fr

**Alternative open-source à Doctrine.fr** — recherche sémantique unifiée dans le droit français, avec synthèse par LLM et citations juridiques structurées.

> *enirtcod = « doctrine » à l'envers.*

---

## Ce que ça fait

Posez une question juridique en français. En retour, vous obtenez :

1. **Des résultats classés par source** — articles de loi, décisions de justice, circulaires, réponses ministérielles — dans des onglets distincts avec compteurs
2. **Une synthèse prose** générée par Mistral 7B, citée en style juridique français : `[Code civil, art. 1240]`, `[Cass. 1re civ., 13 avr. 2023, n° 21-20.145]`, `[Circ. n° 2023-045, ministère du Travail]`
3. **Des renvois croisés** — chaque fiche d'article affiche les décisions judiciaires qui le citent

---

## Sources interrogées

| Source | Origine | Contenu |
|--------|---------|---------|
| 📖 Articles de loi | Légifrance (PISTE) | Tous les codes français en vigueur |
| ⚖️ Jurisprudence | Judilibre (Cour de cassation) | Décisions + fiches d'arrêt officielles |
| 📋 Circulaires | PISTE fond CIRC | Instructions ministérielles |
| 💬 Réponses ministérielles | PISTE fond QR | Questions-réponses parlementaires |

Toutes les sources sont sous **licence Etalab 2.0** (open data, librement redistribuables).

---

## Architecture

```
Question utilisateur (français)
    │
    ├─ Embedding : mistral-embed (1024 dim, HF Inference API)
    │
    ├─ FAISS sur ArthurSrz/open_codes / default        → 3 articles
    ├─ FAISS sur ArthurSrz/open_codes / jurisprudence  → 3 décisions
    ├─ FAISS sur ArthurSrz/open_codes / circulaires    → 2 circulaires
    └─ FAISS sur ArthurSrz/open_codes / reponses_legis → 1 réponse
              │
              ▼
    Mistral-7B-Instruct (HF Inference API)
    Prompt : citer uniquement les extraits fournis, style juridique français
              │
              ▼
    Synthèse + fiches résultats + renvois croisés
```

---

## Filtres disponibles

- **Date** — plage d'années (2000–2026)
- **Juridiction** — Cour de cassation, Cour d'appel
- **Code juridique** — filtré dynamiquement depuis le dataset
- **Ministère** — filtré dynamiquement depuis circulaires et réponses

---

## Démarrage à froid

Les index FAISS (~400 Mo) sont construits en mémoire au lancement du Space. Première réponse disponible **sous 90 secondes** sur le tier gratuit HuggingFace (16 Go RAM). Un message de chargement s'affiche pendant ce temps.

---

## Dataset

[`ArthurSrz/open_codes`](https://huggingface.co/datasets/ArthurSrz/open_codes) — mis à jour chaque nuit depuis les API officielles PISTE et Judilibre.

## Stack

`Gradio 4.x` · `datasets` (FAISS intégré) · `mistralai` · `huggingface_hub` · `numpy`
