// API Group: admin_templates
// Description: Administration des templates de documents (gestionnaires uniquement)
// Auth: JWT (utilisateurs) + vérification rôle gestionnaire
// Base path: /api/admin_templates

api_group "admin_templates" {
  description = "Administration des templates de documents administratifs - Réservé aux gestionnaires"
  auth = "utilisateurs"
}
