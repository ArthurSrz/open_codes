// Task: sync_populate_queue
// Purpose: Nightly task that populates QUEUE_sync with all article IDs from 5 legal codes
// Architecture: Fetches TOC for each code via PISTE API, extracts article IDs, inserts into queue
// Constraint: 5 explicit sequential blocks (no foreach over codes with function.run — hangs)
// Schedule: Daily at 02:00 UTC

task "sync_populate_queue" {
  description = "Peuple la file d'attente QUEUE_sync avec tous les articles des 5 codes juridiques via l'API PISTE. Exécuté chaque nuit à 02h00 UTC."

  stack {
    // ═══════════════════════════════════════════════════════════════
    // INIT: Create sync log + get start time
    // ═══════════════════════════════════════════════════════════════
    var $debut_ms {
      value = ("now"|to_ms)
      description = "Start time in ms for duration calculation"
    }

    db.add LOG_sync_legifrance {
      data = {
        statut: "EN_COURS"
        declencheur: "task"
        force_full: false
        debut_sync: "now"
      }
      description = "Create sync execution log"
    } as $sync_log

    var $total_queued {
      value = 0
      description = "Total articles queued across all codes"
    }

    var $errors_list {
      value = []
      description = "Accumulated errors per code"
    }

    // ═══════════════════════════════════════════════════════════════
    // OAUTH: Get PISTE token (inline — function.run returns metadata)
    // ═══════════════════════════════════════════════════════════════
    api.request {
      url = "https://oauth.piste.gouv.fr/api/oauth/token"
      method = "POST"
      params = {
        grant_type: "client_credentials"
        client_id: $env.PISTE_CLIENT_ID
        client_secret: $env.PISTE_CLIENT_SECRET
        scope: "openid"
      }
      headers = []
        |push:"Content-Type: application/x-www-form-urlencoded"
      description = "PISTE OAuth2 token"
    } as $oauth_result

    precondition ($oauth_result.response.status == 200) {
      error = "OAuth failed: status " ~ $oauth_result.response.status
    }

    var $the_token {
      value = $oauth_result.response.result.access_token
      description = "PISTE Bearer token"
    }

    // ═══════════════════════════════════════════════════════════════
    // FETCH ALL 5 CODES from LEX_codes_piste
    // ═══════════════════════════════════════════════════════════════
    db.query "LEX_codes_piste" {
      where = $db.LEX_codes_piste.actif == true
      description = "Get all active legal codes"
    } as $codes

    debug.log {
      value = "Found " ~ ($codes|count) ~ " active codes to sync"
    }

    // ═══════════════════════════════════════════════════════════════
    // CODE 1 (index 0)
    // ═══════════════════════════════════════════════════════════════
    conditional {
      if (($codes|count) >= 1) {
        var $code_0 {
          value = $codes[0]
        }

        try_catch {
          try {
            function.run "piste/piste_get_toc" {
              input = {api_token: $the_token, textId: $code_0.textId}
            } as $toc_0

            function.run "piste/piste_extraire_articles_toc" {
              input = {toc: $toc_0.sections ?? [], code_nom: $code_0.textId}
            } as $extracted_0

            var $articles_0 {
              value = $extracted_0.articles ?? []
            }

            foreach ($articles_0) {
              each as $art {
                db.add QUEUE_sync {
                  data = {
                    sync_log_id: $sync_log.id
                    code_textId: $code_0.textId
                    article_id_legifrance: $art.id
                    status: "pending"
                  }
                }
              }
            }

            var.update $total_queued {
              value = $total_queued + ($articles_0|count)
            }

            debug.log {
              value = "Code 1 (" ~ $code_0.textId ~ "): " ~ ($articles_0|count) ~ " articles queued"
            }
          }

          catch {
            debug.log {
              value = "Code 1 error: " ~ $error
            }

            var.update $errors_list {
              value = $errors_list|push:({} |set:"code":($code_0.textId ?? "unknown") |set:"error":$error)
            }
          }
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // CODE 2 (index 1)
    // ═══════════════════════════════════════════════════════════════
    conditional {
      if (($codes|count) >= 2) {
        var $code_1 {
          value = $codes[1]
        }

        try_catch {
          try {
            function.run "piste/piste_get_toc" {
              input = {api_token: $the_token, textId: $code_1.textId}
            } as $toc_1

            function.run "piste/piste_extraire_articles_toc" {
              input = {toc: $toc_1.sections ?? [], code_nom: $code_1.textId}
            } as $extracted_1

            var $articles_1 {
              value = $extracted_1.articles ?? []
            }

            foreach ($articles_1) {
              each as $art {
                db.add QUEUE_sync {
                  data = {
                    sync_log_id: $sync_log.id
                    code_textId: $code_1.textId
                    article_id_legifrance: $art.id
                    status: "pending"
                  }
                }
              }
            }

            var.update $total_queued {
              value = $total_queued + ($articles_1|count)
            }

            debug.log {
              value = "Code 2 (" ~ $code_1.textId ~ "): " ~ ($articles_1|count) ~ " articles queued"
            }
          }

          catch {
            debug.log {
              value = "Code 2 error: " ~ $error
            }

            var.update $errors_list {
              value = $errors_list|push:({} |set:"code":($code_1.textId ?? "unknown") |set:"error":$error)
            }
          }
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // CODE 3 (index 2)
    // ═══════════════════════════════════════════════════════════════
    conditional {
      if (($codes|count) >= 3) {
        var $code_2 {
          value = $codes[2]
        }

        try_catch {
          try {
            function.run "piste/piste_get_toc" {
              input = {api_token: $the_token, textId: $code_2.textId}
            } as $toc_2

            function.run "piste/piste_extraire_articles_toc" {
              input = {toc: $toc_2.sections ?? [], code_nom: $code_2.textId}
            } as $extracted_2

            var $articles_2 {
              value = $extracted_2.articles ?? []
            }

            foreach ($articles_2) {
              each as $art {
                db.add QUEUE_sync {
                  data = {
                    sync_log_id: $sync_log.id
                    code_textId: $code_2.textId
                    article_id_legifrance: $art.id
                    status: "pending"
                  }
                }
              }
            }

            var.update $total_queued {
              value = $total_queued + ($articles_2|count)
            }

            debug.log {
              value = "Code 3 (" ~ $code_2.textId ~ "): " ~ ($articles_2|count) ~ " articles queued"
            }
          }

          catch {
            debug.log {
              value = "Code 3 error: " ~ $error
            }

            var.update $errors_list {
              value = $errors_list|push:({} |set:"code":($code_2.textId ?? "unknown") |set:"error":$error)
            }
          }
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // CODE 4 (index 3)
    // ═══════════════════════════════════════════════════════════════
    conditional {
      if (($codes|count) >= 4) {
        var $code_3 {
          value = $codes[3]
        }

        try_catch {
          try {
            function.run "piste/piste_get_toc" {
              input = {api_token: $the_token, textId: $code_3.textId}
            } as $toc_3

            function.run "piste/piste_extraire_articles_toc" {
              input = {toc: $toc_3.sections ?? [], code_nom: $code_3.textId}
            } as $extracted_3

            var $articles_3 {
              value = $extracted_3.articles ?? []
            }

            foreach ($articles_3) {
              each as $art {
                db.add QUEUE_sync {
                  data = {
                    sync_log_id: $sync_log.id
                    code_textId: $code_3.textId
                    article_id_legifrance: $art.id
                    status: "pending"
                  }
                }
              }
            }

            var.update $total_queued {
              value = $total_queued + ($articles_3|count)
            }

            debug.log {
              value = "Code 4 (" ~ $code_3.textId ~ "): " ~ ($articles_3|count) ~ " articles queued"
            }
          }

          catch {
            debug.log {
              value = "Code 4 error: " ~ $error
            }

            var.update $errors_list {
              value = $errors_list|push:({} |set:"code":($code_3.textId ?? "unknown") |set:"error":$error)
            }
          }
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // CODE 5 (index 4)
    // ═══════════════════════════════════════════════════════════════
    conditional {
      if (($codes|count) >= 5) {
        var $code_4 {
          value = $codes[4]
        }

        try_catch {
          try {
            function.run "piste/piste_get_toc" {
              input = {api_token: $the_token, textId: $code_4.textId}
            } as $toc_4

            function.run "piste/piste_extraire_articles_toc" {
              input = {toc: $toc_4.sections ?? [], code_nom: $code_4.textId}
            } as $extracted_4

            var $articles_4 {
              value = $extracted_4.articles ?? []
            }

            foreach ($articles_4) {
              each as $art {
                db.add QUEUE_sync {
                  data = {
                    sync_log_id: $sync_log.id
                    code_textId: $code_4.textId
                    article_id_legifrance: $art.id
                    status: "pending"
                  }
                }
              }
            }

            var.update $total_queued {
              value = $total_queued + ($articles_4|count)
            }

            debug.log {
              value = "Code 5 (" ~ $code_4.textId ~ "): " ~ ($articles_4|count) ~ " articles queued"
            }
          }

          catch {
            debug.log {
              value = "Code 5 error: " ~ $error
            }

            var.update $errors_list {
              value = $errors_list|push:({} |set:"code":($code_4.textId ?? "unknown") |set:"error":$error)
            }
          }
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════
    // FINALIZE: Update sync log with totals
    // ═══════════════════════════════════════════════════════════════
    var $duree_s {
      value = ((("now"|to_ms) - $debut_ms) / 1000)|round
      description = "Duration in seconds"
    }

    var $final_statut {
      value = (($errors_list|count) == 0 ? "TERMINE" : (($total_queued > 0) ? "TERMINE" : "ERREUR"))
    }

    db.edit "LOG_sync_legifrance" {
      field_name = "id"
      field_value = $sync_log.id
      data = {
        statut: $final_statut
        articles_traites: $total_queued
        fin_sync: "now"
        duree_secondes: $duree_s
        erreurs_details: $errors_list
        erreur_message: (($errors_list|count) > 0 ? (($errors_list|count) ~ " code(s) had errors") : null)
      }
      description = "Finalize sync log"
    }

    debug.log {
      value = "Queue populated: " ~ $total_queued ~ " articles, " ~ ($errors_list|count) ~ " errors, " ~ $duree_s ~ "s"
    }
  }

  schedule = [{starts_on: 2026-02-08 02:00:00+0000, freq: 86400}]

  history = "inherit"
}
