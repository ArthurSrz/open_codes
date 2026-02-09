// API: Valider un template réglementairement
// Endpoint: PATCH /api/admin_templates/valider_template_reglementaire
// Auth: JWT utilisateurs + gestionnaire
// Description: Marque un template comme validé pour conformité réglementaire

query "admin_templates/valider_template_reglementaire" verb=PATCH {
  api_group = "admin_templates"
  auth = "utilisateurs"
  description = "Valide un template pour conformité réglementaire"

  input {
    int template_id {
      description = "ID du template à valider"
    }
    text commentaire_validation?="" {
      description = "Commentaire de validation (optionnel)"
    }
  }

  stack {
    db.get "utilisateurs" {
      field_name = "id"
      field_value = $auth.id
    } as $user

    precondition ($user.gestionnaire == true || $user.role == "admin") {
      error_type = "accessdenied"
      error = "Accès réservé aux gestionnaires"
    }

    db.get "templates_documents_administratifs" {
      field_name = "id"
      field_value = $input.template_id
    } as $template

    precondition ($template != null) {
      error_type = "notfound"
      error = "Template non trouvé"
    }

    // Marquer comme validé
    db.edit "templates_documents_administratifs" {
      field_name = "id"
      field_value = $input.template_id
      data = {
        valide_reglementairement: true,
        valide_par: $auth.id,
        date_validation: "now",
        commentaire_validation: $input.commentaire_validation
      }
    } as $validated

    // Audit log
    db.add LOG_generation_documents {
      data = {
        template_id: $input.template_id,
        utilisateur_id: $auth.id,
        action: "validation_reglementaire",
        statut: "succes",
        details: $input.commentaire_validation,
        created_at: "now"
      }
    } as $log

    var $result {
      value = {
        template_id: $input.template_id,
        valide_reglementairement: true,
        valide_par: $user.prenom ~ " " ~ $user.nom,
        message: "Template validé réglementairement."
      }
    }
  }

  response = $result
}
