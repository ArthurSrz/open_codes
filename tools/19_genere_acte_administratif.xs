// Outil MCP: genere_acte_administratif
// Description: Outil exposé via le serveur MCP pour permettre à l'assistant Mistral
//   de guider l'utilisateur dans la génération d'un acte administratif.
//   Intègre le pipeline complet: sélection template → collecte données → génération DOCX.
//
// Flux chatbot:
// 1. L'utilisateur demande "Je veux faire un arrêté de voirie"
// 2. Mistral identifie le besoin et appelle cet outil
// 3. L'outil retourne les templates disponibles et les questions à poser
// 4. Mistral guide l'utilisateur question par question
// 5. Une fois les données collectées, l'outil génère le DOCX
//
// Learnings appliqués:
// - || (OR) remplacé par split queries + |merge: ou conditional + flag
// - object.entries returns {key, value} objects (NOT [key, value] arrays)
// - Two-copy DOCX pattern: .docx for reading, .zip for writing
// - zip ops need password="" and password_encryption=""
// - storage.create_attachment for DB persistence (NOT create_file_resource)
// - Key names 'action', 'act', 'action_type' may conflict → use 'etape', 'log_type'

tool genere_acte_administratif {
  input {
    // Action à effectuer: 'lister_templates', 'demarrer', 'collecter', 'generer', 'telecharger'
    text action

    // ID du template (requis pour demarrer/generer)
    int template_id?

    // ID de la session de génération (requis pour collecter/generer/telecharger)
    int session_id?

    // ID du placeholder à remplir (requis pour collecter)
    text placeholder_id?

    // Valeur fournie par l'utilisateur (requis pour collecter)
    text valeur?

    // ID du document (requis pour telecharger)
    int document_id?
  }

  stack {
    var $resultat {
      value = {}
    }

    db.get utilisateurs {
      field_name = "id"
      field_value = $auth.id
    } as $user

    db.get communes {
      field_name = "id"
      field_value = $user.commune_id
    } as $commune

    conditional {
      // === LISTER_TEMPLATES ===
      if ($input.action == "lister_templates") {
        db.query templates_documents_administratifs {
          where = $db.templates_documents_administratifs.actif == true && $db.templates_documents_administratifs.communes_id == $user.commune_id
          sort = {nom: "asc"}
          return = {type: "list", paging: {page: 1, per_page: 50}}
        } as $templates_commune

        db.query templates_documents_administratifs {
          where = $db.templates_documents_administratifs.actif == true && $db.templates_documents_administratifs.is_global == true
          sort = {nom: "asc"}
          return = {type: "list", paging: {page: 1, per_page: 50}}
        } as $templates_globaux

        var $templates {
          value = $templates_commune|merge:$templates_globaux
        }

        var $liste_texte {
          value = "Voici les modèles disponibles pour " ~ ($commune.denomination ?? "") ~ " :\n\n"
        }

        foreach ($templates) {
          each as $t {
            var.update $liste_texte {
              value = $liste_texte ~ "- **" ~ $t.nom ~ "** (ID: " ~ $t.id ~ ") : " ~ ($t.description ?? "") ~ "\n"
            }
          }
        }

        var.update $resultat {
          value = {
            etape      : "lister_templates"
            message    : $liste_texte
            templates  : $templates
            instruction: "Demandez à l'utilisateur quel type de document il souhaite générer."
          }
        }
      }

      // === DEMARRER ===
      elseif ($input.action == "demarrer") {
        precondition ($input.template_id > 0) {
          error_type = "badrequest"
          error = "template_id requis pour démarrer"
        }

        db.get templates_documents_administratifs {
          field_name = "id"
          field_value = $input.template_id
        } as $template

        precondition ($template != null && $template.actif) {
          error_type = "notfound"
          error = "Template non trouvé ou inactif"
        }

        db.add sessions_generation_documents {
          data = {
            template_id       : $input.template_id
            utilisateur_id    : $auth.id
            communes_id       : $user.commune_id
            statut            : "en_cours"
            donnees_collectees: {}
            created_at        : "now"
          }
        } as $session

        var $premiere_question {
          value = ""
        }

        var $premier_ph_id {
          value = ""
        }

        foreach ($template.placeholders) {
          each as $ph {
            conditional {
              if ($ph.auto_fill != true && $premiere_question == "") {
                var.update $premiere_question {
                  value = $ph.question_chatbot ?? ("Quelle est la valeur pour : " ~ $ph.label ~ " ?")
                }

                var.update $premier_ph_id {
                  value = $ph.id
                }
              }

              else {
                // skip
              }
            }
          }
        }

        var.update $resultat {
          value = {
            etape                 : "demarrer"
            session_id            : $session.id
            template_nom          : $template.nom
            premiere_question     : $premiere_question
            premier_placeholder_id: $premier_ph_id
            instruction           : "Posez la première question : " ~ $premiere_question
          }
        }
      }

      // === COLLECTER ===
      elseif ($input.action == "collecter") {
        precondition ($input.session_id > 0 && $input.placeholder_id != "" && $input.valeur != "") {
          error_type = "badrequest"
          error = "session_id, placeholder_id et valeur requis"
        }

        db.get sessions_generation_documents {
          field_name = "id"
          field_value = $input.session_id
        } as $session

        var $donnees {
          value = $session.donnees_collectees|set:$input.placeholder_id:$input.valeur
        }

        db.edit sessions_generation_documents {
          field_name = "id"
          field_value = $session.id
          data = {donnees_collectees: $donnees}
        } as $session_maj

        db.get templates_documents_administratifs {
          field_name = "id"
          field_value = $session.template_id
        } as $template

        var $prochaine_q {
          value = ""
        }

        var $prochain_ph {
          value = ""
        }

        var $complete {
          value = true
        }

        foreach ($template.placeholders) {
          each as $ph {
            conditional {
              if ($ph.auto_fill != true && !($donnees|has:($ph.id)) && $prochaine_q == "") {
                var.update $prochaine_q {
                  value = $ph.question_chatbot ?? ("Quelle est la valeur pour : " ~ $ph.label ~ " ?")
                }

                var.update $prochain_ph {
                  value = $ph.id
                }

                var.update $complete {
                  value = false
                }
              }

              else {
                // skip
              }
            }
          }
        }

        var $instruction_collecte {
          value = "Posez la question suivante : " ~ $prochaine_q
        }

        conditional {
          if ($complete) {
            var.update $instruction_collecte {
              value = "Toutes les données sont collectées. Demandez si l'utilisateur veut générer le document."
            }
          }

          else {
            // garder la valeur par défaut
          }
        }

        var.update $resultat {
          value = {
            etape                  : "collecter"
            session_id             : $input.session_id
            collecte_complete      : $complete
            prochaine_question     : $prochaine_q
            prochain_placeholder_id: $prochain_ph
            nb_collectes           : $donnees|count
            instruction            : $instruction_collecte
          }
        }
      }

      // === GENERER ===
      elseif ($input.action == "generer") {
        precondition ($input.session_id > 0) {
          error_type = "badrequest"
          error = "session_id requis"
        }

        db.get sessions_generation_documents {
          field_name = "id"
          field_value = $input.session_id
        } as $session

        db.get templates_documents_administratifs {
          field_name = "id"
          field_value = $session.template_id
        } as $template

        var $donnees_completes {
          value = $session.donnees_collectees
            |set:"commune_nom":$commune.denomination ?? ""
            |set:"departement_nom":$commune.nom_dep ?? ""
            |set:"maire_nom":$commune.maire_nom ?? ""
            |set:"tribunal_administratif":$commune.tribunal_administratif ?? ""
        }

        var $date_sig {
          value = now|format_timestamp:"d/m/Y"
        }

        var.update $donnees_completes {
          value = $donnees_completes|set:"date_signature":$date_sig
        }

        // DOCX PIPELINE (two-copy pattern)
        api.request {
          url = $template.fichier_docx.url
          method = "GET"
        } as $docx_dl

        storage.create_file_resource {
          filename = "read_copy.docx"
          filedata = $docx_dl.response.result
        } as $read_copy

        storage.create_file_resource {
          filename = "output.zip"
          filedata = $docx_dl.response.result
        } as $output_copy

        zip.extract {
          zip = $read_copy
          password = ""
        } as $extracted_files

        var $xml {
          value = ""
        }

        foreach ($extracted_files) {
          each as $f {
            conditional {
              if ($f.name == "word/document.xml") {
                storage.read_file_resource {
                  value = $f.resource
                } as $read_result

                var.update $xml {
                  value = $read_result.data
                }
              }

              else {
                // skip
              }
            }
          }
        }

        // Replace placeholders (object.entries returns {key, value} objects)
        object.entries {
          value = $donnees_completes
        } as $donnees_entries

        foreach ($donnees_entries) {
          each as $e {
            var $ph_tag {
              value = "{{" ~ $e.key ~ "}}"
            }

            var $val_safe {
              value = ($e.value ~ "")|replace:"&":"&amp;"|replace:"<":"&lt;"|replace:">":"&gt;"
            }

            var.update $xml {
              value = $xml|replace:$ph_tag:$val_safe
            }
          }
        }

        // Rebuild DOCX
        zip.delete_from_archive {
          filename = "word/document.xml"
          zip = $output_copy
          password = ""
        }

        storage.create_file_resource {
          filename = "document.xml"
          filedata = $xml
        } as $xml_file

        zip.add_to_archive {
          file = $xml_file
          filename = "word/document.xml"
          zip = $output_copy
          password = ""
          password_encryption = ""
        }

        // Persist attachment
        storage.create_attachment {
          value = $output_copy
          access = "public"
          filename = "document_genere.docx"
        } as $docx_attachment

        var $titre {
          value = $template.nom ~ " - " ~ ($commune.denomination ?? "") ~ " - " ~ $date_sig
        }

        db.add documents_generes {
          data = {
            template_id        : $session.template_id
            utilisateur_id     : $auth.id
            session_id         : $session.id
            communes_id        : $user.commune_id
            titre              : $titre
            donnees_substituees: $donnees_completes
            statut             : "brouillon"
            fichier_docx       : $docx_attachment
            created_at         : "now"
          }
        } as $document

        db.edit sessions_generation_documents {
          field_name = "id"
          field_value = $session.id
          data = {statut: "termine", document_id: $document.id}
        } as $s

        db.add LOG_generation_documents {
          data = {
            document_id   : $document.id
            template_id   : $session.template_id
            utilisateur_id: $auth.id
            session_id    : $session.id
            log_type      : "generation"
            log_statut    : "succes"
            created_at    : "now"
          }
        } as $log

        var.update $resultat {
          value = {
            etape      : "generer"
            document_id: $document.id
            titre      : $titre
            message    : "Le document a été généré avec succès."
            instruction: "Informez l'utilisateur que le document est prêt et proposez le téléchargement."
          }
        }
      }

      // === TELECHARGER ===
      elseif ($input.action == "telecharger") {
        precondition ($input.document_id > 0) {
          error_type = "badrequest"
          error = "document_id requis"
        }

        db.get documents_generes {
          field_name = "id"
          field_value = $input.document_id
        } as $doc

        precondition ($doc != null && $doc.communes_id == $user.commune_id) {
          error_type = "accessdenied"
          error = "Document non trouvé ou accès refusé"
        }

        var.update $resultat {
          value = {
            etape             : "telecharger"
            document_id       : $doc.id
            titre             : $doc.titre
            url_telechargement: $doc.fichier_docx.url
            instruction       : "Fournissez le lien de téléchargement à l'utilisateur."
          }
        }
      }

      else {
        var.update $resultat {
          value = {
            error              : "Action inconnue: " ~ $input.action
            actions_disponibles: ["lister_templates", "demarrer", "collecter", "generer", "telecharger"]
          }
        }
      }
    }
  }

  response = $resultat
}
