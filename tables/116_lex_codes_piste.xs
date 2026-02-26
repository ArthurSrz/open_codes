// Table: LEX_codes_piste
// Purpose: Reference table of French legal codes available via PISTE API
// Maps to ontology entity: CodeJuridiquePISTE
// Relationship: ArticleLegifrance.code -> LEX_codes_piste.textId

table 116_lex_codes_piste {
  // ═══════════════════════════════════════════════════════════════════════════
  // PRIMARY KEY
  // ═══════════════════════════════════════════════════════════════════════════
  id { type: int, primary: true, auto: true }

  // ═══════════════════════════════════════════════════════════════════════════
  // IDENTIFICATION
  // ═══════════════════════════════════════════════════════════════════════════
  textId { type: text, unique: true }                 // LEGITEXT000006070633
  titre { type: text }                                 // "Code des collectivités territoriales"
  slug { type: text, nullable: true }                  // "code-collectivites-territoriales"

  // ═══════════════════════════════════════════════════════════════════════════
  // SYNC CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════════
  actif { type: boolean, default: true }               // Include in sync? (EF-006)
  priorite { type: int, default: 99 }                  // Sync order (0 = highest priority)

  // ═══════════════════════════════════════════════════════════════════════════
  // STATISTICS (updated after each sync)
  // ═══════════════════════════════════════════════════════════════════════════
  nb_articles { type: int, default: 0 }                // Total article count
  derniere_sync { type: timestamp, nullable: true }    // Last successful sync timestamp

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMESTAMPS
  // ═══════════════════════════════════════════════════════════════════════════
  created_at { type: timestamp, default: now() }
  updated_at { type: timestamp, default: now() }
}
