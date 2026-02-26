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

# enirtcod.fr — Recherche juridique française ouverte

**enirtcod** (« doctrine » à l'envers) est une alternative open-source à Doctrine.fr.

Interrogez en une seule recherche :
- 📖 **Articles de loi** — tous les codes français (Code civil, Code du travail, etc.)
- ⚖️ **Jurisprudence** — décisions de la Cour de cassation (Judilibre)
- 📋 **Circulaires** — instructions ministérielles officielles
- 💬 **Réponses ministérielles** — questions-réponses parlementaires

## Fonctionnalités

- **Recherche sémantique 4 sources** via FAISS + embeddings Mistral
- **Synthèse LLM** avec citations juridiques françaises (`[Code civil, art. 1240]`, `[Cass. 1re civ., 13 avr. 2023, n° 21-20.145]`)
- **Filtres** par date, juridiction, code, ministère
- **Renvois croisés** : décisions citant un article

## Données

Dataset : [`ArthurSrz/open_codes`](https://huggingface.co/datasets/ArthurSrz/open_codes) — licence Etalab 2.0

## Stack technique

- Gradio 4.x · FAISS · Mistral AI (`mistral-embed` + `Mistral-7B-Instruct`) · HuggingFace Inference API
