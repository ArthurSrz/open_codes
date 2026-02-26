# Specification fonctionnelle : Generateur de documents administratifs IA

**Branche Feature** : `002-ai-doc-generator`
**Cree le** : 2026-02-06
**Statut** : Implemente
**Entree** : Description utilisateur : "Je veux que l'assistante Marianne puisse generer des arretes municipaux et autorisations administratives a partir de templates DOCX, en guidant le secretaire de mairie via un chatbot."

## Scenarios utilisateur & tests *(obligatoire)*

### User Story 1 - Generation guidee par chatbot (Priorite : P1)

En tant que secretaire de mairie, je veux que l'assistante Marianne me guide pas a pas pour remplir un arrete municipal afin de generer un document DOCX conforme sans connaitre la structure du template.

**Justification de la priorite** : C'est le cas d'usage principal. Les secretaires de mairie ne sont pas des juristes ; le chatbot elimine la complexite du remplissage de formulaires administratifs en posant des questions en langage naturel.

**Test Independant** : Demander a Marianne "Je veux faire un arrete de voirie", verifier qu'elle propose les templates disponibles, pose les questions une par une, interprete les reponses (dates en langage naturel, nombres), et genere un DOCX telechargeable avec tous les placeholders remplaces.

**Scenarios d'Acceptation** :

1. **Etant donne** un utilisateur connecte avec une commune configuree, **Quand** il demande a Marianne de generer un arrete, **Alors** l'outil MCP `genere_acte_administratif` liste les templates actifs (commune + globaux) et demande lequel utiliser
2. **Etant donne** un template selectionne, **Quand** l'outil demarre une session, **Alors** les donnees auto-fill (nom commune, departement, maire, tribunal administratif, date signature) sont pre-remplies et seuls les placeholders manuels sont poses en questions chatbot
3. **Etant donne** que toutes les donnees sont collectees, **Quand** l'utilisateur confirme la generation, **Alors** un DOCX est produit avec tous les `{{placeholders}}` remplaces, les caracteres XML echappes, et le fichier est persiste en base de donnees avec un lien de telechargement

---

### User Story 2 - Generation via API REST (Priorite : P2)

En tant que developpeur frontend WeWeb, je veux des endpoints REST pour lister les templates, demarrer une session, collecter les donnees et generer le document afin d'integrer la generation de documents dans l'interface WeWeb.

**Justification de la priorite** : L'API REST permet l'integration WeWeb et offre un controle programmatique complementaire au chatbot. Le frontend peut proposer une interface formulaire classique en plus du chatbot.

**Test Independant** : Appeler sequentiellement GET `/liste_templates_disponibles`, POST `/demarrer_generation_document`, POST `/collecter_donnees_chatbot` (pour chaque placeholder), puis POST `/generer_document_final`. Verifier que chaque endpoint retourne les donnees attendues et que le DOCX final est correct.

**Scenarios d'Acceptation** :

1. **Etant donne** un utilisateur authentifie par JWT, **Quand** il appelle GET `/liste_templates_disponibles`, **Alors** il recoit les templates actifs de sa commune + les templates globaux, fusionnes via deux queries separees (workaround `||`)
2. **Etant donne** une session de generation en cours, **Quand** il envoie un message utilisateur a POST `/collecter_donnees_chatbot` avec un type `date`, **Alors** Mistral interprete la date en langage naturel et retourne la valeur au format JJ/MM/AAAA
3. **Etant donne** une session avec toutes les donnees collectees, **Quand** il appelle POST `/generer_document_final`, **Alors** le pipeline DOCX two-copy s'execute, les placeholders sont remplaces dans `word/document.xml`, et le fichier est persiste via `storage.create_attachment`

---

### User Story 3 - Administration des templates (Priorite : P3)

En tant que gestionnaire de commune, je veux pouvoir creer, modifier, archiver et valider reglementairement des templates de documents administratifs afin de maintenir un referentiel a jour conforme au CGCT.

**Justification de la priorite** : L'administration des templates est necessaire pour la maintenance du systeme mais n'est pas requise pour l'utilisation quotidienne (les 3 templates initiaux suffisent pour le MVP).

**Test Independant** : Creer un template via POST `/creer_template` avec un DOCX contenant des `{{placeholders}}`, verifier l'auto-detection, modifier via PUT `/maj_template` (version incrementee, validation invalidee), valider via PATCH `/valider_template_reglementaire`, puis archiver via DELETE `/archiver_template` (soft-delete).

**Scenarios d'Acceptation** :

1. **Etant donne** un gestionnaire authentifie, **Quand** il uploade un DOCX avec des `{{placeholders}}` sans fournir de metadonnees, **Alors** le systeme extrait automatiquement les placeholders via regex sur `word/document.xml` et cree le template avec les metadonnees generees
2. **Etant donne** un template existant, **Quand** il est modifie (nom, fichier, placeholders), **Alors** la version est incrementee et le flag `valide_reglementairement` est remis a `false`
3. **Etant donne** un template archive, **Quand** un utilisateur tente de l'utiliser, **Alors** l'erreur "Ce template est archive" est retournee, mais les documents deja generes restent accessibles

---

### User Story 4 - Historique et tracabilite (Priorite : P4)

En tant qu'administrateur, je veux consulter l'historique des documents generes et les logs d'audit afin de garantir la tracabilite RGPD et faciliter le debogage.

**Justification de la priorite** : La tracabilite est une obligation RGPD mais n'est pas bloquante pour le fonctionnement initial du generateur.

**Test Independant** : Generer un document, puis verifier que GET `/historique_documents_generes` le liste avec pagination et filtrage par statut, que GET `/telecharger_document_genere` retourne le fichier et cree un log d'audit, et que la table `LOG_generation_documents` contient toutes les actions (generation, telechargement, validation).

**Scenarios d'Acceptation** :

1. **Etant donne** des documents generes, **Quand** l'utilisateur consulte l'historique, **Alors** il voit une liste paginee scopee a sa commune avec filtrage par statut (brouillon, finalise, signe)
2. **Etant donne** un telechargement de document, **Quand** il est effectue, **Alors** un enregistrement d'audit est cree dans `LOG_generation_documents` avec l'action "telechargement"
3. **Etant donne** une generation de document, **Quand** elle reussit, **Alors** un log avec `action_type: "generation"`, `statut: "succes"`, `placeholders_remplaces` et `duree_ms` est persiste

---

### Cas Limites

- Que se passe-t-il quand les placeholders `{{...}}` sont fragmentes sur plusieurs runs XML dans le DOCX ?
  - Les templates DOIVENT etre generes programmatiquement (via `python-docx` ou equivalent) pour garantir que chaque placeholder est dans un seul `<w:r>`. Si un template est edite manuellement dans Word, les placeholders fragmentes ne seront pas remplaces. Detection recommandee : verifier les `{{` non remplaces apres substitution.
- Que se passe-t-il quand une valeur de placeholder contient des caracteres speciaux XML (`&`, `<`, `>`) ?
  - Le pipeline echappe systematiquement les valeurs via `|replace:"&":"&amp;"|replace:"<":"&lt;"|replace:">":"&gt;"` avant insertion dans le XML.
- Que se passe-t-il quand Mistral retourne "INVALIDE" pour une date deja formatee JJ/MM/AAAA ?
  - Limitation connue : Mistral peut rejeter des dates deja au bon format. Workaround : les utilisateurs doivent fournir les dates en langage naturel. Amelioration future : pre-validation regex avant appel Mistral.
- Que se passe-t-il quand les donnees de la commune sont incompletes (maire_nom, tribunal_administratif manquants) ?
  - Les champs auto-fill utilisent `$commune.champ ?? ""` : les valeurs manquantes sont remplacees par une chaine vide. Le document est genere mais avec des champs vides visibles.
- Que se passe-t-il quand un utilisateur tente d'acceder a un template/document d'une autre commune ?
  - Chaque endpoint verifie `$document.communes_id == $user.communes_id` ou `$template.is_global`. L'erreur `accessdenied` est retournee pour les acces inter-communes non autorises.
- Que se passe-t-il quand `zip.create_archive` est appele ?
  - `zip.create_archive` provoque un crash fatal (erreur 500 irrecuperable). Le systeme utilise le pattern "two-copy" : copie `.docx` pour lecture, copie `.zip` pour ecriture, jamais de creation d'archive ex nihilo.

## Exigences *(obligatoire)*

### Exigences Fonctionnelles

- **EF-001** : Le systeme DOIT supporter 3 templates DOCX initiaux : Arrete de voirie (references L.2213-1, L.2213-6 CGCT), Arrete de police du maire (references L.2212-1, L.2212-2 CGCT), Permis de stationnement (references L.2213-1, L.2213-6 CGCT, L.2122-1 CGPPP)
- **EF-002** : Le systeme DOIT pre-remplir automatiquement les donnees de la commune (nom, departement, maire, tribunal administratif, date de signature) a partir de la table `communes` liee a l'utilisateur authentifie
- **EF-003** : Le systeme DOIT guider l'utilisateur via un chatbot IA (outil MCP `genere_acte_administratif`) pour collecter les donnees manquantes, en posant les questions definies dans les metadonnees `question_chatbot` de chaque placeholder
- **EF-004** : Le systeme DOIT utiliser Mistral AI (`mistral-small-latest`, temperature 0.1) pour interpreter les reponses en langage naturel : parsage de dates (format JJ/MM/AAAA), extraction de nombres, validation des entrees
- **EF-005** : Le systeme DOIT implementer le pipeline DOCX inline (pas de `function.run` imbrique) : telecharger template, creer deux copies (.docx lecture / .zip ecriture), extraire `word/document.xml`, remplacer les `{{placeholders}}`, reconstruire l'archive, persister via `storage.create_attachment`
- **EF-006** : Le systeme DOIT echapper les caracteres speciaux XML (`&` -> `&amp;`, `<` -> `&lt;`, `>` -> `&gt;`) dans toutes les valeurs substituees pour garantir la validite du document
- **EF-007** : Le systeme DOIT persister les fichiers DOCX generes via `storage.create_attachment` (et non `storage.create_file_resource` qui est ephemere) pour permettre le telechargement ulterieur
- **EF-008** : Tous les endpoints DOIVENT utiliser l'authentification JWT (`auth = "utilisateurs"`) et les endpoints d'administration DOIVENT verifier le flag `gestionnaire` ou le role `admin` via requete `db.get utilisateurs`
- **EF-009** : Toutes les requetes sur les documents et sessions DOIVENT etre scopees par `communes_id` pour garantir l'isolation des donnees entre communes
- **EF-010** : Le systeme DOIT journaliser toutes les operations (generation, telechargement, validation) dans la table `LOG_generation_documents` avec timestamp, utilisateur, session et statut
- **EF-011** : L'outil MCP `genere_acte_administratif` DOIT exposer 5 actions (`lister_templates`, `demarrer`, `collecter`, `generer`, `telecharger`) et retourner des instructions pour Mistral a chaque etape
- **EF-012** : L'archivage de template DOIT utiliser le soft-delete (flag `actif = false`) ; les documents deja generes a partir d'un template archive DOIVENT rester accessibles
- **EF-013** : La mise a jour d'un template DOIT incrementer la version et invalider le flag `valide_reglementairement` pour forcer une re-validation
- **EF-014** : Le systeme DOIT auto-detecter les placeholders d'un DOCX uploade via regex `\\{\\{(\\w+)\\}\\}` sur `word/document.xml` si les metadonnees ne sont pas fournies manuellement
- **EF-015** : Les champs `instruction` dans les reponses de l'outil MCP DOIVENT guider Mistral sur le comportement a adopter (poser la question suivante, informer l'utilisateur, fournir le lien de telechargement)

### Entites Cles

- **TemplateDocumentAdministratif** : Modele de document avec fichier DOCX, metadonnees placeholders (JSON), categorie, version, flag validation reglementaire, scope commune/global
  - Table : `templates_documents_administratifs` (ID Xano : 122)
  - Champs cles : `nom`, `description`, `categorie_id`, `communes_id`, `is_global`, `fichier_docx` (attachment), `placeholders` (JSON array), `version`, `actif`, `valide_reglementairement`, `cree_par`, `valide_par`

- **SessionGenerationDocument** : Session de travail liant un utilisateur a un template, stockant les donnees collectees progressivement
  - Table : `sessions_generation_documents` (ID Xano : 123)
  - Champs cles : `template_id`, `utilisateur_id`, `communes_id`, `statut` (en_cours/termine), `donnees_collectees` (JSON), `document_id`

- **DocumentGenere** : Document DOCX final genere, avec fichier persiste et metadonnees de substitution
  - Table : `documents_generes` (ID Xano : 124)
  - Champs cles : `template_id`, `utilisateur_id`, `session_id`, `communes_id`, `titre`, `donnees_substituees` (JSON), `statut` (brouillon/finalise/signe), `fichier_docx` (attachment)

- **LOGGenerationDocuments** : Journal d'audit de toutes les operations sur les documents
  - Table : `LOG_generation_documents` (ID Xano : 125)
  - Champs cles : `document_id`, `template_id`, `utilisateur_id`, `session_id`, `action_type`, `statut`, `placeholders_remplaces`, `duree_ms`

### Architecture API

| Groupe | ID | Endpoint | Verbe | Fichier | Description |
|--------|-----|----------|-------|---------|-------------|
| Doc Generator | 56 | `/liste_templates_disponibles` | GET | `914_liste_templates_disponibles_GET.xs` | Templates actifs (commune + globaux) |
| Doc Generator | 56 | `/demarrer_generation_document` | POST | `915_demarrer_generation_document_POST.xs` | Creer session, retourner questions |
| Doc Generator | 56 | `/collecter_donnees_chatbot` | POST | `916_collecter_donnees_chatbot_POST.xs` | Interpreter reponse Mistral, prochaine question |
| Doc Generator | 56 | `/generer_document_final` | POST | `917_generer_document_final_POST.xs` | Pipeline DOCX complet |
| Doc Generator | 56 | `/historique_documents_generes` | GET | `918_historique_documents_generes_GET.xs` | Liste paginee, scopee commune |
| Doc Generator | 56 | `/telecharger_document_genere` | GET | `919_telecharger_document_genere_GET.xs` | Retourner fichier + audit log |
| Admin Templates | 57 | `/creer_template` | POST | `920_creer_template_POST.xs` | Upload DOCX + auto-detection placeholders |
| Admin Templates | 57 | `/maj_template` | PUT | `921_maj_template_PUT.xs` | Modifier + incrementer version |
| Admin Templates | 57 | `/archiver_template` | DELETE | `922_archiver_template_DELETE.xs` | Soft-delete (actif=false) |
| Admin Templates | 57 | `/valider_template_reglementaire` | PATCH | `923_valider_template_reglementaire_PATCH.xs` | Valider conformite + audit log |
| MCP Tool | - | `genere_acte_administratif` | - | `tools/19_genere_acte_administratif.xs` | 5 actions chatbot (lister/demarrer/collecter/generer/telecharger) |

## Criteres de Succes *(obligatoire)*

### Resultats Mesurables

- **CS-001** : Les 3 templates DOCX (arrete voirie, arrete police maire, permis stationnement) sont deployes et operationnels avec tous les placeholders correctement definis
- **CS-002** : Le pipeline chatbot complet (lister -> demarrer -> collecter N questions -> generer -> telecharger) fonctionne de bout en bout via l'outil MCP
- **CS-003** : 100% des placeholders sont remplaces dans le DOCX genere (aucun `{{...}}` residuel visible)
- **CS-004** : Les donnees auto-fill (commune, maire, departement, tribunal, date) sont correctement pre-remplies sans intervention utilisateur
- **CS-005** : L'isolation par commune est effective : un utilisateur ne peut ni voir ni telecharger les documents d'une autre commune
- **CS-006** : Les caracteres speciaux XML dans les valeurs utilisateur ne corrompent pas le DOCX genere
- **CS-007** : Toutes les operations (generation, telechargement, validation) sont tracees dans `LOG_generation_documents`

## Clarifications

### Session 2026-02-06

- Q: Quel format de templates ? -> A: DOCX avec placeholders `{{nom_variable}}` dans le corps du document
- Q: Comment gerer le `||` (OR) non supporte dans XanoScript ? -> A: Split en 2 queries + `|merge:` pour les db.query ; conditional + flag pour les preconditions
- Q: Comment persister les fichiers generes ? -> A: `storage.create_attachment` (pas `create_file_resource` qui est ephemere)
- Q: Pourquoi un pipeline inline plutot que des fonctions ? -> A: XanoScript ne supporte pas les `function.run` imbriques (2+ niveaux) - tout doit etre inline dans l'API/tool
- Q: Comment manipuler le DOCX (ZIP) ? -> A: Pattern two-copy : `.docx` pour lecture (`zip.extract`), `.zip` pour ecriture (`zip.delete_from_archive` + `zip.add_to_archive`), car `zip.create_archive` est casse
- Q: Quel modele Mistral pour le parsage ? -> A: `mistral-small-latest` avec temperature 0.1 pour le parsage de dates et nombres

## Hypotheses

- Les templates DOCX sont generes programmatiquement pour garantir que les placeholders ne sont pas fragmentes sur plusieurs runs XML
- La table `communes` contient les champs `denomination`, `nom_dep`, `maire_nom`, `tribunal_administratif` pour l'auto-fill
- L'API Mistral AI est disponible pour le parsage en langage naturel des reponses chatbot
- Les gestionnaires sont identifies par le flag `gestionnaire = true` dans la table `utilisateurs`
- Le workspace Xano (ID: 5) est sur la branche `genere_template` avec les variables d'environnement `MISTRAL_API_KEY` configurees
- Les references legales (CGCT articles L.2212-1/2, L.2213-1/2/6) sont les bases juridiques correctes pour les arretes municipaux et autorisations de voirie

## References Legales

- **L.2212-1 CGCT** : Pouvoir de police generale du maire
- **L.2212-2 CGCT** : Competences de police municipale (ordre, surete, securite, salubrite publiques)
- **L.2213-1 CGCT** : Police de la circulation et du stationnement
- **L.2213-2 CGCT** : Reglementation de la circulation
- **L.2213-6 CGCT** : Police de la voirie
- **L.2122-1 CGPPP** : Occupation temporaire du domaine public
- **R.411-5 Code de la route** : Signalisation temporaire
- **R.610-5 Code penal** : Contravention pour non-respect d'un arrete municipal
