# Implementation Plan: Generateur de documents administratifs IA

**Branch**: `002-ai-doc-generator` | **Date**: 2026-02-06 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/002-ai-doc-generator/spec.md`

## Summary

Generateur de documents administratifs (arretes municipaux, autorisations) a partir de templates DOCX avec placeholders `{{variable}}`. Pipeline complet : chatbot IA Mistral pour collecter les donnees -> substitution dans le XML du DOCX -> generation du fichier final. Implementation **100% XanoScript natif** avec outil MCP integre au serveur Mistral de l'assistante Marianne.

**Changement cle** : Pipeline DOCX entierement inline (pas de function.run imbrique) avec pattern "two-copy" pour contourner les limitations ZIP de Xano.

## Technical Context

**Language/Version**: XanoScript (Xano native)
**Primary Dependencies**: Mistral AI (chat completions pour parsage), Xano ZIP operations, Xano Storage
**Storage**: PostgreSQL via Xano (4 nouvelles tables + 1 lexique existant)
**Testing**: Tests end-to-end manuels via Run & Debug + application test HTML
**Target Platform**: Xano Cloud (workspace 5 - MARiaNNE)
**Project Type**: Backend API + Outil MCP (integration chatbot + REST)
**Branch Xano**: `genere_template`
**Constraints**:
- `function.run` imbrique (2+ niveaux) provoque un blocage silencieux -> tout inline
- `zip.create_archive` est casse (fatal 500) -> pattern two-copy obligatoire
- `||` (OR) non supporte dans db.query where -> split queries + merge
- `object.entries` retourne `{key, value}` (pas `[key, value]`)
- Certains noms de cles (`action`, `action_type`) sont reserves dans les outils MCP

## Constitution Check

*GATE: Valide - Conforme aux principes constitutionnels marIAnne*

| Principe | Statut | Justification |
|----------|--------|---------------|
| I. Architecture donnees-centree | PASS | Toutes les tables incluent `communes_id`, queries scopees par commune |
| II. Integration IA/LLM contrainte | PASS | Mistral `mistral-small-latest` temperature 0.1, parsage uniquement (pas de generation libre) |
| III. Securite et autorisation | PASS | JWT `auth = "utilisateurs"` sur tous les endpoints, verification `gestionnaire` pour admin |
| IV. Contrat API WeWeb | PASS | Nommage `{numero}_{action}_{entite}_{VERBE}.xs`, groupes `doc_generator` et `admin_templates` |
| V. Observabilite et tracabilite | PASS | Table `LOG_generation_documents` pour audit complet, soft-delete sur templates |
| Ontologie computationnelle | PASS | Entites TemplateDocumentAdministratif, SessionGenerationDocument, DocumentGenere, CategorieTemplate modelisees dans Grafo |

## Project Structure

### Documentation (this feature)

```text
specs/002-ai-doc-generator/
├── plan.md              # Ce fichier
├── spec.md              # Specification fonctionnelle
└── tasks.md             # Taches d'implementation (toutes completees)
```

### Source Code (repository root)

```text
apis/
├── doc_generator/
│   ├── api_group.xs                                    # Groupe API
│   ├── 914_liste_templates_disponibles_GET.xs          # Lister templates
│   ├── 915_demarrer_generation_document_POST.xs        # Demarrer session
│   ├── 916_collecter_donnees_chatbot_POST.xs           # Collecter via Mistral
│   ├── 917_generer_document_final_POST.xs              # Pipeline DOCX
│   ├── 918_historique_documents_generes_GET.xs          # Historique pagine
│   └── 919_telecharger_document_genere_GET.xs          # Telecharger + audit
├── admin_templates/
│   ├── api_group.xs                                    # Groupe API admin
│   ├── 920_creer_template_POST.xs                      # Creer + auto-detect
│   ├── 921_maj_template_PUT.xs                         # Modifier + version++
│   ├── 922_archiver_template_DELETE.xs                 # Soft-delete
│   └── 923_valider_template_reglementaire_PATCH.xs     # Validation + audit

tools/
└── 19_genere_acte_administratif.xs   # Outil MCP (5 actions)

templates_docx/
├── arrete_voirie.docx                # Template arrete de voirie
├── arrete_police_maire.docx          # Template arrete police maire
├── permis_stationnement.docx         # Template permis de stationnement
└── templates_metadata.json           # Metadonnees placeholders (3 templates)
```

**Structure Decision** : 2 nouveaux groupes API (doc_generator + admin_templates), 1 outil MCP, 4 nouvelles tables, 3 templates DOCX. Tout le code est inline dans les endpoints/outil (pas de fonctions separees) pour eviter le bug function.run imbrique.

## Architecture

### Modele de Donnees

```
┌─────────────────────────────────────┐
│  templates_documents_administratifs │  (ID: 122)
│  ─────────────────────────────────  │
│  nom, description, categorie_id    │
│  communes_id (FK), is_global       │
│  fichier_docx (attachment)         │
│  placeholders (JSON array)         │
│  version, actif, valide_regl.      │
│  cree_par, valide_par              │
└─────────────┬───────────────────────┘
              │ 1:N
              ▼
┌─────────────────────────────────────┐
│    sessions_generation_documents    │  (ID: 123)
│  ─────────────────────────────────  │
│  template_id (FK), utilisateur_id  │
│  communes_id, statut               │
│  donnees_collectees (JSON)         │
│  document_id (FK)                  │
└─────────────┬───────────────────────┘
              │ 1:1
              ▼
┌─────────────────────────────────────┐
│         documents_generes           │  (ID: 124)
│  ─────────────────────────────────  │
│  template_id, utilisateur_id       │
│  session_id, communes_id           │
│  titre, donnees_substituees (JSON) │
│  statut, fichier_docx (attachment) │
└─────────────┬───────────────────────┘
              │ 1:N
              ▼
┌─────────────────────────────────────┐
│      LOG_generation_documents       │  (ID: 125)
│  ─────────────────────────────────  │
│  document_id, template_id          │
│  utilisateur_id, session_id        │
│  action_type, statut               │
│  placeholders_remplaces, duree_ms  │
└─────────────────────────────────────┘
```

### Pipeline DOCX (Two-Copy Pattern)

```
Template DOCX (stocke dans Xano)
    │
    ▼  api.request GET
Donnees binaires brutes
    │
    ├──► storage.create_file_resource("read_copy.docx")   ← pour LECTURE
    │         │
    │         ▼  zip.extract
    │    Fichiers extraits: [word/document.xml, ...]
    │         │
    │         ▼  storage.read_file_resource
    │    Contenu XML brut de document.xml
    │         │
    │         ▼  foreach object.entries + |replace:
    │    XML avec {{placeholders}} remplaces + XML-escaped
    │
    └──► storage.create_file_resource("output.zip")        ← pour ECRITURE
              │
              ▼  zip.delete_from_archive("word/document.xml")
              │
              ▼  storage.create_file_resource("document.xml", $xml_modifie)
              │
              ▼  zip.add_to_archive("word/document.xml")
              │
              ▼  storage.create_attachment(access="public")
              │
              ▼  db.add documents_generes {fichier_docx: $attachment}
         Fichier DOCX persiste et telechargeable
```

### Integration IA (Mistral)

```
Utilisateur ──► Marianne (Mistral) ──► MCP Tool: genere_acte_administratif
                                            │
                    ┌───────────────────────┼───────────────────────┐
                    │                       │                       │
              lister_templates         demarrer              collecter
              (2 queries +         (creer session,       (stocker reponse,
               merge)              retour 1ere Q)        prochaine Q)
                                                              │
                                        ┌─────────────────────┘
                                        │
                                   generer                telecharger
                                (pipeline DOCX         (retourner URL
                                 two-copy)              fichier)
```

## Key Design Decisions

| Decision | Choix | Alternative rejetee | Raison |
|----------|-------|---------------------|--------|
| Pipeline DOCX | Inline dans API/tool | Functions separees | `function.run` imbrique bloque silencieusement |
| Manipulation ZIP | Two-copy pattern | `zip.create_archive` | `zip.create_archive` crash fatal (500) |
| OR dans queries | Split + merge | `\|\|` dans where | `\|\|` imbrique non fiable dans XanoScript |
| object.entries | `{key, value}` objects | `[key, value]` arrays | Comportement XanoScript (different de JS) |
| Persistance fichier | `storage.create_attachment` | `storage.create_file_resource` | `create_file_resource` est ephemere, pas stocke en DB |
| Parsage reponses | Mistral small T=0.1 | Regex/hardcode | Flexibilite langage naturel (dates, nombres) |
| Administration | Endpoints separes (admin_templates) | Meme groupe | Separation des responsabilites, auth differente |
| Soft-delete templates | Flag `actif=false` | Suppression physique | Les documents generes referencent le template |
| Noms de cles MCP | `etape` / `log_type` | `action` / `action_type` | `action` est un mot reserve dans les outils MCP |

## XanoScript Workarounds

| Limitation | Workaround | Fichiers concernes |
|------------|------------|-------------------|
| `\|\|` (OR) non supporte dans where | 2 queries + `\|merge:` | 914, 915, tool 19 |
| `function.run` imbrique bloque | Tout inline dans l'endpoint | 917, tool 19 |
| `zip.create_archive` crash | Two-copy pattern (.docx read / .zip write) | 917, tool 19 |
| `object.entries` retourne objets | Utiliser `$e.key` / `$e.value` (pas `$e[0]` / `$e[1]`) | 917, tool 19 |
| `storage.create_file_resource` ephemere | `storage.create_attachment` pour persistance DB | 917, tool 19 |
| Cle `action` reservee dans outils MCP | Renommer en `etape` / `log_type` | tool 19, 923 |
| `db.edit` refuse variable pour data | Construire l'objet inline ou via `\|set:` chainee | 921 |
| `format_timestamp` (pas `date` filter) | `now\|format_timestamp:"d/m/Y"` en variable separee | 917 |
| Ternary dans inline objects crash | Conditional block + variable intermediaire | tool 19 |

## Phases de developpement

### Phase 0 : Modele de Donnees (Tables)

**Objectif** : Creer les 4 tables necessaires

| Tache | Type | Table ID | Agent |
|-------|------|----------|-------|
| 0.1 Creer templates_documents_administratifs | CREER | 122 | Xano Table Designer |
| 0.2 Creer sessions_generation_documents | CREER | 123 | Xano Table Designer |
| 0.3 Creer documents_generes | CREER | 124 | Xano Table Designer |
| 0.4 Creer LOG_generation_documents | CREER | 125 | Xano Table Designer |

**Dependances** : Aucune

### Phase 1 : Administration des Templates (APIs)

**Objectif** : CRUD pour les templates

| Tache | Type | API ID | Fichier | Agent |
|-------|------|--------|---------|-------|
| 1.1 Creer groupe admin_templates | CREER | 57 | `apis/admin_templates/api_group.xs` | Xano API Query Writer |
| 1.2 POST creer_template | CREER | 1065 | `920_creer_template_POST.xs` | Xano API Query Writer |
| 1.3 PUT maj_template | CREER | 1066 | `921_maj_template_PUT.xs` | Xano API Query Writer |
| 1.4 DELETE archiver_template | CREER | 1067 | `922_archiver_template_DELETE.xs` | Xano API Query Writer |
| 1.5 PATCH valider_template | CREER | 1070 | `923_valider_template_reglementaire_PATCH.xs` | Xano API Query Writer |

**Dependances** : Phase 0 complete

### Phase 2 : APIs Doc Generator

**Objectif** : Endpoints de generation de documents

| Tache | Type | API ID | Fichier | Agent |
|-------|------|--------|---------|-------|
| 2.1 Creer groupe doc_generator | CREER | 56 | `apis/doc_generator/api_group.xs` | Xano API Query Writer |
| 2.2 GET liste_templates_disponibles | CREER | 1062 | `914_liste_templates_disponibles_GET.xs` | Xano API Query Writer |
| 2.3 POST demarrer_generation_document | CREER | 1063 | `915_demarrer_generation_document_POST.xs` | Xano API Query Writer |
| 2.4 POST collecter_donnees_chatbot | CREER | 1064 | `916_collecter_donnees_chatbot_POST.xs` | Xano API Query Writer |
| 2.5 POST generer_document_final | CREER | 1071 | `917_generer_document_final_POST.xs` | Xano API Query Writer |
| 2.6 GET historique_documents_generes | CREER | 1068 | `918_historique_documents_generes_GET.xs` | Xano API Query Writer |
| 2.7 GET telecharger_document_genere | CREER | 1069 | `919_telecharger_document_genere_GET.xs` | Xano API Query Writer |

**Dependances** : Phase 0 complete

### Phase 3 : Outil MCP

**Objectif** : Outil chatbot integre a Mistral

| Tache | Type | Tool ID | Fichier | Agent |
|-------|------|---------|---------|-------|
| 3.1 Creer genere_acte_administratif | CREER | 24 | `tools/19_genere_acte_administratif.xs` | Xano AI Builder |

**Dependances** : Phases 0 et 2 completes (reutilise la meme logique inline)

### Phase 4 : Templates DOCX

**Objectif** : Creer et deployer les 3 templates

| Tache | Type | Fichier |
|-------|------|---------|
| 4.1 Creer arrete_voirie.docx | CREER | `templates_docx/arrete_voirie.docx` |
| 4.2 Creer arrete_police_maire.docx | CREER | `templates_docx/arrete_police_maire.docx` |
| 4.3 Creer permis_stationnement.docx | CREER | `templates_docx/permis_stationnement.docx` |
| 4.4 Creer templates_metadata.json | CREER | `templates_docx/templates_metadata.json` |

**Dependances** : Aucune (parallelisable)

### Phase 5 : Tests et Corrections de Bugs

**Objectif** : Validation end-to-end et correction des problemes decouverts

| Tache | Type | Description |
|-------|------|-------------|
| 5.1 Fix storage.create_attachment | BUGFIX | Remplacer create_file_resource par create_attachment pour persistance |
| 5.2 Fix object.entries format | BUGFIX | Corriger `$e[0]` -> `$e.key`, `$e[1]` -> `$e.value` |
| 5.3 Fix noms de cles MCP | BUGFIX | Renommer `action` -> `etape`, `action_type` -> `log_type` |
| 5.4 Test end-to-end | TEST | Pipeline complet chatbot -> DOCX via application test HTML |

**Dependances** : Phases 2, 3, 4 completes

### Phase 6 : Documentation

**Objectif** : Documentation retroactive et mise a jour des references

| Tache | Type | Description |
|-------|------|-------------|
| 6.1 Mise a jour troubleshooting.md | DOC | Ajouter 10+ problemes documentes (two-copy, object.entries, OR workaround, etc.) |
| 6.2 Mise a jour CLAUDE.md | DOC | Ajouter sections XanoScript learnings + Text Chunking Architecture |
| 6.3 Mise a jour Grafo + specs | DOC | Ontologie computationnelle + fichiers spec/plan/tasks |

**Dependances** : Phase 5 complete

## Risques identifies

| Risque | Impact | Mitigation |
|--------|--------|------------|
| Placeholders fragmentes dans Word | Substitution echouee | Templates generes programmatiquement, pas edites dans Word |
| zip.create_archive casse | Impossible de creer DOCX | Two-copy pattern (delete + add au lieu de create) |
| Mistral rejette dates formatees | UX degradee | Pre-validation regex future, documentation utilisateur |
| Donnees commune incompletes | Champs auto-fill vides | Fallback `?? ""`, alertes admin |
| Taille DOCX > limites Xano | Generation echouee | Templates legers (< 1MB), pas d'images |

## Metriques de succes

- [x] 3 templates DOCX deployes et operationnels
- [x] Pipeline chatbot complet fonctionnel (5 actions MCP)
- [x] 10 endpoints REST deployes et testes
- [x] Isolation commune effective sur tous les endpoints
- [x] Audit logging operationnel dans LOG_generation_documents
- [x] Documentation troubleshooting complete (10+ problemes documentes)

## Variables d'environnement requises

```
MISTRAL_API_KEY=<cle API Mistral AI>
```

Configurer dans Xano -> Settings -> Environment Variables pour la branche `genere_template`.
