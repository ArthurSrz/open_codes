# Tasks: enirtcod.fr Open Legal Search Space

**Input**: Design documents from `/specs/006-enirtcod-space/`
**Prerequisites**: plan.md ✅, spec.md ✅

**Organization**: US1 (search) and US2 (synthesis) are both P1 and tightly coupled — implemented together as the MVP. US3 (filters) and US4 (cross-references) are independent increments.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to

---

## Phase 1: Setup (Project Scaffolding)

**Purpose**: Create the `spaces/enirtcod/` directory and all boilerplate files

- [ ] T001 Create `spaces/enirtcod/` directory structure with empty placeholder files: `app.py`, `search.py`, `synthesis.py`, `ui_components.py`, `data_loader.py`
- [ ] T002 [P] Write `spaces/enirtcod/requirements.txt` with pinned dependencies: `gradio>=4.44.0`, `datasets>=2.14.0`, `huggingface_hub>=0.20.0`, `faiss-cpu>=1.7.4`, `mistralai>=1.0.0`, `numpy>=1.24.0`
- [ ] T003 [P] Write `spaces/enirtcod/README.md` HuggingFace Space card with YAML header: `title: enirtcod`, `emoji: ⚖️`, `colorFrom: blue`, `colorTo: indigo`, `sdk: gradio`, `sdk_version: "4.44.0"`, `app_file: app.py`, `pinned: true`, `license: apache-2.0`; include brief description of the project as open-source alternative to Doctrine.fr

**Checkpoint**: Directory structure and static files exist — implementation can begin

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Dataset loading and FAISS index construction — all user stories depend on this

**⚠️ CRITICAL**: No search or synthesis can work until datasets are loaded and indexed

- [ ] T004 Implement `spaces/enirtcod/data_loader.py` with function `load_all_datasets()` that loads all four configs from `ArthurSrz/open_codes` (`default`, `jurisprudence`, `circulaires`, `reponses_legis`) using `load_dataset(..., split="train")`, calls `ds.add_faiss_index(column="embedding")` on each, and returns a dict `{"articles": ds, "jurisprudence": ds, "circulaires": ds, "reponses": ds}`; implement graceful degradation: wrap each dataset load in try/except, log failures, continue with available datasets; add `LOADING_STATUS` dict tracking which sources loaded successfully
- [ ] T005 Add `embed_query(query_text: str, hf_token: str) -> list[float]` function in `spaces/enirtcod/data_loader.py` that calls HuggingFace Inference API (`InferenceClient`) with model `mistral-embed` and returns a 1024-dim float list; handle API errors by raising a user-readable exception

**Checkpoint**: `load_all_datasets()` and `embed_query()` can be called independently in a Python REPL

---

## Phase 3: User Stories 1 & 2 — Unified Search + LLM Synthesis (Priority: P1) 🎯 MVP

**Goal**: Users can type a French legal question, see ranked result cards from all 4 source types in tabs, and read a synthesized prose answer with inline citations

**Independent Test**: Typing "responsabilité civile délictuelle" into the search bar returns result cards in at least 2 source type tabs AND a synthesis panel with at least one inline citation in French legal style within 10 seconds (after first cold start)

### Implementation for User Stories 1 & 2

- [ ] T006 [US1] Implement `search_source(ds, query_embedding, k, source_type) -> list[dict]` in `spaces/enirtcod/search.py`: call `ds.get_nearest_examples("embedding", np.array(query_embedding), k=k*5)` to retrieve candidates, build result dicts with fields: `source_type`, `chunk_text`, `chunk_index`, `score`, and all source-specific metadata (for articles: `code_name`, `num`, `id_legifrance`, `article_etat`, `article_dateDebut`; for jurisprudence: `jurisdiction`, `chamber`, `date_decision`, `solution`, `fiche_arret`, `url_judilibre`; for circulaires: `numero`, `date_parution`, `ministere`, `objet`, `url_legifrance`; for reponses: `numero_question`, `date_reponse`, `ministere`, `question_text`, `url_legifrance`), return top `k` results
- [ ] T007 [US1] Implement `search_all(query_embedding, datasets_dict, source_filter="Tous") -> dict` in `spaces/enirtcod/search.py`: call `search_source()` for each loaded dataset (articles k=3, jurisprudence k=3, circulaires k=2, reponses k=1); respect `source_filter` param to restrict to one source type when not "Tous"; return `{"articles": [...], "jurisprudence": [...], "circulaires": [...], "reponses": [...]}`
- [ ] T008 [US2] Implement `format_context_for_llm(results_dict) -> str` in `spaces/enirtcod/synthesis.py`: build a numbered context string from all retrieved chunks; for each chunk include source type prefix, snippet (first 500 chars), and citation key (article num + code, decision date + number, circulaire number, or Q number)
- [ ] T009 [US2] Implement `synthesize(query, results_dict, hf_token) -> str` in `spaces/enirtcod/synthesis.py`: build messages list with SYSTEM_PROMPT (cite only from context, use French legal citation style `[Code civil, art. 1240]` for articles, `[Cass. 1re civ., 13 avr. 2023, n° 21-20.145]` for decisions, `[Circ. n° 2023-045, ministère XY]` for circulaires) and user message with query + formatted context; call `InferenceClient(model="mistralai/Mistral-7B-Instruct-v0.3").chat_completion(messages)`; if results_dict is empty or all lists empty, return `"Aucun résultat pertinent trouvé pour cette requête."`
- [ ] T010 [P] [US1] Implement `build_article_card(result) -> str` in `spaces/enirtcod/ui_components.py`: return HTML string for an article result card with: badge `[{code_name}]`, article number and snippet (first 200 chars of chunk_text), date from `article_dateDebut` (formatted), link to `https://www.legifrance.gouv.fr/codes/article_lc/{id_legifrance}`; include `data-article-id` attribute for cross-reference hook
- [ ] T011 [P] [US1] Implement `build_decision_card(result) -> str` in `spaces/enirtcod/ui_components.py`: badge `[{jurisdiction} | {chamber}]`, date + decision number, fiche_arret snippet (if present) OR chunk_text snippet (first 200 chars), link to `url_judilibre`
- [ ] T012 [P] [US1] Implement `build_circulaire_card(result) -> str` in `spaces/enirtcod/ui_components.py`: badge `[Ministère: {ministere}]`, circulaire number + objet snippet (first 200 chars), date, link to `url_legifrance`
- [ ] T013 [P] [US1] Implement `build_reponse_card(result) -> str` in `spaces/enirtcod/ui_components.py`: badge `[{ministere}]`, question number + question_text snippet (first 200 chars), date, link to `url_legifrance`
- [ ] T014 [US1] Implement `build_tabs_html(results_dict) -> str` in `spaces/enirtcod/ui_components.py`: build HTML for 4-tab panel (`Articles (N) | Jurisprudence (N) | Circulaires (N) | Q&R (N)`) calling the appropriate card builder per source type; if a source failed to load, show `"Source temporairement indisponible"` for that tab
- [ ] T015 [US1] [US2] Implement the main Gradio app in `spaces/enirtcod/app.py`: call `load_all_datasets()` at module level with a loading status message; define `gr.Blocks()` layout with: search bar (`gr.Textbox`), source selector (`gr.Dropdown(["Tous", "Articles", "Jurisprudence", "Circulaires", "Q&R"])`), Rechercher button, `gr.HTML` panel for synthesis output, `gr.HTML` panel for tabbed results; wire `btn.click` to `run_search(query, source_filter)` which calls `embed_query` → `search_all` → `synthesize` → `build_tabs_html` and returns both synthesis text and tabs HTML; add loading spinner message "Chargement des sources juridiques…" during startup

**Checkpoint**: US1+US2 MVP — full search+synthesis cycle works end-to-end. Deploy to HF Space and validate with "responsabilité civile délictuelle" query.

---

## Phase 4: User Story 3 — Filter Panel (Priority: P2)

**Goal**: Users can filter results by date range, jurisdiction, legal code, and ministry

**Independent Test**: Setting date range to 2020–2025 and submitting the same query reduces result counts in all tabs to only items dated within that range; setting jurisdiction filter to "Cour de cassation" reduces Jurisprudence tab to only that court's decisions

### Implementation for User Story 3

- [ ] T016 [US3] Add `apply_filters(results, filters_dict) -> list[dict]` in `spaces/enirtcod/search.py`: apply date range filter (`date_from`, `date_to` as int years) to all source types; apply `jurisdiction` filter only to jurisprudence results; apply `code_name` filter only to articles results; apply `ministere` filter only to circulaires and reponses results; return filtered list
- [ ] T017 [US3] Integrate filters into `search_all()` in `spaces/enirtcod/search.py`: accept `filters_dict` param and call `apply_filters(results, filters_dict)` on each source's results before returning
- [ ] T018 [US3] Add filter panel components to `spaces/enirtcod/app.py`: add collapsible `gr.Accordion("Filtres")` containing `gr.Slider` for year range (min=2000, max=2026), `gr.Dropdown` for jurisdiction (["Tous", "Cour de cassation", "Cour d'appel"]), `gr.Dropdown` for legal code (dynamically populated from articles dataset unique `code_name` values at startup), `gr.Dropdown` for ministry (dynamically populated from circulaires unique `ministere` values at startup)
- [ ] T019 [US3] Wire filter components into `run_search()` in `spaces/enirtcod/app.py`: read filter values from Gradio state and pass as `filters_dict` to `search_all()`; ensure filters are reset to defaults when search bar is cleared

**Checkpoint**: US3 complete — filter panel works independently; applying jurisdiction filter visibly changes Jurisprudence tab count

---

## Phase 5: User Story 4 — Cross-References (Priority: P3)

**Goal**: Article result cards show "Voir les décisions (N)" button revealing related decisions

**Independent Test**: An article card for Code civil art. 1240 shows "Voir les décisions (N)" with N > 0 and clicking it reveals up to 3 decision card snippets in a sub-panel

### Implementation for User Story 4

- [ ] T020 [US4] Implement `find_related_decisions(article_id_legifrance, juris_ds) -> list[dict]` in `spaces/enirtcod/search.py`: filter `juris_ds` to rows where `article_id_legifrance` appears in `chunk_text` (string contains check); return up to 3 matching rows with fields: `jurisdiction`, `date_decision`, `solution`, `url_judilibre`, `chunk_text` snippet
- [ ] T021 [US4] Update `build_article_card(result, related_decisions=[]) -> str` in `spaces/enirtcod/ui_components.py`: if `related_decisions` is non-empty, append a `"Voir les décisions (N)"` expandable HTML section after the card snippet showing up to 3 mini decision cards (jurisdiction badge, date, link); if empty, no cross-reference section appears
- [ ] T022 [US4] Integrate cross-reference lookup into `run_search()` in `spaces/enirtcod/app.py`: after retrieving article results, call `find_related_decisions(result["id_legifrance"], datasets["jurisprudence"])` for each article result and pass `related_decisions` list to `build_article_card()`

**Checkpoint**: US4 complete — article cards show "Voir les décisions (N)" when N > 0; clicking reveals related decisions in sub-panel

---

## Phase 6: Polish & Deployment

- [ ] T023 [P] Validate all official source URLs in a representative sample of result cards manually: verify legifrance.gouv.fr article links and courdecassation.fr decision links open correctly in a browser
- [ ] T024 [P] Add empty-query guard in `run_search()` in `spaces/enirtcod/app.py`: if `query.strip() == ""`, return `gr.update(value="Veuillez entrer une question juridique.")` for synthesis and empty HTML for results without calling embed or search
- [ ] T025 [P] Add query length guard in `spaces/enirtcod/search.py`: if `len(query) > 500`, truncate to 500 chars before embedding and add warning note to synthesis output
- [ ] T026 Deploy `spaces/enirtcod/` to `ArthurSrz/enirtcod` HuggingFace Space by pushing all files via `huggingface_hub.upload_folder(folder_path="spaces/enirtcod", repo_id="ArthurSrz/enirtcod", repo_type="space")`
- [ ] T027 Verify cold start time: trigger a cold start on the deployed HF Space and measure time from page load to first search returning results; must complete within 90 seconds
- [ ] T028 Configure enirtcod.fr custom domain in HuggingFace Space settings

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — `data_loader.py` file must exist
- **Phase 3 (US1+US2)**: Depends on Phase 2 — FAISS indexes must be built before search
- **Phase 4 (US3)**: Depends on Phase 3 — filter logic plugs into existing `search_all()` and `run_search()`
- **Phase 5 (US4)**: Depends on Phase 3 — cross-reference logic requires `juris_ds` from data_loader and `build_article_card()` from ui_components
- **Phase 6 (Polish)**: Depends on all prior phases

### User Story Dependencies

- **US1+US2 (P1)**: Depend only on Phase 2 (data_loader) — the true MVP
- **US3 (P2)**: Depends on US1+US2 complete — filter panel wraps existing search
- **US4 (P3)**: Depends on US1 complete — cross-reference extends article cards

### Parallel Opportunities

- T002, T003 (requirements.txt, README.md) can run in parallel with each other
- T010, T011, T012, T013 (4 card builders) can run in parallel — different functions in same file
- T023, T024, T025 (polish tasks) can run in parallel

---

## Parallel Example: Phase 3 Card Builders

```
After T009 (synthesis) is done:
  Thread A: T010 build_article_card() in ui_components.py
  Thread B: T011 build_decision_card() in ui_components.py
  Thread C: T012 build_circulaire_card() in ui_components.py
  Thread D: T013 build_reponse_card() in ui_components.py

Then: T014 build_tabs_html() (depends on all four card builders)
Then: T015 app.py (depends on T014 + T009)
```

---

## Implementation Strategy

### MVP First (US1 + US2 only)

1. Phase 1: Scaffold project (T001–T003)
2. Phase 2: Data loader + embedder (T004–T005)
3. Phase 3 partial: T006 → T007 → T008 → T009 → T010–T013 (parallel) → T014 → T015
4. **STOP and VALIDATE**: Deploy to HF Space, run "responsabilité civile délictuelle" query manually
5. Verify: results appear in ≥2 tabs, synthesis has inline citation, links open correctly

### Incremental Delivery

1. Phase 1+2 → Foundation ready (datasets loaded, FAISS built)
2. Phase 3 → **MVP live**: search + synthesis working end-to-end → Deploy and demo
3. Phase 4 → Filters added → re-deploy
4. Phase 5 → Cross-references added → re-deploy
5. Phase 6 → Custom domain configured → production ready

---

## Notes

- `load_all_datasets()` runs at module import time in `app.py` — Gradio executes this during Space startup
- Cold start budget is 90s; FAISS index build time scales with dataset size (~400MB estimated total)
- `gr.Blocks()` allows custom HTML for result cards — use `gr.HTML` components, not `gr.Markdown`
- HF Inference API calls for embedding + generation require `HF_TOKEN` secret set in Space settings
- Synthesis prompt must include explicit "cite only from context" instruction to prevent hallucination
- Cross-reference string match (`article_id_legifrance in chunk_text`) is O(N) — precompute at startup if dataset is large
