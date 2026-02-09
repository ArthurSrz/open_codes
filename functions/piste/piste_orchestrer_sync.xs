// Function: piste_orchestrer_sync
// Purpose: Orchestrate sync of all active legal codes (T016)
// Input: Optional textId to sync specific code, force_full flag
// Output: LOG_sync_legifrance entry with full statistics
// Used by: Task sync_legifrance_quotidien and API 920_sync_legifrance_lancer
//
// FIXES (2026-02-06):
// - Removed code_nom parameter from piste_sync_code call (parameter doesn't exist)
// - Added |round filter to duration calculations (duree_secondes is int type)
// - Fixed variable shadowing in else branch for $codes

function piste_orchestrer_sync {
  input: {
    code_textId: text?            // Optional: sync specific code only
    force_full: boolean = false   // If true, ignore hashes and sync all
  }

  // Create LOG entry
  var log_entry = db.insert({
    into: LOG_sync_legifrance,
    values: {
      code_textId: code_textId,
      statut: "EN_COURS",
      articles_traites: 0,
      articles_crees: 0,
      articles_maj: 0,
      articles_erreur: 0,
      embeddings_generes: 0,
      debut_sync: date.now()
    }
  })

  var log_id = log_entry.id

  // Aggregate statistics
  var total_codes = 0
  var total_articles = 0
  var total_crees = 0
  var total_maj = 0
  var total_erreur = 0
  var total_embeddings = 0

  try_catch {
    try {
      // Get codes to sync
      var codes = []

      if code_textId != null {
        // Sync specific code
        var code_info = db.query({
          from: LEX_codes_piste,
          where: { textId: code_textId },
          return: "single"
        })
        precondition(code_info != null, "Code non trouve: " + code_textId)
        codes = [code_info]
      } else {
        // Sync all active codes, ordered by priority
        // FIX: Use separate variable to avoid shadowing
        var active_codes = db.query({
          from: LEX_codes_piste,
          where: { actif: true },
          order_by: [{ priorite: "asc" }],
          return: "list"
        })
        codes = active_codes
      }

      // Sync each code
      foreach code in codes {
        try_catch {
          try {
            // FIX: Removed code_nom parameter (not accepted by piste_sync_code)
            var sync_result = call piste_sync_code(
              textId: code.textId,
              force_full: force_full,
              log_id: log_id
            )

            // Aggregate stats
            total_codes = total_codes + 1
            total_articles = total_articles + sync_result.articles_traites
            total_crees = total_crees + sync_result.articles_crees
            total_maj = total_maj + sync_result.articles_maj
            total_erreur = total_erreur + sync_result.articles_erreur
            total_embeddings = total_embeddings + sync_result.embeddings_generes

            // Update code's last sync time and article count
            db.update({
              table: LEX_codes_piste,
              where: { id: code.id },
              values: {
                derniere_sync: date.now(),
                nb_articles: sync_result.articles_traites
              }
            })

            // Update log with progress
            db.update({
              table: LOG_sync_legifrance,
              where: { id: log_id },
              values: {
                articles_traites: total_articles,
                articles_crees: total_crees,
                articles_maj: total_maj,
                articles_erreur: total_erreur,
                embeddings_generes: total_embeddings
              }
            })
          }
          catch (code_error) {
            db.update({
              table: LOG_sync_legifrance,
              where: { id: log_id },
              values: {
                erreur_message: "Erreur sur code " + code.textId + ": " + code_error
              }
            })
          }
        }
      }

      // Calculate duration - FIX: Round to integer
      var fin = date.now()
      var duree = round((fin - debut) / 1000)

      // Update LOG with success
      db.update({
        table: LOG_sync_legifrance,
        where: { id: log_id },
        values: {
          statut: "TERMINE",
          fin_sync: fin,
          duree_secondes: duree,
          articles_traites: total_articles,
          articles_crees: total_crees,
          articles_maj: total_maj,
          articles_erreur: total_erreur,
          embeddings_generes: total_embeddings
        }
      })
    }
    catch (error) {
      // Update LOG with error - FIX: Round duration
      var fin = date.now()
      db.update({
        table: LOG_sync_legifrance,
        where: { id: log_id },
        values: {
          statut: "ERREUR",
          fin_sync: fin,
          duree_secondes: round((fin - debut) / 1000),
          erreur_message: "Erreur globale: " + error
        }
      })
    }
  }

  // Return summary
  return {
    sync_log_id: log_id,
    codes_traites: total_codes,
    total_articles: total_articles,
    duree_secondes: round((date.now() - debut) / 1000)
  }
}
