# Feature Specification: enirtcod.fr — Open Legal Search Space

**Feature Branch**: `006-enirtcod-space`
**Created**: 2026-02-25
**Status**: Draft
**Input**: User description: "enirtcod.fr — open-source alternative to Doctrine.fr, a Gradio HuggingFace Space querying all four configs of ArthurSrz/open_codes using 4-way semantic search + Mistral 7B synthesis with inline citations. Doctrine.fr basic parity MVP. HuggingFace free tier, cold start under 90s. Out of scope: user accounts, saved searches, alerts, paid features."

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Unified Semantic Search Across All Legal Sources (Priority: P1)

As a French legal practitioner or researcher, I want to type a legal question in plain French and receive ranked result cards from all four legal source types (articles, decisions, circulaires, Q&R) in a single search so that I no longer need to query Legifrance, Judilibre, and ministerial portals separately.

**Why this priority**: This is the core value proposition. Without unified search, enirtcod.fr is no better than visiting four separate government portals. It must work end-to-end before any other feature is worth building.

**Independent Test**: Typing "responsabilité civile délictuelle" into the search bar returns at least one result card per source type (Articles, Jurisprudence, Circulaires, Q&R), each showing a snippet (~200 chars), a source badge, a date, and a clickable link to the official source.

**Acceptance Scenarios**:

1. **Given** the application is loaded, **When** a user types "responsabilité civile délictuelle" and submits, **Then** results appear within 10 seconds organized in tabs labeled "Articles (N) | Jurisprudence (N) | Circulaires (N) | Q&R (N)" with N > 0 for at least two tabs
2. **Given** search results are displayed, **When** a user clicks a source link on any result card, **Then** the link opens the official source (legifrance.gouv.fr or courdecassation.fr) in a new tab
3. **Given** a very specific legal question, **When** the system finds fewer than 3 results for a given source type, **Then** that tab is still shown but labeled with its actual count (e.g., "Circulaires (1)"), not hidden
4. **Given** the "Tous" (All sources) tab is selected in the source selector, **When** results are returned, **Then** cards from all four source types are interleaved and ranked by relevance score

---

### User Story 2 — LLM-Synthesized Answer with Inline Citations (Priority: P1)

As a legal researcher, I want to receive a synthesized prose answer to my legal question with inline citations in French legal citation style (e.g., "[Code civil, art. 1240]" and "[Cass. 1re civ., 13 avr. 2023, n° 21-20.145]") so that I can understand the applicable legal framework at a glance without reading through each result card individually.

**Why this priority**: The synthesis panel is what differentiates enirtcod.fr from a simple search engine — it's the Doctrine.fr core feature. It is equally critical as search (P1) because without synthesis, the product does not achieve doctrine.fr parity.

**Independent Test**: After any search, a "Synthèse" panel appears below the results with 2–5 prose sentences that directly answer the query, containing at least one citation linking to an article and at least one citation linking to a jurisprudence result from the retrieved context.

**Acceptance Scenarios**:

1. **Given** search results have been retrieved, **When** the synthesis panel renders, **Then** it contains at least 2 sentences of prose in French that are relevant to the query topic
2. **Given** the synthesis contains a legal code citation, **When** the user reads it, **Then** the citation follows French style: "[Code civil, art. 1240]" or "[C. trav., art. L.1237-19]"
3. **Given** the synthesis contains a case law citation, **When** the user reads it, **Then** the citation follows French judicial style: "[Cass. com., 26 mai 2006, n° 03-19.376]" or "[CA Paris, 15 janv. 2024]"
4. **Given** no relevant results are found for a query, **When** the synthesis renders, **Then** it displays "Aucun résultat pertinent trouvé pour cette requête." rather than hallucinating legal content

---

### User Story 3 — Filter Panel by Date, Jurisdiction, and Source (Priority: P2)

As a legal practitioner researching a specific legal area, I want to filter results by date range, jurisdiction (Court of Cassation / Cour d'appel), legal code, and ministry so that I can narrow down results to the most relevant time period and authority.

**Why this priority**: Filters dramatically improve result quality for professional users. Without them, results for broad queries like "contrat de travail" return hundreds of cards across all periods. Filters are standard in Doctrine.fr and required for professional parity.

**Independent Test**: Using the date range filter set to "2020–2025" and jurisdiction filter set to "Cour de cassation" reduces the Jurisprudence tab results to only decisions from 2020–2025 by the Cour de cassation, while Articles and Circulaires tabs are unaffected by the jurisdiction filter.

**Acceptance Scenarios**:

1. **Given** search results include decisions from multiple years, **When** a user sets the date range to 2022–2024, **Then** only results dated within that range appear in all source type tabs
2. **Given** the jurisdiction filter is set to "Cour de cassation", **When** results refresh, **Then** the Jurisprudence tab shows only Cour de cassation decisions, while other tabs are unchanged
3. **Given** a code filter is set to "Code civil", **When** results refresh, **Then** only article chunks from the Code civil appear in the Articles tab
4. **Given** a ministry filter is applied, **When** results refresh, **Then** only circulaires and Q&R from that ministry appear in their respective tabs

---

### User Story 4 — Cross-References: Decisions Citing an Article (Priority: P3)

As a legal researcher viewing an article result card, I want to see how many Court of Cassation decisions cite that specific article so that I can understand the article's judicial interpretation without running a separate search.

**Why this priority**: Cross-references are the "killer feature" that separates enirtcod from a simple keyword search. They are a Doctrine.fr differentiator. However, they require US1–US3 to be complete first, and are sufficiently complex that they can be added incrementally after the core experience is stable.

**Independent Test**: Clicking "Voir les décisions (N)" on an article result card expands a sub-panel showing up to 3 decision snippets that reference the article's identifier, each with jurisdiction, date, and a link to courdecassation.fr.

**Acceptance Scenarios**:

1. **Given** an article result card is displayed, **When** the article has at least one related decision in the jurisprudence config, **Then** the card shows a "Voir les décisions (N)" button with N > 0
2. **Given** a user clicks "Voir les décisions (N)", **When** the sub-panel expands, **Then** up to 3 decision snippets appear with jurisdiction badge, date, and official link
3. **Given** an article has no related decisions in the dataset, **When** the result card renders, **Then** no cross-reference button appears (clean card with no empty state)

---

### Edge Cases

- **Empty query submission**: Submitting an empty search bar displays an inline validation message "Veuillez entrer une question juridique" without triggering a search.
- **All source types return zero results**: If all four configs return no results for a query, display "Aucun résultat trouvé pour cette requête." with a suggestion to try broader terms, and the synthesis panel shows the no-result message.
- **One source type unavailable**: If the jurisprudence dataset fails to load at startup, the other three configs continue to work; the Jurisprudence tab shows "Source temporairement indisponible" instead of results.
- **Very long query**: Queries exceeding 500 characters are truncated before embedding, and a warning note is appended to the results.
- **Cold start latency**: On first load, dataset FAISS indexes are built in memory. Users see a loading spinner with message "Chargement des sources juridiques… (peut prendre jusqu'à 90 secondes)" rather than a blank screen.
- **Synthesis hallucination guard**: The LLM synthesis prompt explicitly instructs the model to cite only from the retrieved context chunks; if context is empty, the synthesis must fall back to the no-result message.

---

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Users MUST be able to enter a French legal question in a search bar and receive results from all four legal source types in under 10 seconds (after cold start)
- **FR-002**: Results MUST be organized in tabbed panels per source type: Articles, Jurisprudence, Circulaires, Q&R — each tab shows the count of results
- **FR-003**: Each result card MUST display: title or article number, a snippet (~200 chars), date, source badge (code name / jurisdiction / ministry), and a clickable link to the official source
- **FR-004**: Official source links MUST open in a new browser tab and point to legifrance.gouv.fr for articles/circulaires/Q&R and courdecassation.fr for decisions
- **FR-005**: System MUST generate a prose synthesis in French with inline citations drawn exclusively from the retrieved result context (no external knowledge beyond retrieved chunks)
- **FR-006**: Citations in the synthesis MUST follow French legal style for articles (e.g., "[Code civil, art. 1240]") and for decisions (e.g., "[Cass. 1re civ., 13 avr. 2023, n° 21-20.145]")
- **FR-007**: System MUST provide a source selector allowing users to search across "Tous" (all) or restrict to a single source type
- **FR-008**: System MUST provide a date range filter (year from/to) that applies to all source types
- **FR-009**: System MUST provide a jurisdiction filter (Cour de cassation, Cour d'appel) that applies to the Jurisprudence tab only
- **FR-010**: System MUST provide a legal code dropdown filter for the Articles tab and a ministry filter for the Circulaires and Q&R tabs
- **FR-011**: Article result cards MUST show a "Voir les décisions (N)" cross-reference button when N > 0 related decisions exist in the jurisprudence dataset
- **FR-012**: The application MUST display a loading indicator during cold start dataset loading (up to 90 seconds), with a user-readable progress message
- **FR-013**: System MUST handle the case where a source dataset is unavailable at startup by degrading gracefully (other sources continue working, affected tab shows error message)
- **FR-014**: System MUST display "Aucun résultat pertinent trouvé" in the synthesis panel when no results are retrieved, instead of generating content

### Key Entities

- **Search Query**: A plain French legal question entered by the user. Has optional filters (date range, jurisdiction, code, ministry). Produces a ranked result set per source type.
- **Result Card**: A single retrieved chunk enriched with source metadata. Belongs to one of four source types. Has: text snippet, date, source badge, and official URL.
- **Synthesis Panel**: The LLM-generated prose answer to the query, grounded in retrieved result chunks. Contains inline citations referencing specific Result Cards.
- **Cross-Reference**: A link from an article Result Card to related jurisprudence Result Cards, based on article identifier matching within decision text.
- **Source Tab**: A tabbed panel grouping Result Cards by source type. Shows count in tab label. Responds to jurisdiction and code/ministry filters.

---

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: After cold start, the first search query returns results in under 10 seconds for a typical French legal question (e.g., "responsabilité civile")
- **SC-002**: The application is fully loaded and interactive within 90 seconds of cold start on HuggingFace free tier infrastructure
- **SC-003**: A query for "responsabilité civile délictuelle" returns results in at least 2 of the 4 source type tabs, with at least 3 result cards per populated tab
- **SC-004**: The synthesis panel generates a response containing at least one inline citation matching a retrieved result card for 90% of queries that return results
- **SC-005**: All official source links point to valid, publicly accessible URLs on legifrance.gouv.fr or courdecassation.fr — zero broken links for retrieved results
- **SC-006**: Applying the date range filter changes the result count in at least one tab for 95% of filtered queries tested against the dataset
- **SC-007**: The cross-reference "Voir les décisions (N)" button appears on article cards when N > 0, with N accurately reflecting the count of related decisions in the dataset

---

## Assumptions

- The `ArthurSrz/open_codes` dataset is publicly accessible on HuggingFace Hub with all four configs populated by spec 005 before enirtcod.fr is deployed.
- The HuggingFace free tier provides sufficient memory (~16GB) to hold all four FAISS indexes in RAM simultaneously. If the dataset exceeds this, only the two largest configs (articles + jurisprudence) will be loaded.
- Cross-references between articles and decisions are determined by searching for the article's `id_legifrance` identifier within decision chunk text — a simple string match, not semantic search.
- The application is deployed as a public HuggingFace Space (no authentication required for access). User accounts and access control are explicitly out of scope.
- The synthesis prompt instructs the LLM to stay grounded in retrieved context. Hallucination risk is mitigated by including the retrieved chunks verbatim in the prompt context window.
- Cold start time up to 90 seconds is acceptable given this is a free-tier research tool. Users are informed via a loading message.
- "enirtcod" is "doctrine" reversed — the domain enirtcod.fr is assumed to be available and will be configured as a custom domain on the HuggingFace Space.
