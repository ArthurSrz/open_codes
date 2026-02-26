# Implementation Plan: Pipeline Sync Légifrance PISTE

**Branch**: `001-legalkit-vector-sync` | **Date**: 2026-01-24 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-legalkit-vector-sync/spec.md`

## Summary

Pipeline de synchronisation des codes juridiques français depuis l'API officielle PISTE (Légifrance) vers la base vectorielle Xano. Implémentation **100% XanoScript natif** sans dépendances externes, avec génération d'embeddings Mistral AI pour recherche sémantique par l'assistante Marianne.

**Changement clé** : Abandon des datasets HuggingFace (obsolètes depuis 6 mois) au profit de l'API PISTE directe pour garantir la fraîcheur des données juridiques.

## Technical Context

**Language/Version**: XanoScript (Xano native)
**Primary Dependencies**: API PISTE OAuth2, API Mistral AI embeddings
**Storage**: PostgreSQL via Xano (table REF_codes_legifrance + 2 nouvelles tables)
**Testing**: Tests unitaires XanoScript avec assertions `expect`
**Target Platform**: Xano Cloud (workspace existant x8ki-letl-twmt)
**Project Type**: Backend pipeline (tâche planifiée + APIs monitoring)
**Performance Goals**:
- Sync quotidienne complète < 4h (200k articles)
- Sync incrémentale < 30min
- Rate: 10 req/s PISTE, 5 req/s Mistral
**Constraints**:
- Rate limits PISTE et Mistral à respecter
- Token OAuth expire après 1h (refresh requis)
- Embeddings 1024-dim (800MB stockage estimé)
**Scale/Scope**: ~98 codes, ~200 000 articles, 5 codes prioritaires Phase 1 MVP

## Constitution Check

*GATE: Validé - Conforme aux principes constitutionnels marIAnne*

| Principe | Statut | Justification |
|----------|--------|---------------|
| I. Architecture données-centrée | ✅ | Table REF_codes_legifrance est une table de référence (`LEX_*` / `REF_*`), pas de scope commune requis |
| II. Intégration IA/LLM contrainte | ✅ | Embeddings Mistral 1024-dim, seuil similarité ≥0.8 respecté |
| III. Sécurité et autorisation | ✅ | APIs monitoring avec `auth = "utilisateurs"`, gestionnaire requis |
| IV. Contrat API WeWeb | ✅ | Endpoints suivent convention `{numero}_{action}_{entite}_{VERBE}.xs` |
| V. Observabilité et traçabilité | ✅ | Table LOG_sync_legifrance pour audit complet |
| Ontologie computationnelle | ✅ | Entité ArticleLegifrance déjà modélisée dans Grafo |

## Project Structure

### Documentation (this feature)

```text
specs/001-legalkit-vector-sync/
├── plan.md              # Ce fichier
├── spec.md              # Spécification fonctionnelle
├── research.md          # Recherche Phase 0 (PISTE vs HuggingFace)
├── data-model.md        # Schéma des tables
├── quickstart.md        # Guide démarrage rapide
├── contracts/
│   ├── piste-sync-api.yaml    # OpenAPI endpoints monitoring
│   └── functions-spec.md      # Spécification des fonctions
└── tasks.md             # Phase 2 output (à générer via /speckit.tasks)
```

### Source Code (repository root)

```text
tables/
├── 98_ref_codes_legifrance.xs      # ÉTENDRE (30 nouvelles colonnes)
├── 116_lex_codes_piste.xs          # CRÉER (référentiel codes)
└── 117_log_sync_legifrance.xs      # CRÉER (logs sync)

functions/
├── piste/
│   ├── piste_auth_token.xs         # OAuth2 PISTE
│   ├── piste_get_toc.xs            # Table des matières
│   ├── piste_get_article.xs        # Détail article
│   ├── piste_extraire_articles_toc.xs  # Parser TOC récursif
│   ├── piste_sync_code.xs          # Sync un code complet
│   └── piste_orchestrer_sync.xs    # Orchestrateur principal
└── utils/
    ├── hash_contenu_article.xs     # SHA256 pour détection changements
    └── parser_fullSectionsTitre.xs # Parser hiérarchie

tasks/
└── 8_sync_legifrance_quotidien.xs  # CRÉER (task planifiée 02:00 UTC)

apis/maintenance/
├── 920_sync_legifrance_lancer_POST.xs      # CRÉER
├── 921_sync_legifrance_statut_GET.xs       # CRÉER
└── 922_sync_legifrance_historique_GET.xs   # CRÉER
```

**Structure Decision**: Extension de l'architecture Xano existante avec minimum d'ajouts :
- 2 nouvelles tables (référentiel + logs)
- 1 extension de table existante
- 6 nouvelles fonctions (groupées dans `functions/piste/`)
- 1 nouvelle task
- 3 nouveaux endpoints API (groupe maintenance existant)

## Complexity Tracking

| Aspect | Choix | Alternative rejetée | Raison |
|--------|-------|---------------------|--------|
| Source données | API PISTE directe | HuggingFace datasets | Datasets HF obsolètes (6 mois) |
| Runtime | XanoScript natif | Python externe | Minimiser dépendances, pas de runtime externe |
| Stockage métadonnées | 38 champs complets | Champs minimaux | Valeur ajoutée pour recherche et affichage |

## Phases de développement

### Phase 1 : Schema (Tables)

**Objectif** : Préparer la structure de données

| Tâche | Type | Fichier | Agent |
|-------|------|---------|-------|
| 1.1 Étendre REF_codes_legifrance | MODIFIER | `tables/98_ref_codes_legifrance.xs` | Xano Table Designer |
| 1.2 Créer LEX_codes_piste | CRÉER | `tables/116_lex_codes_piste.xs` | Xano Table Designer |
| 1.3 Créer LOG_sync_legifrance | CRÉER | `tables/117_log_sync_legifrance.xs` | Xano Table Designer |

**Dépendances** : Aucune

### Phase 2 : Functions PISTE

**Objectif** : Implémenter la logique d'appel API PISTE

| Tâche | Type | Fichier | Agent |
|-------|------|---------|-------|
| 2.1 piste_auth_token | CRÉER | `functions/piste/piste_auth_token.xs` | Xano Function Writer |
| 2.2 piste_get_toc | CRÉER | `functions/piste/piste_get_toc.xs` | Xano Function Writer |
| 2.3 piste_get_article | CRÉER | `functions/piste/piste_get_article.xs` | Xano Function Writer |
| 2.4 piste_extraire_articles_toc | CRÉER | `functions/piste/piste_extraire_articles_toc.xs` | Xano Function Writer |
| 2.5 piste_sync_code | CRÉER | `functions/piste/piste_sync_code.xs` | Xano Function Writer |
| 2.6 piste_orchestrer_sync | CRÉER | `functions/piste/piste_orchestrer_sync.xs` | Xano Function Writer |

**Dépendances** : Phase 1 complète

### Phase 3 : Functions Support

**Objectif** : Utilitaires et intégration Mistral

| Tâche | Type | Fichier | Agent |
|-------|------|---------|-------|
| 3.1 hash_contenu_article | CRÉER | `functions/utils/hash_contenu_article.xs` | Xano Function Writer |
| 3.2 parser_fullSectionsTitre | CRÉER | `functions/utils/parser_fullSectionsTitre.xs` | Xano Function Writer |
| 3.3 mistral_generer_embedding | VÉRIFIER/CRÉER | `functions/mistral/mistral_generer_embedding.xs` | Xano Function Writer |

**Dépendances** : Aucune (parallélisable avec Phase 2)

### Phase 4 : Task & APIs

**Objectif** : Exposition et planification

| Tâche | Type | Fichier | Agent |
|-------|------|---------|-------|
| 4.1 Task sync quotidien | CRÉER | `tasks/8_sync_legifrance_quotidien.xs` | Xano Task Writer |
| 4.2 API lancer sync | CRÉER | `apis/maintenance/920_sync_legifrance_lancer_POST.xs` | Xano API Query Writer |
| 4.3 API statut sync | CRÉER | `apis/maintenance/921_sync_legifrance_statut_GET.xs` | Xano API Query Writer |
| 4.4 API historique sync | CRÉER | `apis/maintenance/922_sync_legifrance_historique_GET.xs` | Xano API Query Writer |

**Dépendances** : Phases 2 et 3 complètes

### Phase 5 : Données initiales & Tests

**Objectif** : Peupler et valider

| Tâche | Type | Agent |
|-------|------|-------|
| 5.1 Peupler LEX_codes_piste (5 codes prioritaires MVP) | DATA | Manuel via Xano |
| 5.2 Configurer variables d'environnement | CONFIG | Manuel via Xano |
| 5.3 Lancer première synchronisation | TEST | Xano Unit Test Writer |
| 5.4 Valider embeddings et recherche | TEST | Xano Unit Test Writer |

**Dépendances** : Phase 4 complète

## Variables d'environnement à configurer

```
PISTE_OAUTH_ID=dc06ede7-4a49-44e4-90d8-af342a5e1f36
PISTE_OAUTH_SECRET=2bfad70f-7cc3-4c60-84ec-1f1e6e69773e
MISTRAL_API_KEY=QMT34dF9pKDubwKTVQepNNsowm5CJ778
```

## Risques identifiés

| Risque | Impact | Mitigation |
|--------|--------|------------|
| Rate limit PISTE | Sync incomplète | Implémentation backoff exponentiel |
| Token PISTE expire (1h) | Erreurs 401 | Refresh automatique dans orchestrateur |
| Volume articles élevé | Timeout task | Traitement par lots de 50, checkpoint |
| Changements API PISTE | Breaking changes | Versioning endpoints, tests de régression |

## Métriques de succès

- [ ] 5 codes prioritaires synchronisés en < 24h
- [ ] 99.5% articles avec embeddings valides
- [ ] Sync incrémentale quotidienne < 30min
- [ ] Aucune perte de données lors des mises à jour
- [ ] Logs de sync accessibles via API

## Stratégie de chunking des articles longs

Pour les articles dépassant la limite de tokens Mistral (8 000 tokens), le système applique un **chunking hiérarchique intelligent** :

1. **Détection** : Si `length(fullSectionsTitre + surtitre + texte) > 8000 tokens`
2. **Découpage** : Utiliser les subdivisions naturelles du code :
   - Priorité 1 : Découper par paragraphe (si disponible dans la structure)
   - Priorité 2 : Découper par section/sous-section
   - Priorité 3 : Découper par phrases complètes avec overlap de 200 tokens
3. **Conservation du contexte** : Chaque fragment conserve `fullSectionsTitre` + `surtitre` comme préfixe
4. **Stockage** :
   - Option A : Créer des enregistrements multiples avec `id_legifrance` identique mais `ordre_fragment` différent
   - Option B : Stocker un seul embedding du texte tronqué (8000 premiers tokens) avec flag `texte_tronque=true`

**Décision implémentation** : Délégué à la tâche T009 (mistral_generer_embedding) - Option B recommandée pour MVP (simplicité), Option A pour production complète.
