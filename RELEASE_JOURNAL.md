# Journal des releases — Database

<!-- release-journal-state {"dev": "c4fa2dd7dfaa01a0f41c90c5bf004dce5703b86c", "prod": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "prod_tag": "v3.3.0", "staging": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "updated": {"dev": "2026-11-04 14:08 UTC", "prod": "2026-10-21 09:11 UTC", "staging": "2026-10-21 03:14 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.3.0 | `1706a71` | 2026-10-21 09:11 UTC |
| staging | — | `1706a71` | 2026-10-21 03:14 UTC |
| dev | — | `c4fa2dd` | 2026-11-04 14:08 UTC |

## Ajouté sur main depuis la dernière release prod (v3.3.0)

#### Nouveautés
- Tables `compliance_journal` (journal append-only des constats et effacements, sans valeur) et `erasure_steps` (étapes d'effacement par utilisateur : keycloak, resend, s3, redis, backup_key, database), avec le rôle `compliance_api` qui ne lit aucune table personnelle et appelle `fn_compliance_scan()` et `fn_erasure_targets(user_id)`. (MAIR-498, [#173](https://github.com/mairie360/Database/pull/173))
- Effacement d'un utilisateur par `anonymize_user(p_user_id INT)` (exécutée par `core_api`) : suppression des événements privés, transfert des autres événements, groupes et projets à un administrateur actif, suppression des lignes marquées `delete`, archivage puis anonymisation du compte, remplacement des clés d'identité de `users_audit_log` par des hachages `sha256:`. Retour : `{ user_id, already_anonymized, handed_over_to, deleted_private_events, revoked_sessions }`. Refusée pour l'id 1 et sans autre administrateur actif (`23001`). (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `export_user_data(p_user_id INT)` renvoie les données d'un utilisateur (`{ user, data, exported_at }`), sans le mot de passe. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `fn_anonymize_archived_users(INTERVAL)` anonymise les comptes archivés depuis plus longtemps que la période de la politique `users` (1 an par défaut), via `fn_apply_retention_policies()` avec `ANONYMIZE`. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))

#### Changements de comportement
- Suppression d'un compte : les conversations directes restent pour l'autre participant, car `conversations.direct_user_low` et `direct_user_high` passent de `ON DELETE CASCADE` à `NO ACTION`. Les formations suivies (`user_courses.user_id`) ne sont plus supprimées en cascade avec l'utilisateur. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `restore_user()` refuse désormais un compte anonymisé (`is_user_anonymized()`). Un appelant qui restaure un compte effacé reçoit une erreur. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Nouvelle valeur `ANONYMIZE` pour `archive_strategy_type` et politique `users` à `1 year` : les comptes archivés depuis plus d'un an sont anonymisés. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))

#### Corrections
- Journal d'audit des comptes (`users_audit_log`) : avant, chaque écriture sur `users` copiait la ligne entière, avec le hash du mot de passe, le mot de passe en clair des comptes antérieurs à MAIR-169 et la photo. Maintenant, `password` et `photo` sont exclus du journal. La migration `mair-286-01` retire ces clés des lignes déjà écrites, de façon irréversible (le rollback ne fait rien). Voir `gdpr/purges.md`. (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164))

#### Technique
- Inventaire RGPD `gdpr/inventory.yaml` : classification de chaque colonne (291 colonnes, 46 tables), section `redis` avec TTL, clés du cache de lecture (`read-cache:…`) et clé des liens Keycloak à usage unique ; tests `tests/gdpr/redis_prefixes_test.py`, `tests/40`, `tests/41` et `tests/42`. (MAIR-285, MAIR-499, MAIR-497, MAIR-609, MAIR-286, [#154](https://github.com/mairie360/Database/pull/154), [#175](https://github.com/mairie360/Database/pull/175), [#222](https://github.com/mairie360/Database/pull/222), [#224](https://github.com/mairie360/Database/pull/224))
- L'inventaire est copié dans l'image `liquibase-migrations` à `/gdpr/inventory.yaml` (MAIR-500, [#177](https://github.com/mairie360/Database/pull/177)). Les colonnes de `compliance_journal` et `erasure_steps` sont consignées dans l'inventaire.
- Workflow `gdpr-pr.yml` : checklist RGPD sur les pull requests (MAIR-295, [#168](https://github.com/mairie360/Database/pull/168)).
- Passage de CICD de v4.4.0 à v5.2.2 dans les workflows, avec le script `cicd_version_test.sh` qui vérifie l'alignement des versions (MAIR-612 : [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214) ; MAIR-771 : [#218](https://github.com/mairie360/Database/pull/218)).
- `libbrotli1` mis à jour dans l'image `liquibase-migrations` pour corriger CVE-2026-111497, qui bloquait `release-dev` au scan Trivy (MAIR-739, [#216](https://github.com/mairie360/Database/pull/216)).
- `LIQUIBASE_SEARCH_PATH` pointe sur `releases/v3.4.0` au lieu de `v3.3.1` dans les compose (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166)).

## Différence dev → staging (en dev, pas encore en staging)

#### Nouveautés
- Tables `compliance_journal` (journal append-only des constats et effacements, sans valeur) et `erasure_steps` (étapes d'effacement par utilisateur : keycloak, resend, s3, redis, backup_key, database), avec le rôle `compliance_api` qui ne lit aucune table personnelle et appelle `fn_compliance_scan()` et `fn_erasure_targets(user_id)`. (MAIR-498, [#173](https://github.com/mairie360/Database/pull/173))
- Effacement d'un utilisateur par `anonymize_user(p_user_id INT)` (exécutée par `core_api`) : suppression des événements privés, transfert des autres événements, groupes et projets à un administrateur actif, suppression des lignes marquées `delete`, archivage puis anonymisation du compte, remplacement des clés d'identité de `users_audit_log` par des hachages `sha256:`. Retour : `{ user_id, already_anonymized, handed_over_to, deleted_private_events, revoked_sessions }`. Refusée pour l'id 1 et sans autre administrateur actif (`23001`). (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `export_user_data(p_user_id INT)` renvoie les données d'un utilisateur (`{ user, data, exported_at }`), sans le mot de passe. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `fn_anonymize_archived_users(INTERVAL)` anonymise les comptes archivés depuis plus longtemps que la période de la politique `users` (1 an par défaut), via `fn_apply_retention_policies()` avec `ANONYMIZE`. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))

#### Changements de comportement
- Suppression d'un compte : les conversations directes restent pour l'autre participant, car `conversations.direct_user_low` et `direct_user_high` passent de `ON DELETE CASCADE` à `NO ACTION`. Les formations suivies (`user_courses.user_id`) ne sont plus supprimées en cascade avec l'utilisateur. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `restore_user()` refuse désormais un compte anonymisé (`is_user_anonymized()`). Un appelant qui restaure un compte effacé reçoit une erreur. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Nouvelle valeur `ANONYMIZE` pour `archive_strategy_type` et politique `users` à `1 year` : les comptes archivés depuis plus d'un an sont anonymisés. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))

#### Corrections
- Journal d'audit des comptes (`users_audit_log`) : avant, chaque écriture sur `users` copiait la ligne entière, avec le hash du mot de passe, le mot de passe en clair des comptes antérieurs à MAIR-169 et la photo. Maintenant, `password` et `photo` sont exclus du journal. La migration `mair-286-01` retire ces clés des lignes déjà écrites, de façon irréversible (le rollback ne fait rien). Voir `gdpr/purges.md`. (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164))

#### Technique
- Inventaire RGPD `gdpr/inventory.yaml` : classification de chaque colonne (291 colonnes, 46 tables), section `redis` avec TTL, clés du cache de lecture (`read-cache:…`) et clé des liens Keycloak à usage unique ; tests `tests/gdpr/redis_prefixes_test.py`, `tests/40`, `tests/41` et `tests/42`. (MAIR-285, MAIR-499, MAIR-497, MAIR-609, MAIR-286, [#154](https://github.com/mairie360/Database/pull/154), [#175](https://github.com/mairie360/Database/pull/175), [#222](https://github.com/mairie360/Database/pull/222), [#224](https://github.com/mairie360/Database/pull/224))
- L'inventaire est copié dans l'image `liquibase-migrations` à `/gdpr/inventory.yaml` (MAIR-500, [#177](https://github.com/mairie360/Database/pull/177)). Les colonnes de `compliance_journal` et `erasure_steps` sont consignées dans l'inventaire.
- Workflow `gdpr-pr.yml` : checklist RGPD sur les pull requests (MAIR-295, [#168](https://github.com/mairie360/Database/pull/168)).
- Passage de CICD de v4.4.0 à v5.2.2 dans les workflows, avec le script `cicd_version_test.sh` qui vérifie l'alignement des versions (MAIR-612 : [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214) ; MAIR-771 : [#218](https://github.com/mairie360/Database/pull/218)).
- `libbrotli1` mis à jour dans l'image `liquibase-migrations` pour corriger CVE-2026-111497, qui bloquait `release-dev` au scan Trivy (MAIR-739, [#216](https://github.com/mairie360/Database/pull/216)).
- `LIQUIBASE_SEARCH_PATH` pointe sur `releases/v3.4.0` au lieu de `v3.3.1` dans les compose (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166)).

## Différence staging → prod (en staging, pas encore en prod)

_Rien._

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
| 2026-11-04 14:08 UTC | dev | — | `c4fa2dd` | [run](https://github.com/mairie360/Database/actions/runs/41843779424) |
| 2026-11-03 13:50 UTC | dev | — | `1fcf3fb` | [run](https://github.com/mairie360/Database/actions/runs/41647256820) |
| 2026-11-02 23:56 UTC | dev | — | `ba1419d` | [run](https://github.com/mairie360/Database/actions/runs/41548528544) |
| 2026-10-31 00:27 UTC | dev | — | `c5b8e22` | [run](https://github.com/mairie360/Database/actions/runs/41149888015) |
| 2026-10-21 09:11 UTC | prod | v3.3.0 | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39574474376) |
| 2026-10-21 09:10 UTC | dev | — | `3062888` | [run](https://github.com/mairie360/Database/actions/runs/39574431117) |
| 2026-10-21 08:27 UTC | dev | — | `db3c2a2` | [run](https://github.com/mairie360/Database/actions/runs/39568811813) |
| 2026-10-21 03:50 UTC | dev | — | `ef11982` | [run](https://github.com/mairie360/Database/actions/runs/39540422847) |
| 2026-10-21 03:14 UTC | staging | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39537392312) |
| 2026-10-21 01:37 UTC | dev | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39527984881) |
| 2026-10-20 19:11 UTC | dev | — | `cb09f08` | [run](https://github.com/mairie360/Database/actions/runs/39480797338) |
| 2026-10-19 20:05 UTC | dev | — | `34b5230` | [run](https://github.com/mairie360/Database/actions/runs/39315794981) |
<!-- release-journal-history:end -->
