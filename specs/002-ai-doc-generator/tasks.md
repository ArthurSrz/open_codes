# Tasks: Generateur de documents administratifs IA

**Input**: Design documents from `/specs/002-ai-doc-generator/`
**Prerequisites**: plan.md, spec.md
**Status**: TOUTES LES TACHES COMPLETEES

**Tests**: Tests end-to-end manuels via Run & Debug Xano + application test HTML.

**Organization**: Tasks grouped by phase for sequential implementation.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4)
- Include exact file paths in descriptions

## Path Conventions (Xano/XanoScript)

- **Tables**: Tables Xano (IDs 122-125)
- **APIs**: `apis/{group}/` at repository root
- **Tools**: `tools/` at repository root
- **Templates**: `templates_docx/` at repository root

---

## Phase 0: Modele de Donnees (Tables)

**Purpose**: Creer les 4 tables necessaires pour le generateur de documents

**CRITICAL**: Aucune API ne peut fonctionner sans ces tables

### Tables

- [x] T001 [P] Create table `templates_documents_administratifs` (ID: 122) - nom (text), description (text), categorie_id (int), communes_id (int FK), is_global (bool), fichier_docx (attachment), placeholders (JSON), version (int default 1), actif (bool default true), valide_reglementairement (bool default false), cree_par (int), valide_par (int), modifie_par (int), archive_par (int), date_validation (timestamp), commentaire_validation (text), archived_at (timestamp), created_at (timestamp), updated_at (timestamp)
- [x] T002 [P] Create table `sessions_generation_documents` (ID: 123) - template_id (int FK -> 122), utilisateur_id (int FK), communes_id (int FK), statut (enum: en_cours/termine), donnees_collectees (JSON), document_id (int FK -> 124 nullable), created_at (timestamp)
- [x] T003 [P] Create table `documents_generes` (ID: 124) - template_id (int FK -> 122), utilisateur_id (int FK), session_id (int FK -> 123), communes_id (int FK), titre (text), donnees_substituees (JSON), statut (enum: brouillon/finalise/signe), fichier_docx (attachment), created_at (timestamp)
- [x] T004 [P] Create table `LOG_generation_documents` (ID: 125) - document_id (int FK -> 124), template_id (int FK -> 122), utilisateur_id (int FK), session_id (int FK -> 123), action_type (text), statut (text), placeholders_remplaces (int), duree_ms (int), details (text), created_at (timestamp)

**Checkpoint**: Schema deploye - 4 tables creees dans Xano workspace 5, branche genere_template

---

## Phase 1: Administration des Templates (US3)

**Purpose**: Endpoints CRUD pour les gestionnaires de templates

**Goal**: Permettre aux gestionnaires de creer, modifier, archiver et valider les templates DOCX.

**Independent Test**: Creer un template via POST, verifier auto-detection des placeholders, modifier (version incrementee), valider, archiver (soft-delete).

### API Group

- [x] T005 Create API group `admin_templates` (ID: 57) in `apis/admin_templates/api_group.xs` - docs = "Administration des templates de documents administratifs"

### API Endpoints

- [x] T006 [P] [US3] Create API endpoint in `apis/admin_templates/920_creer_template_POST.xs` (ID: 1065) - auth=utilisateurs + gestionnaire, input: nom, description, categorie_id, fichier_docx (attachment), placeholders (JSON optional), is_global. Auto-detection des placeholders via regex si non fournis. db.add templates_documents_administratifs.
- [x] T007 [P] [US3] Create API endpoint in `apis/admin_templates/921_maj_template_PUT.xs` (ID: 1066) - auth=utilisateurs + gestionnaire, input: template_id, nom?, description?, categorie_id?, fichier_docx?, placeholders?. Incremente version, invalide valide_reglementairement. Verification acces commune.
- [x] T008 [P] [US3] Create API endpoint in `apis/admin_templates/922_archiver_template_DELETE.xs` (ID: 1067) - auth=utilisateurs + gestionnaire, input: template_id. Soft-delete: actif=false, archive_par, archived_at. Verification acces commune.
- [x] T009 [P] [US3] Create API endpoint in `apis/admin_templates/923_valider_template_reglementaire_PATCH.xs` (ID: 1070) - auth=utilisateurs + gestionnaire, input: template_id, commentaire_validation?. Set valide_reglementairement=true, valide_par, date_validation. Audit log dans LOG_generation_documents.

**Checkpoint**: Phase 1 complete - CRUD templates fonctionnel, auto-detection placeholders, soft-delete, validation reglementaire

---

## Phase 2: APIs Doc Generator (US1, US2, US4)

**Purpose**: Endpoints de generation de documents accessibles par le frontend WeWeb

**Goal**: Pipeline complet REST : lister templates -> demarrer session -> collecter donnees (avec Mistral) -> generer DOCX -> historique -> telecharger.

**Independent Test**: Appeler sequentiellement les 6 endpoints, verifier que le DOCX final contient les bonnes substitutions.

### API Group

- [x] T010 Create API group `doc_generator` (ID: 56, canonical: usIHn06x) in `apis/doc_generator/api_group.xs` - docs = "Generation de documents administratifs"

### API Endpoints

- [x] T011 [US2] Create API endpoint in `apis/doc_generator/914_liste_templates_disponibles_GET.xs` (ID: 1062) - auth=utilisateurs, input: categorie_id?. Split 2 queries (commune + global) + |merge: pour contourner || non supporte. Retourne templates actifs.
- [x] T012 [US1] Create API endpoint in `apis/doc_generator/915_demarrer_generation_document_POST.xs` (ID: 1063) - auth=utilisateurs, input: template_id. Verifier acces (commune ou global) via conditional + flag $has_access. Creer session, pre-remplir auto-fill (commune, maire, departement, tribunal, date). Retourner placeholders a collecter + premiere question.
- [x] T013 [US1] Create API endpoint in `apis/doc_generator/916_collecter_donnees_chatbot_POST.xs` (ID: 1064) - auth=utilisateurs, input: session_id, message_utilisateur, placeholder_id. Interpreter via Mistral (dates, nombres). Mettre a jour donnees_collectees dans session. Retourner prochaine question ou collecte_complete=true.
- [x] T014 [US2] Create API endpoint in `apis/doc_generator/917_generer_document_final_POST.xs` (ID: 1071) - auth=utilisateurs, input: session_id. Pipeline DOCX inline two-copy pattern. object.entries avec {key,value}. XML escaping. storage.create_attachment. db.add documents_generes + LOG_generation_documents. Chronometrage duree_ms.
- [x] T015 [P] [US4] Create API endpoint in `apis/doc_generator/918_historique_documents_generes_GET.xs` (ID: 1068) - auth=utilisateurs, input: page, per_page, statut?. db.query scopee communes_id, sort created_at desc, pagination.
- [x] T016 [P] [US4] Create API endpoint in `apis/doc_generator/919_telecharger_document_genere_GET.xs` (ID: 1069) - auth=utilisateurs, input: document_id. Verifier acces commune. Audit log telechargement. Retourner fichier_docx + metadonnees.

**Checkpoint**: Phase 2 complete - 6 endpoints deployes, pipeline DOCX fonctionnel, Mistral parsage operationnel

---

## Phase 3: Outil MCP (US1)

**Purpose**: Outil chatbot integre au serveur MCP de Marianne

**Goal**: Permettre a Mistral de guider l'utilisateur dans la generation de documents via 5 actions.

**Independent Test**: Via le chatbot Marianne, dire "Je veux faire un arrete de voirie" et verifier le flux complet (lister -> demarrer -> collecter N questions -> generer -> telecharger).

### MCP Tool

- [x] T017 [US1] Create MCP tool in `tools/19_genere_acte_administratif.xs` (ID: 24) - auth=utilisateurs, input: action (text), template_id?, session_id?, placeholder_id?, valeur?, document_id?. 5 actions: lister_templates (2 queries + merge), demarrer (creer session + premiere question), collecter (stocker donnee + prochaine question), generer (pipeline DOCX two-copy complet inline), telecharger (retourner URL). Chaque action retourne `instruction` pour guider Mistral. Workarounds: etape au lieu de action, {key,value} pour object.entries, password="" sur toutes les ops ZIP.

**Checkpoint**: Phase 3 complete - Outil MCP deploye avec 5 actions, testable via chatbot

---

## Phase 4: Templates DOCX (US1)

**Purpose**: Creer les 3 templates DOCX initiaux avec placeholders

**Goal**: Templates propres avec placeholders en single XML run, metadata complete, references legales CGCT.

### Templates

- [x] T018 [P] Create DOCX template `templates_docx/arrete_voirie.docx` - 19 placeholders (5 auto-fill: commune_nom, departement_nom, maire_nom, tribunal_administratif, date_signature + 14 manuels). References: L.2213-1, L.2213-6 CGCT, R.411-5 Code de la route.
- [x] T019 [P] Create DOCX template `templates_docx/arrete_police_maire.docx` - 14 placeholders (5 auto-fill + 9 manuels). References: L.2212-1, L.2212-2 CGCT, R.610-5 Code penal.
- [x] T020 [P] Create DOCX template `templates_docx/permis_stationnement.docx` - 18 placeholders (5 auto-fill + 13 manuels). References: L.2213-1, L.2213-6 CGCT, L.2122-1 CGPPP.
- [x] T021 [P] Create metadata file `templates_docx/templates_metadata.json` - JSON complet avec nom, categorie, description, references_legales, et metadonnees de chaque placeholder (id, label, type, required, auto_fill, source, question_chatbot, example, default, options).

**Checkpoint**: Phase 4 complete - 3 templates DOCX + metadata deployes

---

## Phase 5: Tests et Corrections de Bugs

**Purpose**: Validation end-to-end et correction des problemes decouverts pendant les tests

### Bug Fixes

- [x] T022 [BUGFIX] Fix storage.create_attachment - Remplacer `storage.create_file_resource` par `storage.create_attachment` dans API 1071 et tool 24 pour persister les fichiers generes en base de donnees. `create_file_resource` est ephemere et ne survit pas a la fin de la requete.
- [x] T023 [BUGFIX] Fix object.entries format - Corriger le code de substitution dans API 1071 et tool 24 : `$e[0]`/`$e[1]` -> `$e.key`/`$e.value`. XanoScript retourne des objets `{key, value}`, pas des tableaux `[key, value]`.
- [x] T024 [BUGFIX] Fix noms de cles MCP reservees - Renommer `action` -> `etape` et `action_type` -> `log_type` dans les objets resultat du tool 24 et dans les db.add LOG_generation_documents. Le mot `action` est reserve dans le contexte des outils MCP.

### End-to-End Test

- [x] T025 Test pipeline complet - Creer une application test HTML avec les 6 endpoints doc_generator. Verifier : liste templates, demarrage session avec auto-fill, collecte progressive avec Mistral, generation DOCX (verifier absence de `{{` residuels), telechargement, audit logs. Tester avec les 3 templates.

**Checkpoint**: Phase 5 complete - Tous les bugs resolus, pipeline valide end-to-end

---

## Phase 6: Documentation

**Purpose**: Documentation retroactive et mise a jour des references du projet

### Documentation Tasks

- [x] T026 Update `docs/troubleshooting.md` - Ajouter 10+ problemes documentes pour Feature 002 : DOCX placeholders fragmentes, XML special chars, two-copy pattern, object.entries format, OR workaround, MCP key names, storage.create_attachment, format_timestamp, db.edit variable data, Mistral date rejection.
- [x] T027 Update project CLAUDE.md - Ajouter sections : XanoScript troubleshooting (doc generator), Text Chunking Architecture, Critical XanoScript Learnings (function.run returns metadata, response wrapping, timestamp arithmetic, filter parentheses, non-existent filters, no early returns, reserved keywords).
- [x] T028 Update Grafo ontology + create specs - Mettre a jour l'ontologie computationnelle Grafo avec les entites TemplateDocumentAdministratif, SessionGenerationDocument, DocumentGenere, CategorieTemplate et relations (genereDepuis, generePar, contientPlaceholders, classeeDans, collecteDonneesPour, utiliseTemplate, produitDocument, demarre). Creer les fichiers specs/002-ai-doc-generator/ (spec.md, plan.md, tasks.md).

**Checkpoint**: Phase 6 complete - Documentation a jour, ontologie synchronisee

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 0 (Tables) ◄── BLOCKS ALL PHASES
    │
    ├──────────────┬──────────────┐
    ▼              ▼              ▼
Phase 1 (Admin)  Phase 2 (APIs)  Phase 4 (Templates)
  US3              US1/2/4          independent
    │              │
    └──────┬───────┘
           ▼
     Phase 3 (MCP Tool)
       US1 (reutilise logique inline)
           │
           ▼
     Phase 5 (Tests + Bugfix)
           │
           ▼
     Phase 6 (Documentation)
```

### Parallel Opportunities

**Phase 0 (Tables)**:
```
Task: T001 - templates_documents_administratifs
Task: T002 - sessions_generation_documents
Task: T003 - documents_generes
Task: T004 - LOG_generation_documents
→ All 4 can be created in parallel
```

**Phase 1 (Admin)**:
```
Task: T006 - creer_template
Task: T007 - maj_template
Task: T008 - archiver_template
Task: T009 - valider_template
→ All 4 can be created in parallel
```

**Phase 4 (Templates)**:
```
Task: T018 - arrete_voirie.docx
Task: T019 - arrete_police_maire.docx
Task: T020 - permis_stationnement.docx
Task: T021 - templates_metadata.json
→ All 4 can be created in parallel
→ Entire phase parallelizable with Phases 1 & 2
```

---

## Xano Resource IDs Reference

### Tables
| Table | ID | Description |
|-------|-----|-------------|
| templates_documents_administratifs | 122 | Templates DOCX avec placeholders |
| sessions_generation_documents | 123 | Sessions de generation en cours |
| documents_generes | 124 | Documents finaux generes |
| LOG_generation_documents | 125 | Journal d'audit |

### API Groups
| Groupe | ID | Canonical | Description |
|--------|-----|-----------|-------------|
| Doc Generator | 56 | usIHn06x | Endpoints de generation |
| Admin Templates | 57 | - | Administration des templates |

### API Endpoints
| API | ID | Groupe | Verbe | Description |
|-----|-----|--------|-------|-------------|
| liste_templates_disponibles | 1062 | 56 | GET | Lister templates (commune + global) |
| demarrer_generation_document | 1063 | 56 | POST | Creer session de generation |
| collecter_donnees_chatbot | 1064 | 56 | POST | Collecter reponse via Mistral |
| creer_template | 1065 | 57 | POST | Creer template + auto-detect |
| maj_template | 1066 | 57 | PUT | Modifier template + version++ |
| archiver_template | 1067 | 57 | DELETE | Soft-delete template |
| historique_documents_generes | 1068 | 56 | GET | Historique pagine |
| telecharger_document_genere | 1069 | 56 | GET | Telecharger + audit |
| valider_template_reglementaire | 1070 | 57 | PATCH | Validation reglementaire |
| generer_document_final | 1071 | 56 | POST | Pipeline DOCX complet |

### MCP Tool
| Tool | ID | Description |
|------|-----|-------------|
| genere_acte_administratif | 24 | 5 actions chatbot |

---

## Summary

| Phase | Tasks | Parallel | Story | Status |
|-------|-------|----------|-------|--------|
| Phase 0: Tables | 4 | 4 | - | COMPLETE |
| Phase 1: Admin Templates | 5 | 4 | US3 | COMPLETE |
| Phase 2: APIs Doc Generator | 7 | 2 | US1/2/4 | COMPLETE |
| Phase 3: MCP Tool | 1 | 0 | US1 | COMPLETE |
| Phase 4: Templates DOCX | 4 | 4 | US1 | COMPLETE |
| Phase 5: Tests + Bugfix | 4 | 0 | - | COMPLETE |
| Phase 6: Documentation | 3 | 0 | - | COMPLETE |
| **Total** | **28** | **14** | - | **COMPLETE** |

---

## Notes

- [P] tasks = different files, no dependencies within phase
- XanoScript specifics: tout inline (pas de function.run imbrique), two-copy pattern pour DOCX, split queries pour OR
- Agent delegation: Xano Table Designer for tables, Xano API Query Writer for endpoints, Xano AI Builder for MCP tool
- Tous les workarounds XanoScript documentes dans `docs/troubleshooting.md`
- Branche Xano: `genere_template` (workspace 5)
