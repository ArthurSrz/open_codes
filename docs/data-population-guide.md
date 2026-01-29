# Data Population Guide: LEX_codes_piste

## Task T017: Populate Priority Legal Codes

### Overview

This guide provides step-by-step instructions to populate the `LEX_codes_piste` table with the 5 priority legal codes for the MVP implementation.

---

## Code Records to Insert

### 1. Code des collectivités territoriales

```
textId: LEGITEXT000006070633
titre: Code général des collectivités territoriales
slug: code-collectivites-territoriales
actif: true
priorite: 0
nb_articles: null (will be populated during first sync)
derniere_sync: null (will be populated during first sync)
```

### 2. Code des communes

```
textId: LEGITEXT000006070162
titre: Code des communes
slug: code-communes
actif: true
priorite: 1
nb_articles: null
derniere_sync: null
```

### 3. Code électoral

```
textId: LEGITEXT000006070239
titre: Code électoral
slug: code-electoral
actif: true
priorite: 2
nb_articles: null
derniere_sync: null
```

### 4. Code de l'urbanisme

```
textId: LEGITEXT000006074075
titre: Code de l'urbanisme
slug: code-urbanisme
actif: true
priorite: 3
nb_articles: null
derniere_sync: null
```

### 5. Code civil

```
textId: LEGITEXT000006070721
titre: Code civil
slug: code-civil
actif: true
priorite: 4
nb_articles: null
derniere_sync: null
```

---

## Manual Insertion via Xano Admin

### Step 1: Access Table Content

1. Log into your Xano workspace (`x8ki-letl-twmt`)
2. Navigate to **Database** → **Tables**
3. Find and open **LEX_codes_piste** (table ID: 116)
4. Click **Add Record** button

### Step 2: Add Each Code Record

For each of the 5 codes above:

1. Click **Add Record**
2. Fill in the fields:
   - `textId`: Copy the LEGITEXT value exactly
   - `titre`: Copy the full title
   - `slug`: Copy the slug identifier
   - `actif`: Check the box (true)
   - `priorite`: Enter the priority number (0-4)
   - `nb_articles`: Leave empty (null)
   - `derniere_sync`: Leave empty (null)
3. Click **Save**
4. Repeat for all 5 codes

### Step 3: Verify Data

After inserting all records:

1. Query the table to verify 5 records exist:
   ```sql
   SELECT * FROM LEX_codes_piste ORDER BY priorite ASC
   ```

2. Expected result:
   ```
   id | textId                    | titre                                       | priorite | actif
   ---|---------------------------|---------------------------------------------|----------|------
   1  | LEGITEXT000006070633      | Code général des collectivités territoriales| 0        | true
   2  | LEGITEXT000006070162      | Code des communes                           | 1        | true
   3  | LEGITEXT000006070239      | Code électoral                              | 2        | true
   4  | LEGITEXT000006074075      | Code de l'urbanisme                         | 3        | true
   5  | LEGITEXT000006070721      | Code civil                                  | 4        | true
   ```

---

## Alternative: SQL Insert Script

If you prefer SQL insertion via Xano's query interface:

```sql
INSERT INTO LEX_codes_piste (textId, titre, slug, actif, priorite)
VALUES
  ('LEGITEXT000006070633', 'Code général des collectivités territoriales', 'code-collectivites-territoriales', true, 0),
  ('LEGITEXT000006070162', 'Code des communes', 'code-communes', true, 1),
  ('LEGITEXT000006070239', 'Code électoral', 'code-electoral', true, 2),
  ('LEGITEXT000006074075', 'Code de l'urbanisme', 'code-urbanisme', true, 3),
  ('LEGITEXT000006070721', 'Code civil', 'code-civil', true, 4);
```

**Note**: Verify your Xano workspace allows direct SQL execution. If not, use the manual insertion method above.

---

## Validation

After population, verify using a Xano function or API call:

```xanoscript
// Quick verification query
var $codes = db.query("LEX_codes_piste")
  .filter({actif: true})
  .orderBy("priorite", "asc")
  .findMany()

return {
  total_codes: $codes.length,
  codes: $codes.map(function($code) {
    return {
      priorite: $code.priorite,
      textId: $code.textId,
      titre: $code.titre
    }
  })
}
```

Expected output:
```json
{
  "total_codes": 5,
  "codes": [
    {"priorite": 0, "textId": "LEGITEXT000006070633", "titre": "Code général des collectivités territoriales"},
    {"priorite": 1, "textId": "LEGITEXT000006070162", "titre": "Code des communes"},
    {"priorite": 2, "textId": "LEGITEXT000006070239", "titre": "Code électoral"},
    {"priorite": 3, "textId": "LEGITEXT000006074075", "titre": "Code de l'urbanisme"},
    {"priorite": 4, "textId": "LEGITEXT000006070721", "titre": "Code civil"}
  ]
}
```

---

## Post-MVP: Adding Additional Codes

To extend beyond the 5 MVP codes to the full ~98 codes available via PISTE API:

1. Follow the same insertion process
2. Assign higher priority values (5, 6, 7, ...)
3. Set `actif=true` for codes you want to sync
4. The `piste_orchestrer_sync` function will automatically process all active codes in priority order

---

## Troubleshooting

### Issue: Duplicate textId error

**Cause**: The textId field has a UNIQUE constraint

**Solution**:
- Check if the code already exists: `SELECT * FROM LEX_codes_piste WHERE textId='LEGITEXT...'`
- If exists, update instead of insert
- If corrupted, delete and re-insert

### Issue: Priority conflicts

**Cause**: Multiple codes with same priority value

**Solution**: Priority values should be unique for deterministic execution order
- Query: `SELECT priorite, COUNT(*) FROM LEX_codes_piste GROUP BY priorite HAVING COUNT(*) > 1`
- Update duplicates to use unique values

---

## Next Steps

After completing T017:

1. ✅ Verify 5 codes inserted successfully
2. ➡️ Proceed to **T018**: Test initial sync with one code
3. ➡️ Monitor LOG_sync_legifrance table for sync execution results

---

**Task Status**: T017 - Data population guide created ✓

Manually insert these 5 records in Xano admin panel to complete T017.
