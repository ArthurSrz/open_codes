// API: Mettre à jour un template
// Endpoint: PUT /api/admin_templates/maj_template
// Auth: JWT utilisateurs + gestionnaire

query "admin_templates/maj_template" verb=PUT {
  api_group = "admin_templates"
  auth = "utilisateurs"
  description = "Met à jour un template existant (incrémente la version)"

  input {
    int template_id {
      description = "ID du template à modifier"
    }
    text nom?="" {
      description = "Nouveau nom (vide = inchangé)"
    }
    text description?="" {
      description = "Nouvelle description"
    }
    int categorie_id?=0 {
      description = "Nouvelle catégorie (0 = inchangé)"
    }
    attachment fichier_docx?=null {
      description = "Nouveau fichier DOCX (null = inchangé)"
    }
    json placeholders?=[] {
      description = "Nouvelles métadonnées placeholders"
    }
  }

  stack {
    // Vérifier gestionnaire
    db.get "utilisateurs" {
      field_name = "id"
      field_value = $auth.id
    } as $user

    precondition ($user.gestionnaire == true || $user.role == "admin") {
      error_type = "accessdenied"
      error = "Accès réservé aux gestionnaires"
    }

    // Récupérer le template
    db.get "templates_documents_administratifs" {
      field_name = "id"
      field_value = $input.template_id
    } as $template

    precondition ($template != null) {
      error_type = "notfound"
      error = "Template non trouvé"
    }

    // Vérifier accès commune
    precondition ($template.communes_id == $user.communes_id || $user.role == "admin") {
      error_type = "accessdenied"
      error = "Ce template n'appartient pas à votre commune"
    }

    // Préparer les données de mise à jour
    var $data_update {
      value = {
        version: ($template.version + 1),
        valide_reglementairement: false,
        modifie_par: $auth.id,
        updated_at: "now"
      }
    }

    conditional {
      if ($input.nom != "") {
        var.update $data_update {
          value = $data_update|set:"nom":$input.nom
        }
      }
      else {
        // Nom inchangé
      }
    }

    conditional {
      if ($input.description != "") {
        var.update $data_update {
          value = $data_update|set:"description":$input.description
        }
      }
      else {
        // Description inchangée
      }
    }

    conditional {
      if ($input.categorie_id > 0) {
        var.update $data_update {
          value = $data_update|set:"categorie_id":$input.categorie_id
        }
      }
      else {
        // Catégorie inchangée
      }
    }

    conditional {
      if ($input.fichier_docx != null) {
        var.update $data_update {
          value = $data_update|set:"fichier_docx":$input.fichier_docx
        }
      }
      else {
        // Fichier inchangé
      }
    }

    conditional {
      if (($input.placeholders|count) > 0) {
        var.update $data_update {
          value = $data_update|set:"placeholders":$input.placeholders
        }
      }
      else {
        // Placeholders inchangés
      }
    }

    db.edit "templates_documents_administratifs" {
      field_name = "id"
      field_value = $input.template_id
      data = $data_update
    } as $updated

    var $result {
      value = {
        template_id: $input.template_id,
        version: ($template.version + 1),
        message: "Template mis à jour (v" ~ ($template.version + 1) ~ "). Validation réglementaire requise."
      }
    }
  }

  response = $result
}
