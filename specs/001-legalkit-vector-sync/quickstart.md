# Quickstart : Pipeline Sync Légifrance

## Prérequis

### 1. Variables d'environnement Xano

Ajouter dans les settings Xano :

```
PISTE_OAUTH_ID=dc06ede7-4a49-44e4-90d8-af342a5e1f36
PISTE_OAUTH_SECRET=2bfad70f-7cc3-4c60-84ec-1f1e6e69773e
MISTRAL_API_KEY=QMT34dF9pKDubwKTVQepNNsowm5CJ778
```

### 2. Tables requises

- `REF_codes_legifrance` : **Étendre** (30 nouvelles colonnes)
- `LEX_codes_piste` : **Créer** (référentiel des codes)
- `LOG_sync_legifrance` : **Créer** (logs de synchronisation)

## Ordre d'implémentation

```
Phase 1 : Schema
├── 1.1 Étendre REF_codes_legifrance
├── 1.2 Créer LEX_codes_piste
└── 1.3 Créer LOG_sync_legifrance

Phase 2 : Functions PISTE
├── 2.1 piste_auth_token
├── 2.2 piste_get_toc
├── 2.3 piste_get_article
├── 2.4 piste_extraire_articles_toc
├── 2.5 piste_sync_code
└── 2.6 piste_orchestrer_sync

Phase 3 : Functions Support
├── 3.1 hash_contenu_article
├── 3.2 parser_fullSectionsTitre
└── 3.3 mistral_generer_embedding (si non existant)

Phase 4 : Task & APIs
├── 4.1 Task sync_legifrance_quotidien
├── 4.2 API sync_legifrance_lancer
├── 4.3 API sync_legifrance_statut
└── 4.4 API sync_legifrance_historique

Phase 5 : Données initiales
├── 5.1 Peupler LEX_codes_piste (5 codes prioritaires MVP)
└── 5.2 Lancer première synchronisation
```

## Test rapide

### 1. Tester l'authentification PISTE

```bash
curl -X POST https://oauth.piste.gouv.fr/api/oauth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=dc06ede7-4a49-44e4-90d8-af342a5e1f36&client_secret=2bfad70f-7cc3-4c60-84ec-1f1e6e69773e"
```

Réponse attendue :
```json
{
  "access_token": "eyJ...",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

### 2. Tester la récupération d'un article

```bash
curl -X POST https://api.piste.gouv.fr/dila/legifrance/lf-engine-app/consult/getArticle \
  -H "Authorization: Bearer {access_token}" \
  -H "Content-Type: application/json" \
  -d '{"id": "LEGIARTI000006360827"}'
```

## Codes prioritaires à activer

| Priorité | Code | TextId |
|----------|------|--------|
| 0 | Code général des collectivités territoriales | LEGITEXT000006070633 |
| 1 | Code des communes | LEGITEXT000006070162 |
| 2 | Code électoral | LEGITEXT000006070239 |
| 3 | Code de l'urbanisme | LEGITEXT000006074075 |
| 4 | Code civil | LEGITEXT000006070721 |
| 5 | Code général de la fonction publique | LEGITEXT000044416551 |
| 6 | Code de la commande publique | LEGITEXT000037701019 |

## Monitoring

### Vérifier une sync en cours

```sql
SELECT * FROM LOG_sync_legifrance
WHERE statut = 'EN_COURS'
ORDER BY debut_sync DESC
LIMIT 1
```

### Statistiques globales

```sql
SELECT
  COUNT(*) as total_articles,
  COUNT(CASE WHEN embeddings IS NOT NULL THEN 1 END) as avec_embeddings,
  COUNT(DISTINCT code) as codes_uniques
FROM REF_codes_legifrance
```

## Troubleshooting

| Erreur | Cause probable | Solution |
|--------|----------------|----------|
| 401 sur PISTE | Token expiré | Rafraîchir le token (expire après 1h) |
| 429 sur PISTE | Rate limit | Augmenter délai entre requêtes |
| 429 sur Mistral | Rate limit | Réduire batch size embeddings |
| Timeout TOC | Code volumineux | Augmenter timeout HTTP |
