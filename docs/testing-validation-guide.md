# Testing & Validation Guide: Pipeline Sync Légifrance

## Overview

This guide provides comprehensive testing procedures for validating the LegalKit vector sync pipeline implementation.

---

## T018: Test Initial Sync (User Story 1 - P1 MVP)

### Objective
Verify that the initial synchronization correctly imports legal articles from PISTE API into Xano with valid embeddings.

### Prerequisites
- ✅ T010 complete: Environment variables configured
- ✅ T017 complete: LEX_codes_piste populated with 5 priority codes

### Test Procedure

#### Step 1: Trigger Manual Sync

**Method A - Via Xano Function Testing**:
1. Navigate to `functions/piste/piste_orchestrer_sync.xs`
2. Click **Test** button
3. Provide input (optional - can filter by code):
   ```json
   {
     "code_textId": "LEGITEXT000006070633"
   }
   ```
4. Click **Run**
5. Monitor execution time (should complete within reasonable time for one code)

**Method B - Via API Endpoint** (if T022 complete):
```bash
curl -X POST https://x8ki-letl-twmt.xano.io/api:your-api-group/sync_legifrance_lancer \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "code_textId": "LEGITEXT000006070633",
    "force_full": true
  }'
```

#### Step 2: Verify Sync Execution

Check the LOG_sync_legifrance table:

```sql
SELECT
  id,
  code_textId,
  statut,
  articles_traites,
  articles_crees,
  articles_maj,
  articles_erreur,
  embeddings_generes,
  debut_sync,
  fin_sync,
  duree_secondes,
  erreur_message
FROM LOG_sync_legifrance
ORDER BY debut_sync DESC
LIMIT 1;
```

**Expected Results**:
- `statut`: "TERMINE" (not "ERREUR")
- `articles_traites` > 0
- `articles_crees` > 0 (for first sync)
- `articles_erreur` < 10 (< 0.5% error rate acceptable)
- `embeddings_generes` > 0
- `erreur_message`: NULL or minimal warnings
- `duree_secondes`: Reasonable (varies by code size)

#### Step 3: Verify Article Import

Query the REF_codes_legifrance table:

```sql
SELECT
  id,
  code,
  id_legifrance,
  num,
  contenu_article,
  embeddings,
  content_hash,
  last_sync_at,
  etat
FROM REF_codes_legifrance
WHERE code = 'Code général des collectivités territoriales'
LIMIT 10;
```

**Expected Results**:
- Multiple rows returned (articles imported)
- `id_legifrance`: Populated with LEGIARTI... identifiers
- `num`: Article numbers populated
- `contenu_article`: Non-null article text
- `embeddings`: **NOT NULL** (critical - 1024-dim vector)
- `content_hash`: Populated SHA256 hash
- `last_sync_at`: Recent timestamp
- `etat`: "VIGUEUR" for active articles

#### Step 4: Verify Embedding Dimensions

```sql
SELECT
  id,
  num,
  LENGTH(embeddings::text) as embedding_length,
  content_hash
FROM REF_codes_legifrance
WHERE code = 'Code général des collectivités territoriales'
  AND embeddings IS NOT NULL
LIMIT 5;
```

**Expected**: Each embedding should be a 1024-dimensional vector.

#### Step 5: Test Vector Search

Run a semantic similarity search to verify embeddings work:

```xanoscript
// Generate test embedding for query
var $query_text = "règles d'urbanisme dans les communes"
var $query_embedding = mistral_generer_embedding($query_text)

// Search for similar articles
var $similar_articles = db.query("REF_codes_legifrance")
  .filter({etat: "VIGUEUR"})
  .orderBy("embeddings <#> $query_embedding", "asc")  // Inner product distance
  .limit(5)
  .findMany()

return $similar_articles
```

**Expected**: Returns 5 relevant articles related to urban planning rules.

### Success Criteria (from spec.md CS-003)

- ✅ 99.5% of articles have valid embeddings (< 0.5% failure rate)
- ✅ Articles contain all 38 metadata fields from PISTE API
- ✅ content_hash populated for change detection
- ✅ last_sync_at timestamp reflects recent sync

---

## T020: Verify Incremental Logic (User Story 2 - P2)

### Objective
Verify that the sync correctly handles incremental updates by comparing content hashes.

### Test Procedure

#### Step 1: Identify Test Article

```sql
SELECT id, id_legifrance, num, content_hash, contenu_article
FROM REF_codes_legifrance
WHERE code = 'Code général des collectivités territoriales'
  AND contenu_article IS NOT NULL
LIMIT 1;
```

Note the `id_legifrance` and original `content_hash`.

#### Step 2: Simulate Article Change

Manually modify the article content to simulate a PISTE API change:

```sql
UPDATE REF_codes_legifrance
SET
  contenu_article = contenu_article || ' [MODIFIED FOR TEST]',
  content_hash = 'outdated_hash_for_testing'
WHERE id = [noted_id];
```

#### Step 3: Run Incremental Sync

```xanoscript
// Call piste_sync_code with the same code
piste_sync_code("LEGITEXT000006070633", false)  // force_full=false
```

#### Step 4: Verify Update Detection

```sql
SELECT
  id,
  id_legifrance,
  num,
  contenu_article,
  content_hash,
  last_sync_at
FROM REF_codes_legifrance
WHERE id = [noted_id];
```

**Expected**:
- `contenu_article`: Updated to match PISTE source (test marker removed)
- `content_hash`: New SHA256 hash matching the updated content
- `last_sync_at`: Recent timestamp
- Embedding regenerated for the modified article

#### Step 5: Verify ABROGE Handling

Test that abrogated articles are marked inactive:

1. Find or create a test article with `etat = "ABROGE"`
2. Run sync
3. Verify article is either:
   - Marked inactive (if using soft-delete pattern)
   - OR excluded from active search index
   - OR flagged appropriately for exclusion from search

### Success Criteria

- ✅ Only modified articles are updated (unchanged articles skipped)
- ✅ Hash comparison correctly detects changes
- ✅ Abrogated articles are handled appropriately
- ✅ Sync time is significantly reduced (incremental vs. full)

---

## T021: Test Incremental Sync Performance (User Story 2)

### Objective
Verify that running sync twice processes only changed articles.

### Test Procedure

#### Step 1: Run First Full Sync

```bash
# Record start time
START_TIME=$(date +%s)

# Run sync
piste_orchestrer_sync()

# Record end time
END_TIME=$(date +%s)
DURATION_1=$((END_TIME - START_TIME))
```

Check LOG_sync_legifrance:
```sql
SELECT articles_crees, articles_maj, duree_secondes
FROM LOG_sync_legifrance
ORDER BY debut_sync DESC
LIMIT 1;
```

**Expected**:
- `articles_crees`: Large number (first sync)
- `articles_maj`: 0 (no existing articles to update)

#### Step 2: Run Second Sync Immediately

```bash
START_TIME=$(date +%s)
piste_orchestrer_sync()
END_TIME=$(date +%s)
DURATION_2=$((END_TIME - START_TIME))
```

Check LOG_sync_legifrance:
```sql
SELECT articles_crees, articles_maj, duree_secondes
FROM LOG_sync_legifrance
ORDER BY debut_sync DESC
LIMIT 1;
```

**Expected**:
- `articles_crees`: 0 (no new articles)
- `articles_maj`: 0 or very few (no changes detected)
- `duree_secondes`: **< 30 minutes** (per spec.md CS-002)
- Duration significantly less than first sync (DURATION_2 << DURATION_1)

### Success Criteria (from spec.md CS-002)

- ✅ Incremental sync completes in < 30 minutes
- ✅ Second sync processes 0 or minimal articles (only actual changes)
- ✅ LOG shows clear distinction: articles_crees vs. articles_maj

---

## T025: Test Monitoring APIs (User Story 3 - P3)

### Objective
Verify REST API endpoints for monitoring sync status and history.

### Prerequisites
- ✅ T022, T023, T024 complete: Monitoring APIs deployed

### Test Procedure

#### Step 1: Test Sync Launch API (920_sync_legifrance_lancer_POST)

```bash
# Launch a new sync via API
curl -X POST https://x8ki-letl-twmt.xano.io/api:maintenance/sync_legifrance_lancer \
  -H "Authorization: Bearer YOUR_USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "code_textId": "LEGITEXT000006070239",
    "force_full": false
  }'
```

**Expected Response**:
```json
{
  "sync_id": 123,
  "statut": "EN_COURS",
  "debut_sync": "2026-01-29T18:30:00Z",
  "message": "Synchronisation lancée avec succès"
}
```

#### Step 2: Test Status API (921_sync_legifrance_statut_GET)

Poll the status repeatedly during execution:

```bash
# Get status of running sync
for i in {1..10}; do
  curl -X GET "https://x8ki-letl-twmt.xano.io/api:maintenance/sync_legifrance_statut?sync_id=123" \
    -H "Authorization: Bearer YOUR_USER_TOKEN"
  sleep 5
done
```

**Expected Response** (during execution):
```json
{
  "sync_id": 123,
  "statut": "EN_COURS",
  "articles_traites": 1250,
  "articles_crees": 15,
  "articles_maj": 3,
  "articles_erreur": 0,
  "debut_sync": "2026-01-29T18:30:00Z",
  "progression": "Processing Code électoral..."
}
```

**Expected Response** (after completion):
```json
{
  "sync_id": 123,
  "statut": "TERMINE",
  "articles_traites": 1580,
  "articles_crees": 15,
  "articles_maj": 3,
  "articles_erreur": 2,
  "embeddings_generes": 18,
  "debut_sync": "2026-01-29T18:30:00Z",
  "fin_sync": "2026-01-29T18:45:00Z",
  "duree_secondes": 900
}
```

#### Step 3: Test History API (922_sync_legifrance_historique_GET)

```bash
# Get sync history
curl -X GET "https://x8ki-letl-twmt.xano.io/api:maintenance/sync_legifrance_historique?limit=5&offset=0" \
  -H "Authorization: Bearer YOUR_USER_TOKEN"
```

**Expected Response**:
```json
{
  "total": 15,
  "limit": 5,
  "offset": 0,
  "syncs": [
    {
      "id": 123,
      "code_textId": "LEGITEXT000006070239",
      "statut": "TERMINE",
      "articles_traites": 1580,
      "articles_crees": 15,
      "articles_maj": 3,
      "embeddings_generes": 18,
      "debut_sync": "2026-01-29T18:30:00Z",
      "fin_sync": "2026-01-29T18:45:00Z",
      "duree_secondes": 900
    },
    // ... 4 more records
  ]
}
```

### Success Criteria

- ✅ Launch API triggers async sync execution
- ✅ Status API shows real-time progression updates
- ✅ History API returns paginated sync records
- ✅ All APIs require authentication (auth="utilisateurs")
- ✅ Sync completion appears in history with correct stats

---

## T027: Quickstart Validation

### Objective
Run the complete validation workflow from quickstart.md.

### Test Procedure

#### Test 1: PISTE OAuth Authentication

```bash
curl -X POST https://oauth.piste.gouv.fr/api/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=dc06ede7-4a49-44e4-90d8-af342a5e1f36&client_secret=2bfad70f-7cc3-4c60-84ec-1f1e6e69773e"
```

**Expected**: HTTP 200, JSON response with `access_token`

#### Test 2: PISTE Article Retrieval

```bash
# First, get token from Test 1
TOKEN="your_access_token_here"

# Get table of contents
curl -X POST https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/consult/legi/tableMatieres \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "textId": "LEGITEXT000006070633",
    "date": "2026-01-29"
  }'
```

**Expected**: HTTP 200, JSON structure with sections and article IDs

```bash
# Get specific article
curl -X POST https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/consult/getArticle \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "id": "LEGIARTI000006360827"
  }'
```

**Expected**: HTTP 200, JSON with all 38 article fields

#### Test 3: Full Pipeline End-to-End

1. Clear test data (optional):
   ```sql
   DELETE FROM REF_codes_legifrance WHERE code = 'Test Code';
   DELETE FROM LOG_sync_legifrance WHERE code_textId = 'TEST';
   ```

2. Run full sync pipeline:
   ```xanoscript
   piste_orchestrer_sync()
   ```

3. Verify results across all tables:
   - LEX_codes_piste: 5 codes with updated `derniere_sync` and `nb_articles`
   - REF_codes_legifrance: Thousands of articles imported
   - LOG_sync_legifrance: Successful sync entries

### Success Criteria

- ✅ PISTE API accessible and returning data
- ✅ Full pipeline executes without fatal errors
- ✅ Data flows correctly through all components

---

## T028: Verify Indexes

### Objective
Confirm all required indexes are created on REF_codes_legifrance for optimal query performance.

### Test Procedure

Query the database schema to verify indexes:

```sql
-- PostgreSQL syntax (Xano uses PostgreSQL)
SELECT
  tablename,
  indexname,
  indexdef
FROM pg_indexes
WHERE tablename = 'ref_codes_legifrance'
ORDER BY indexname;
```

**Expected Indexes**:

1. **Primary Key**: `id` (int, primary key)
2. **B-tree indexes**:
   - `created_at` (DESC) - for recent article queries
   - `idEli` - European Legislation Identifier lookups
   - `etat` - filter by legal status (VIGUEUR, ABROGE, etc.)
   - `cid` - Chronical ID lookups
   - `id_legifrance` - LEGIARTI identifier lookups
   - `code` - filter by legal code name
3. **Vector index**: `embeddings` (vector_ip_ops) - for similarity search

### Verification Script

```xanoscript
// Check if vector search is performant
var $start = Date.now()

var $results = db.query("REF_codes_legifrance")
  .filter({etat: "VIGUEUR"})  // Should use b-tree index
  .orderBy("embeddings <#> $test_vector", "asc")  // Should use vector index
  .limit(10)
  .findMany()

var $duration = Date.now() - $start

return {
  query_time_ms: $duration,
  results_count: $results.length,
  performance: $duration < 1000 ? "FAST" : "SLOW"
}
```

**Expected**: Query time < 1000ms for indexed fields

### Success Criteria

- ✅ All 9 indexes present (7 b-tree + 1 vector + 1 primary key)
- ✅ Vector similarity search executes in < 1s
- ✅ Filtering by `etat`, `code`, `idEli` uses indexes (fast queries)

---

## T029: Final Sync Validation

### Objective
Validate the complete system with all 5 priority codes synchronized.

### Test Procedure

#### Step 1: Full System Sync

```xanoscript
// Trigger sync for all active codes
piste_orchestrer_sync({force_full: false})
```

#### Step 2: Verify Code Coverage

```sql
SELECT
  lp.textId,
  lp.titre,
  lp.nb_articles,
  lp.derniere_sync,
  COUNT(rlf.id) as articles_in_db
FROM LEX_codes_piste lp
LEFT JOIN REF_codes_legifrance rlf ON rlf.code = lp.titre
WHERE lp.actif = true
GROUP BY lp.id
ORDER BY lp.priorite;
```

**Expected**: All 5 codes show `nb_articles` > 0 and `derniere_sync` populated

#### Step 3: Verify Embedding Coverage (CS-003)

```sql
SELECT
  code,
  COUNT(*) as total_articles,
  COUNT(embeddings) as articles_with_embeddings,
  ROUND(100.0 * COUNT(embeddings) / COUNT(*), 2) as embedding_coverage_pct,
  COUNT(CASE WHEN embeddings IS NULL THEN 1 END) as missing_embeddings
FROM REF_codes_legifrance
WHERE code IN (
  'Code général des collectivités territoriales',
  'Code des communes',
  'Code électoral',
  'Code de l'urbanisme',
  'Code civil'
)
GROUP BY code
ORDER BY code;
```

**Expected per spec.md CS-003**:
- `embedding_coverage_pct` ≥ 99.5% for each code
- `missing_embeddings` < 0.5% of total articles

#### Step 4: Verify Search Quality (CS-004)

Run 10 test queries and measure relevance:

```xanoscript
var $test_queries = [
  "règles d'élection des maires",
  "compétences des conseils municipaux",
  "urbanisme et permis de construire",
  "mariage civil",
  "organisation des communes"
]

var $results = []

for (var $query of $test_queries) {
  var $query_embedding = mistral_generer_embedding($query)

  var $top_result = db.query("REF_codes_legifrance")
    .filter({etat: "VIGUEUR"})
    .orderBy("embeddings <#> $query_embedding", "asc")
    .limit(1)
    .findOne()

  // Calculate similarity score (IP distance to similarity)
  var $similarity = 1.0 / (1.0 + Math.abs($top_result.embeddings_distance))

  $results.push({
    query: $query,
    top_article: $top_result.num,
    similarity: $similarity,
    relevant: $similarity >= 0.8
  })
}

var $relevant_count = $results.filter(r => r.relevant).length

return {
  total_queries: $test_queries.length,
  relevant_results: $relevant_count,
  success_rate_pct: ($relevant_count / $test_queries.length) * 100,
  passes_cs004: ($relevant_count / $test_queries.length) >= 0.95
}
```

**Expected per spec.md CS-004**:
- `success_rate_pct` ≥ 95% (similarity threshold ≥ 0.8)

#### Step 5: Verify Freshness (CS-006)

```sql
SELECT
  code,
  MAX(last_sync_at) as most_recent_sync,
  AGE(NOW(), MAX(last_sync_at)) as data_age
FROM REF_codes_legifrance
WHERE code IN (
  'Code général des collectivités territoriales',
  'Code des communes',
  'Code électoral',
  'Code de l'urbanisme',
  'Code civil'
)
GROUP BY code;
```

**Expected per spec.md CS-006**:
- `data_age` < 48 hours for all codes

### Success Criteria (Final System Validation)

From spec.md Success Criteria section:

- ✅ **CS-001**: 5 codes imported in < 24h ✓
- ✅ **CS-002**: Incremental sync < 30 min ✓
- ✅ **CS-003**: 99.5% embeddings valid ✓
- ✅ **CS-004**: 95% search relevance (similarity ≥ 0.8) ✓
- ✅ **CS-005**: Failures detected & alerted < 5 min (via LOG table)
- ✅ **CS-006**: Data freshness < 48h ✓

---

## Troubleshooting Reference

### Common Issues

**Issue**: Embeddings NULL for many articles
- **Check**: Mistral API key validity
- **Check**: Rate limiting (5 req/s Mistral)
- **Check**: Article text length (truncate at 8000 tokens)

**Issue**: Sync takes > 30 min (incremental)
- **Check**: Hash comparison logic working
- **Check**: Unnecessary article re-processing
- **Check**: Database indexes present

**Issue**: Articles not found in search
- **Check**: `etat = "VIGUEUR"` filter applied
- **Check**: Vector index created (`vector_ip_ops`)
- **Check**: Similarity threshold appropriate (≥ 0.8)

**Issue**: PISTE API 401 errors
- **Check**: OAuth token refresh logic
- **Check**: Token expiry (1 hour)
- **Check**: Credentials in environment variables

---

## Test Completion Checklist

- [ ] T018: Initial sync successful ✓
- [ ] T020: Incremental logic verified ✓
- [ ] T021: Performance validated (< 30min) ✓
- [ ] T025: Monitoring APIs functional ✓
- [ ] T027: Quickstart scenarios pass ✓
- [ ] T028: All indexes present ✓
- [ ] T029: Final validation complete (all success criteria met) ✓

---

**Next Steps**: After all tests pass, the system is ready for production deployment and daily automated syncs (T019 - scheduled task at 02:00 UTC).
