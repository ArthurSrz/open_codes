// API: Démarrer une session de génération de document
// Endpoint: POST /api/doc_generator/demarrer_generation_document
// Auth: JWT utilisateurs
// Description: Crée une session de génération et retourne les infos du template
//   avec les questions chatbot à poser
//   Note: || remplacé par conditional + flag $has_access

query "doc_generator/demarrer_generation_document" verb=POST {
  api_group = "Doc Generator"
  auth = "utilisateurs"

  input {
    int template_id
  }

  stack {
    db.get utilisateurs {
      field_name = "id"
      field_value = $auth.id
    } as $user

    db.get communes {
      field_name = "id"
      field_value = $user.commune_id
    } as $commune

    db.get templates_documents_administratifs {
      field_name = "id"
      field_value = $input.template_id
    } as $template

    precondition ($template != null) {
      error_type = "notfound"
      error = "Template non trouvé"
    }

    precondition ($template.actif) {
      error_type = "badrequest"
      error = "Ce template est archivé"
    }

    // Vérifier accès: commune ou global (pas de || dans precondition)
    var $has_access {
      value = false
    }

    conditional {
      if ($template.is_global) {
        var.update $has_access {
          value = true
        }
      }

      elseif ($template.communes_id == $user.commune_id) {
        var.update $has_access {
          value = true
        }
      }

      else {
        // pas d'accès
      }
    }

    precondition ($has_access) {
      error_type = "accessdenied"
      error = "Vous n avez pas accès à ce template"
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

    var $date_sig {
      value = now|format_timestamp:"d/m/Y"
    }

    var $donnees_auto {
      value = {
        commune_nom           : ($commune.denomination ?? "")
        departement_nom       : ($commune.nom_dep ?? "")
        maire_nom             : ($commune.maire_nom ?? "")
        tribunal_administratif: ($commune.tribunal_administratif ?? "")
        date_signature        : $date_sig
      }
    }

    var $placeholders_a_collecter {
      value = []
    }

    foreach ($template.placeholders) {
      each as $ph {
        conditional {
          if ($ph.auto_fill != true) {
            var.update $placeholders_a_collecter {
              value = $placeholders_a_collecter|push:$ph
            }
          }

          else {
            // Auto-filled
          }
        }
      }
    }

    var $premiere_q {
      value = ""
    }

    var $first_ph {
      value = $placeholders_a_collecter|first
    }

    conditional {
      if ($first_ph != null) {
        var.update $premiere_q {
          value = $first_ph.question_chatbot ?? ("Quelle est la valeur pour : " ~ $first_ph.label ~ " ?")
        }
      }

      else {
        // Aucun placeholder à collecter
      }
    }

    var $result {
      value = {
        session_id              : $session.id
        template                : {id: $template.id, nom: $template.nom, description: $template.description}
        donnees_auto            : $donnees_auto
        placeholders_a_collecter: $placeholders_a_collecter
        total_questions         : $placeholders_a_collecter|count
        premiere_question       : $premiere_q
      }
    }
  }

  response = $result
}
