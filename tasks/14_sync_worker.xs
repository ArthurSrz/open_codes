// Task: sync_worker
// Purpose: Processes ONE article from QUEUE_sync per run
// Architecture: Polls queue every 4s, fetches article, hashes, upserts, chunks+embeds
// Constraint: No foreach+function.run — chunk embedding is UNROLLED (10 explicit blocks)
// Schedule: Every 4 seconds (continuous)

task "sync_worker" {
  description = "Traite UN article de la file QUEUE_sync par exécution. Récupère l'article PISTE, vérifie le hash, upsert dans REF_codes_legifrance, découpe en chunks et génère les embeddings."

  stack {
    // ═══════════════════════════════════════════════════════════════
    // POLL: Get next pending item from queue
    // ═══════════════════════════════════════════════════════════════
    db.query "QUEUE_sync" {
      where = $db.QUEUE_sync.status == "pending"
      sort = {id: "asc"}
      return = {
        type: "list"
        paging: {page: 1, per_page: 1}
      }
      description = "Get oldest pending queue item"
    } as $queue_items

    // No-op if queue is empty
    conditional {
      if (($queue_items|count) == 0) {
        debug.log {
          value = "No pending items in queue"
        }

        return {
          value = "idle"
        }
      }
    }

    var $item {
      value = $queue_items|first
      description = "Current queue item to process"
    }

    // ═══════════════════════════════════════════════════════════════
    // LOCK: Mark as processing
    // ═══════════════════════════════════════════════════════════════
    db.edit "QUEUE_sync" {
      field_name = "id"
      field_value = $item.id
      data = {
        status: "processing"
        processed_at: "now"
      }
      description = "Lock queue item"
    }

    // ═══════════════════════════════════════════════════════════════
    // MAIN PROCESSING (wrapped in try_catch)
    // ═══════════════════════════════════════════════════════════════
    try_catch {
      try {
        // OAuth inline
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
          error = "OAuth failed: " ~ $oauth_result.response.status
        }

        var $the_token {
          value = $oauth_result.response.result.access_token
        }

        // Fetch article from PISTE
        function.run "piste/piste_get_article" {
          input = {api_token: $the_token, article_id: $item.article_id_legifrance}
        } as $article

        // Hash check for change detection
        function.run "utils/hash_contenu_article" {
          input = {
            fullSectionsTitre: $article.fullSectionsTitre ?? ""
            surtitre: $article.surtitre ?? ""
            texte: $article.texte ?? ""
          }
        } as $hash_result

        // Check if article already exists
        db.get "REF_codes_legifrance" {
          field_name = "id_legifrance"
          field_value = $item.article_id_legifrance
          description = "Check existing article"
        } as $existing

        // Skip if hash unchanged
        conditional {
          if ($existing != null && $existing.content_hash == $hash_result.hash) {
            db.edit "QUEUE_sync" {
              field_name = "id"
              field_value = $item.id
              data = {
                status: "unchanged"
                chunks_count: 0
              }
              description = "Mark unchanged"
            }

            debug.log {
              value = "Unchanged: " ~ $item.article_id_legifrance
            }

            return {
              value = "unchanged"
            }
          }
        }

        // Parse hierarchy
        function.run "utils/parser_fullSectionsTitre" {
          input = {fullSectionsTitre: $article.fullSectionsTitre ?? ""}
        } as $hierarchy

        // ═══════════════════════════════════════════════════════════
        // UPSERT article in REF_codes_legifrance
        // Data MUST be inlined — db.add rejects variable refs (assign:var error)
        // Chunk cleanup: "always add, cleanup later" — no db.delete in XanoScript
        // ═══════════════════════════════════════════════════════════
        var $article_ref_id {
          value = 0
          description = "ID of the upserted article record"
        }

        conditional {
          if ($existing == null) {
            db.add REF_codes_legifrance {
              data = {
                id_legifrance: $item.article_id_legifrance
                code: $item.code_textId
                num: $article.num ?? ""
                cid: $article.cid ?? ""
                idEli: $article.idEli ?? ""
                idEliAlias: $article.idEliAlias ?? ""
                idTexte: $article.idTexte ?? ""
                cidTexte: $article.cidTexte ?? ""
                texte: $article.texte ?? ""
                texteHtml: $article.texteHtml ?? ""
                nota: $article.nota ?? ""
                notaHtml: $article.notaHtml ?? ""
                surtitre: $article.surtitre ?? ""
                historique: $article.historique ?? ""
                dateDebut: $article.dateDebut ?? null
                dateFin: $article.dateFin ?? null
                dateDebutExtension: $article.dateDebutExtension ?? null
                dateFinExtension: $article.dateFinExtension ?? null
                etat: $article.etat ?? ""
                type_article: $article.type ?? ""
                nature: $article.nature ?? ""
                origine: $article.origine ?? ""
                version_article: $article.versionArticle ?? ""
                versionPrecedente: $article.versionPrecedente ?? ""
                multipleVersions: $article.isMultipleVersions ?? false
                sectionParentId: $article.sectionParentId ?? ""
                sectionParentCid: $article.sectionParentCid ?? ""
                sectionParentTitre: $article.sectionParentTitre ?? ""
                fullSectionsTitre: $article.fullSectionsTitre ?? ""
                ordre: $article.ordre ?? null
                partie: $hierarchy.partie ?? ""
                livre: $hierarchy.livre ?? ""
                titre: $hierarchy.titre ?? ""
                chapitre: $hierarchy.chapitre ?? ""
                section: $hierarchy.section ?? ""
                sous_section: $hierarchy.sous_section ?? ""
                paragraphe: $hierarchy.paragraphe ?? ""
                infosComplementaires: $article.infosComplementaires ?? ""
                infosComplementairesHtml: $article.infosComplementairesHtml ?? ""
                conditionDiffere: $article.conditionDiffere ?? ""
                infosRestructurationBranche: $article.infosRestructurationBranche ?? ""
                infosRestructurationBrancheHtml: $article.infosRestructurationBrancheHtml ?? ""
                renvoi: $article.renvoi ?? ""
                comporteLiensSP: $article.comporteLiensSP ?? false
                idTechInjection: $article.idTechInjection ?? ""
                refInjection: $article.refInjection ?? ""
                numeroBo: $article.numeroBo ?? ""
                inap: $article.inap ?? ""
                content_hash: $hash_result.hash
                last_sync_at: "now"
              }
              description = "Insert new article"
            } as $new_record

            var.update $article_ref_id {
              value = $new_record.id
            }
          }

          else {
            db.edit "REF_codes_legifrance" {
              field_name = "id"
              field_value = $existing.id
              data = {
                id_legifrance: $item.article_id_legifrance
                code: $item.code_textId
                num: $article.num ?? ""
                cid: $article.cid ?? ""
                idEli: $article.idEli ?? ""
                idEliAlias: $article.idEliAlias ?? ""
                idTexte: $article.idTexte ?? ""
                cidTexte: $article.cidTexte ?? ""
                texte: $article.texte ?? ""
                texteHtml: $article.texteHtml ?? ""
                nota: $article.nota ?? ""
                notaHtml: $article.notaHtml ?? ""
                surtitre: $article.surtitre ?? ""
                historique: $article.historique ?? ""
                dateDebut: $article.dateDebut ?? null
                dateFin: $article.dateFin ?? null
                dateDebutExtension: $article.dateDebutExtension ?? null
                dateFinExtension: $article.dateFinExtension ?? null
                etat: $article.etat ?? ""
                type_article: $article.type ?? ""
                nature: $article.nature ?? ""
                origine: $article.origine ?? ""
                version_article: $article.versionArticle ?? ""
                versionPrecedente: $article.versionPrecedente ?? ""
                multipleVersions: $article.isMultipleVersions ?? false
                sectionParentId: $article.sectionParentId ?? ""
                sectionParentCid: $article.sectionParentCid ?? ""
                sectionParentTitre: $article.sectionParentTitre ?? ""
                fullSectionsTitre: $article.fullSectionsTitre ?? ""
                ordre: $article.ordre ?? null
                partie: $hierarchy.partie ?? ""
                livre: $hierarchy.livre ?? ""
                titre: $hierarchy.titre ?? ""
                chapitre: $hierarchy.chapitre ?? ""
                section: $hierarchy.section ?? ""
                sous_section: $hierarchy.sous_section ?? ""
                paragraphe: $hierarchy.paragraphe ?? ""
                infosComplementaires: $article.infosComplementaires ?? ""
                infosComplementairesHtml: $article.infosComplementairesHtml ?? ""
                conditionDiffere: $article.conditionDiffere ?? ""
                infosRestructurationBranche: $article.infosRestructurationBranche ?? ""
                infosRestructurationBrancheHtml: $article.infosRestructurationBrancheHtml ?? ""
                renvoi: $article.renvoi ?? ""
                comporteLiensSP: $article.comporteLiensSP ?? false
                idTechInjection: $article.idTechInjection ?? ""
                refInjection: $article.refInjection ?? ""
                numeroBo: $article.numeroBo ?? ""
                inap: $article.inap ?? ""
                content_hash: $hash_result.hash
                last_sync_at: "now"
              }
              description = "Update existing article"
            }

            var.update $article_ref_id {
              value = $existing.id
            }
          }
        }

        // ═══════════════════════════════════════════════════════════
        // CHUNK + EMBED (unrolled — no foreach+function.run)
        // ═══════════════════════════════════════════════════════════
        var $texte_complet {
          value = $article.texte ?? ""
        }

        var $chunk_count {
          value = 0
          description = "Number of chunks processed"
        }

        conditional {
          if (($texte_complet|strlen) > 0) {
            function.run "utils/chunker_texte" {
              input = {texte: $texte_complet}
            } as $chunks

            var.update $chunk_count {
              value = ($chunks|count)
            }

            // $article_ref_id already set by upsert conditional above

            // ─── CHUNK 0 ───
            conditional {
              if ($chunk_count >= 1) {
                function.run "mistral/mistral_generer_embedding" {
                  input = {texte: $chunks[0].text}
                } as $emb_0

                db.add REF_article_chunks {
                  data = {
                    article_id: $article_ref_id
                    id_legifrance: $item.article_id_legifrance
                    chunk_index: 0
                    chunk_text: $chunks[0].text
                    start_position: $chunks[0].start
                    end_position: $chunks[0].end
                    embedding: $emb_0
                  }
                  description = "Store chunk 0"
                }

                util.sleep {
                  value = 250
                  description = "Rate limit Mistral"
                }
              }
            }

            // ─── CHUNK 1 ───
            conditional {
              if ($chunk_count >= 2) {
                function.run "mistral/mistral_generer_embedding" {
                  input = {texte: $chunks[1].text}
                } as $emb_1

                db.add REF_article_chunks {
                  data = {
                    article_id: $article_ref_id
                    id_legifrance: $item.article_id_legifrance
                    chunk_index: 1
                    chunk_text: $chunks[1].text
                    start_position: $chunks[1].start
                    end_position: $chunks[1].end
                    embedding: $emb_1
                  }
                  description = "Store chunk 1"
                }

                util.sleep {
                  value = 250
                  description = "Rate limit Mistral"
                }
              }
            }

            // ─── CHUNK 2 ───
            conditional {
              if ($chunk_count >= 3) {
                function.run "mistral/mistral_generer_embedding" {
                  input = {texte: $chunks[2].text}
                } as $emb_2

                db.add REF_article_chunks {
                  data = {
                    article_id: $article_ref_id
                    id_legifrance: $item.article_id_legifrance
                    chunk_index: 2
                    chunk_text: $chunks[2].text
                    start_position: $chunks[2].start
                    end_position: $chunks[2].end
                    embedding: $emb_2
                  }
                  description = "Store chunk 2"
                }

                util.sleep {
                  value = 250
                  description = "Rate limit Mistral"
                }
              }
            }

            // ─── CHUNK 3 ───
            conditional {
              if ($chunk_count >= 4) {
                function.run "mistral/mistral_generer_embedding" {
                  input = {texte: $chunks[3].text}
                } as $emb_3

                db.add REF_article_chunks {
                  data = {
                    article_id: $article_ref_id
                    id_legifrance: $item.article_id_legifrance
                    chunk_index: 3
                    chunk_text: $chunks[3].text
                    start_position: $chunks[3].start
                    end_position: $chunks[3].end
                    embedding: $emb_3
                  }
                  description = "Store chunk 3"
                }

                util.sleep {
                  value = 250
                  description = "Rate limit Mistral"
                }
              }
            }

            // ─── CHUNK 4 ───
            conditional {
              if ($chunk_count >= 5) {
                function.run "mistral/mistral_generer_embedding" {
                  input = {texte: $chunks[4].text}
                } as $emb_4

                db.add REF_article_chunks {
                  data = {
                    article_id: $article_ref_id
                    id_legifrance: $item.article_id_legifrance
                    chunk_index: 4
                    chunk_text: $chunks[4].text
                    start_position: $chunks[4].start
                    end_position: $chunks[4].end
                    embedding: $emb_4
                  }
                  description = "Store chunk 4"
                }

                util.sleep {
                  value = 250
                  description = "Rate limit Mistral"
                }
              }
            }

            // ─── CHUNK 5 ───
            conditional {
              if ($chunk_count >= 6) {
                function.run "mistral/mistral_generer_embedding" {
                  input = {texte: $chunks[5].text}
                } as $emb_5

                db.add REF_article_chunks {
                  data = {
                    article_id: $article_ref_id
                    id_legifrance: $item.article_id_legifrance
                    chunk_index: 5
                    chunk_text: $chunks[5].text
                    start_position: $chunks[5].start
                    end_position: $chunks[5].end
                    embedding: $emb_5
                  }
                  description = "Store chunk 5"
                }

                util.sleep {
                  value = 250
                  description = "Rate limit Mistral"
                }
              }
            }

            // ─── CHUNK 6 ───
            conditional {
              if ($chunk_count >= 7) {
                function.run "mistral/mistral_generer_embedding" {
                  input = {texte: $chunks[6].text}
                } as $emb_6

                db.add REF_article_chunks {
                  data = {
                    article_id: $article_ref_id
                    id_legifrance: $item.article_id_legifrance
                    chunk_index: 6
                    chunk_text: $chunks[6].text
                    start_position: $chunks[6].start
                    end_position: $chunks[6].end
                    embedding: $emb_6
                  }
                  description = "Store chunk 6"
                }

                util.sleep {
                  value = 250
                  description = "Rate limit Mistral"
                }
              }
            }

            // ─── CHUNK 7 ───
            conditional {
              if ($chunk_count >= 8) {
                function.run "mistral/mistral_generer_embedding" {
                  input = {texte: $chunks[7].text}
                } as $emb_7

                db.add REF_article_chunks {
                  data = {
                    article_id: $article_ref_id
                    id_legifrance: $item.article_id_legifrance
                    chunk_index: 7
                    chunk_text: $chunks[7].text
                    start_position: $chunks[7].start
                    end_position: $chunks[7].end
                    embedding: $emb_7
                  }
                  description = "Store chunk 7"
                }

                util.sleep {
                  value = 250
                  description = "Rate limit Mistral"
                }
              }
            }

            // ─── CHUNK 8 ───
            conditional {
              if ($chunk_count >= 9) {
                function.run "mistral/mistral_generer_embedding" {
                  input = {texte: $chunks[8].text}
                } as $emb_8

                db.add REF_article_chunks {
                  data = {
                    article_id: $article_ref_id
                    id_legifrance: $item.article_id_legifrance
                    chunk_index: 8
                    chunk_text: $chunks[8].text
                    start_position: $chunks[8].start
                    end_position: $chunks[8].end
                    embedding: $emb_8
                  }
                  description = "Store chunk 8"
                }

                util.sleep {
                  value = 250
                  description = "Rate limit Mistral"
                }
              }
            }

            // ─── CHUNK 9 ───
            conditional {
              if ($chunk_count >= 10) {
                function.run "mistral/mistral_generer_embedding" {
                  input = {texte: $chunks[9].text}
                } as $emb_9

                db.add REF_article_chunks {
                  data = {
                    article_id: $article_ref_id
                    id_legifrance: $item.article_id_legifrance
                    chunk_index: 9
                    chunk_text: $chunks[9].text
                    start_position: $chunks[9].start
                    end_position: $chunks[9].end
                    embedding: $emb_9
                  }
                  description = "Store chunk 9"
                }
              }
            }
          }
        }

        // ═══════════════════════════════════════════════════════════
        // SUCCESS: Mark queue item as done
        // ═══════════════════════════════════════════════════════════
        db.edit "QUEUE_sync" {
          field_name = "id"
          field_value = $item.id
          data = {
            status: "done"
            chunks_count: $chunk_count
          }
          description = "Mark done"
        }

        debug.log {
          value = "Done: " ~ $item.article_id_legifrance ~ " (" ~ $chunk_count ~ " chunks)"
        }
      }

      catch {
        // ERROR: Mark queue item as error
        db.edit "QUEUE_sync" {
          field_name = "id"
          field_value = $item.id
          data = {
            status: "error"
            error_message: $error
          }
          description = "Mark error"
        }

        debug.log {
          value = "Error on " ~ $item.article_id_legifrance ~ ": " ~ $error
        }
      }
    }
  }

  schedule = [{starts_on: 2026-02-08 02:01:00+0000, freq: 4}]

  history = "inherit"
}
