// API: Archiver un template (soft-delete)
// Endpoint: DELETE /api/admin_templates/archiver_template
// Auth: JWT utilisateurs + gestionnaire

query "admin_templates/archiver_template" verb=DELETE {
  api_group = "admin_templates"
  auth = "utilisateurs"
  description = "Archive un template (soft-delete, pas de suppression physique)"

  input {
    int template_id {
      description = "ID du template à archiver"
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

    precondition ($template.communes_id == $user.communes_id || $user.role == "admin") {
      error_type = "accessdenied"
      error = "Ce template n'appartient pas à votre commune"
    }

    // Soft-delete: marquer comme inactif
    db.edit "templates_documents_administratifs" {
      field_name = "id"
      field_value = $input.template_id
      data = {
        actif: false,
        archive_par: $auth.id,
        archived_at: "now"
      }
    } as $archived

    var $result {
      value = {
        template_id: $input.template_id,
        message: "Template archivé avec succès. Les documents déjà générés restent accessibles."
      }
    }
  }

  response = $result
}
