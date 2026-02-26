// Table: LOG_sync_legifrance
// Purpose: Audit log for PISTE synchronization executions
// Maps to ontology entity: SyncExecution
// Relationship: SyncExecution synchronise CodeJuridiquePISTE (N:N via code_textId)

table 117_log_sync_legifrance {
  // ═══════════════════════════════════════════════════════════════════════════
  // PRIMARY KEY
  // ═══════════════════════════════════════════════════════════════════════════
  id { type: int, primary: true, auto: true }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXECUTION CONTEXT
  // ═══════════════════════════════════════════════════════════════════════════
  code_textId { type: text, nullable: true }           // Specific code synced (NULL = all codes)
  force_full { type: boolean, default: false }         // Full sync forced (ignore hashes)?
  declencheur { type: text, default: "task" }          // "task", "api", "manual"

  // ═══════════════════════════════════════════════════════════════════════════
  // STATUS (EF-008: Log all sync operations)
  // ═══════════════════════════════════════════════════════════════════════════
  statut { type: text, index: btree, default: "EN_COURS" }  // EN_COURS, TERMINE, ERREUR

  // ═══════════════════════════════════════════════════════════════════════════
  // STATISTICS
  // ═══════════════════════════════════════════════════════════════════════════
  articles_traites { type: int, default: 0 }           // Total processed
  articles_crees { type: int, default: 0 }             // New articles inserted
  articles_maj { type: int, default: 0 }               // Existing articles updated
  articles_erreur { type: int, default: 0 }            // Failed articles
  articles_ignores { type: int, default: 0 }           // Skipped (unchanged hash)
  embeddings_generes { type: int, default: 0 }         // Mistral API calls made

  // ═══════════════════════════════════════════════════════════════════════════
  // ERROR TRACKING
  // ═══════════════════════════════════════════════════════════════════════════
  erreur_message { type: text, nullable: true }        // Error description if failed
  erreurs_details { type: json, nullable: true }       // Array of { article_id, error }

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMING
  // ═══════════════════════════════════════════════════════════════════════════
  debut_sync { type: timestamp, default: now() }       // Start timestamp
  fin_sync { type: timestamp, nullable: true }         // End timestamp
  duree_secondes { type: int, nullable: true }         // Duration in seconds

  // ═══════════════════════════════════════════════════════════════════════════
  // TIMESTAMPS
  // ═══════════════════════════════════════════════════════════════════════════
  created_at { type: timestamp, default: now() }
  updated_at { type: timestamp, default: now() }
}
