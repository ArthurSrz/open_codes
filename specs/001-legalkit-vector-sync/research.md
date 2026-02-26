# Research: Pipeline LegalKit → Vecteurs

**Date**: 2026-01-24
**Branche**: `001-legalkit-vector-sync`

## Décision 1 : Source de données

**Décision** : API PISTE directe (Légifrance officiel)

**Rationale** :
- Les datasets HuggingFace louisbrulenaudet n'ont pas été mis à jour depuis 6 mois (dernière màj : septembre 2025)
- L'API PISTE fournit des données en temps réel depuis la source officielle Légifrance
- Contrôle total sur la fraîcheur des données (on-demand ou planifié)

**Alternatives rejetées** :
- HuggingFace datasets : données obsolètes (6 mois de retard)
- GitHub legalkit-pipeline externe : ajout de complexité (Python runtime externe)

## Décision 2 : Runtime d'exécution

**Décision** : XanoScript natif

**Rationale** :
- Aucune dépendance externe requise
- Utilise l'infrastructure Xano existante (tasks, functions, external.oauth)
- Planification native via le système de tasks Xano
- Maintenance simplifiée (un seul environnement)

**Alternatives rejetées** :
- Cloud Run/Lambda + Xano API : complexité infra supplémentaire
- GitHub Actions schedulé : dépendance externe, latence de synchronisation

## Décision 3 : Stratégie d'extension de schéma

**Décision** : Extension de la table REF_codes_legifrance existante

**Rationale** :
- La table existe déjà avec 11 colonnes de base
- Ajout de ~30 colonnes pour les métadonnées LegalKit complètes
- Préserve la compatibilité avec les requêtes existantes
- Index vectoriel déjà configuré (`vector_ip_ops`)

**Colonnes à ajouter** :
| Groupe | Champs |
|--------|--------|
| Identification | `id_legifrance`, `cid`, `idEli`, `idEliAlias`, `idTexte`, `cidTexte` |
| Contenu | `texteHtml`, `nota`, `notaHtml`, `surtitre`, `historique` |
| Temporalité | `dateDebut`, `dateFin`, `dateDebutExtension`, `dateFinExtension` |
| Statut | `etat`, `type_article`, `nature`, `origine` |
| Versioning | `version_article`, `versionPrecedente`, `multipleVersions` |
| Hiérarchie | `sectionParentId`, `sectionParentCid`, `sectionParentTitre`, `fullSectionsTitre`, `ordre` |
| Technique | `idTechInjection`, `refInjection`, `numeroBo`, `inap` |
| Complémentaires | `infosComplementaires`, `infosComplementairesHtml`, `conditionDiffere`, `infosRestructurationBranche`, `infosRestructurationBrancheHtml`, `renvoi`, `comporteLiensSP` |
| Sync | `content_hash`, `last_sync_at` |

## API PISTE - Référence technique

### Endpoints

| Endpoint | URL | Usage |
|----------|-----|-------|
| OAuth Token | `https://oauth.piste.gouv.fr/api/oauth/token` | Authentification client_credentials |
| Table des matières | `https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/consult/legi/tableMatieres` | Structure d'un code juridique |
| Article | `https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/consult/getArticle` | Contenu détaillé d'un article |

### Authentification OAuth2

```
POST https://oauth.piste.gouv.fr/api/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id={PISTE_OAUTH_ID}
&client_secret={PISTE_OAUTH_SECRET}
```

### Requête Table des matières

```
POST https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/consult/legi/tableMatieres
Authorization: Bearer {access_token}
Content-Type: application/json

{
  "textId": "LEGITEXT000006070633",
  "date": "2026-01-24"
}
```

### Requête Article

```
POST https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/consult/getArticle
Authorization: Bearer {access_token}
Content-Type: application/json

{
  "id": "LEGIARTI000006360827"
}
```

## Codes juridiques prioritaires (mairie)

| Code | TextId | Pertinence |
|------|--------|------------|
| Code des collectivités territoriales | LEGITEXT000006070633 | Haute (MVP Phase 1) |
| Code des communes | LEGITEXT000006070162 | Haute (MVP Phase 1) |
| Code électoral | LEGITEXT000006070239 | Haute (MVP Phase 1) |
| Code de l'urbanisme | LEGITEXT000006074075 | Haute (MVP Phase 1) |
| Code civil | LEGITEXT000006070721 | Haute (MVP Phase 1) |
| Code général de la fonction publique | LEGITEXT000044416551 | Moyenne (Post-MVP) |
| Code de la commande publique | LEGITEXT000037701019 | Moyenne (Post-MVP) |

## Variables d'environnement requises

```
PISTE_OAUTH_ID=dc06ede7-4a49-44e4-90d8-af342a5e1f36
PISTE_OAUTH_SECRET=2bfad70f-7cc3-4c60-84ec-1f1e6e69773e
MISTRAL_API_KEY=QMT34dF9pKDubwKTVQepNNsowm5CJ778
```

Note : Les credentials API key/secret fournis (c7cf...) semblent être des identifiants secondaires. L'OAuth2 client_credentials utilise les identifiants OAuth (dc06...).
