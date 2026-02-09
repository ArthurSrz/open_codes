// API: 921_sync_legifrance_statut_GET
// Purpose: Get current or specific sync status (T023)
// Method: GET
// Auth: Requires authenticated user
// Input: { sync_id?: int }
// Output: LOG_sync_legifrance entry with progress

query 921_sync_legifrance_statut_GET {
  auth: utilisateurs

  input: {
    sync_id: int?               // Optional: specific sync ID (default: latest)
  }

  run {
    var sync_log = null

    if input.sync_id != null {
      // Get specific sync
      var results = db.query({
        from: LOG_sync_legifrance,
        where: { id: input.sync_id },
        limit: 1
      })
      if list.length(results) == 0 {
        throw { status: 404, message: text.concat("Sync not found: ", input.sync_id) }
      }
      sync_log = results[0]
    } else {
      // Get latest sync
      var results = db.query({
        from: LOG_sync_legifrance,
        order_by: [{ debut_sync: "desc" }],
        limit: 1
      })
      if list.length(results) == 0 {
        return { message: "No sync history found" }
      }
      sync_log = results[0]
    }

    // Calculate progress if in progress
    var progress = null
    if sync_log.statut == "EN_COURS" {
      var elapsed = date.diff(sync_log.debut_sync, date.now(), "seconds")
      progress = {
        elapsed_seconds: elapsed,
        articles_so_far: sync_log.articles_traites
      }
    }

    return {
      id: sync_log.id,
      statut: sync_log.statut,
      code_textId: sync_log.code_textId,
      debut_sync: sync_log.debut_sync,
      fin_sync: sync_log.fin_sync,
      duree_secondes: sync_log.duree_secondes,
      articles_traites: sync_log.articles_traites,
      articles_crees: sync_log.articles_crees,
      articles_maj: sync_log.articles_maj,
      articles_erreur: sync_log.articles_erreur,
      articles_ignores: sync_log.articles_ignores,
      embeddings_generes: sync_log.embeddings_generes,
      erreur_message: sync_log.erreur_message,
      progress: progress
    }
  }
}
