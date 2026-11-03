# Journal des releases — Database

<!-- release-journal-state {"dev": "1fcf3fbc047909e854927b6d0879643c782c93d5", "prod": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "prod_tag": "v3.3.0", "staging": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "updated": {"dev": "2026-11-03 13:50 UTC", "prod": "2026-10-21 09:11 UTC", "staging": "2026-10-21 03:14 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.3.0 | `1706a71` | 2026-10-21 09:11 UTC |
| staging | — | `1706a71` | 2026-10-21 03:14 UTC |
| dev | — | `1fcf3fb` | 2026-11-03 13:50 UTC |

## Ajouté sur main depuis la dernière release prod (v3.3.0)

#### Nouveautés
- Journal de conformité `compliance_journal` (append-only, trigger `tr_immutable_compliance_journal`) et table `erasure_steps` pour le service de conformité de l'instance ; rôle `compliance_api` qui ne lit aucune table personnelle et passe par `fn_compliance_scan()`, `fn_erasure_targets(INT)` et `anonymize_user(INT)`. (MAIR-498, [#173](https://github.com/mairie360/Database/pull/173))
- Effacement d'un utilisateur par `anonymize_user(p_user_id INT)` (rôle `core_api`) : suppression des événements privés, transfert des autres événements, groupes et projets à un administrateur, suppression des lignes marquées `delete`, archivage puis effacement de l'identité du compte. Renvoie `{ user_id, already_anonymized, handed_over_to, deleted_private_events, revoked_sessions }`. Refusé pour l'id 1 et sans autre administrateur actif (`23001`). (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Export des données d'un utilisateur par `export_user_data(p_user_id INT)` (rôle `core_api`), et fonctions `fn_anonymize_archived_users(INTERVAL)` et `is_user_anonymized(INT)`. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Inventaire RGPD copié dans l'image `liquibase-migrations` à `/gdpr/inventory.yaml`, lisible par tout utilisateur de l'image. (MAIR-500, [#177](https://github.com/mairie360/Database/pull/177))

#### Changements de comportement
- `users_audit_log` n'enregistre plus les colonnes `password` ni `photo` de `users` (`fn_audit_and_mutate_user()`). La migration `mair-286-01` retire ces clés des lignes déjà présentes ; l'opération est irréversible (rollback sans effet). (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164))
- Lors de la suppression d'une ligne `users`, les conversations directes ne sont plus supprimées en cascade (`direct_user_low` et `direct_user_high` passent de `ON DELETE CASCADE` à `NO ACTION`), et les formations suivies (`user_courses.user_id`) sont conservées. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- La politique `users` de `retention_policies` est ajoutée : un compte archivé depuis plus d'un an (`ANONYMIZE`, durée modifiable par instance) est anonymisé automatiquement. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `restore_user()` refuse désormais un compte anonymisé (`is_user_anonymized()`). (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))

#### Technique
- Passage de `cicd.yml`, `promote-staging.yml`, `promote-prod.yml` et `gdpr-pr.yml` à mairie360/CICD v5.2.2, avec `ANTHROPIC_API_KEY` et `ANTHROPIC_WORKSPACE_ID` transmis pour les contrôles RGPD. Nouveau `cicd_version_test.sh`, lancé par `./test.sh`, qui vérifie que tous les workflows appellent la même version de CICD. (MAIR-771, [#218](https://github.com/mairie360/Database/pull/218))
- Nouveau workflow `gdpr-pr.yml` qui vérifie la section « Données personnelles » des PR, et section `redis` de l'inventaire (clés Redis, TTL maximum) avec le test `redis_prefixes_test.py`. (MAIR-295, [#168](https://github.com/mairie360/Database/pull/168) ; MAIR-499, [#175](https://github.com/mairie360/Database/pull/175) ; MAIR-497, [#222](https://github.com/mairie360/Database/pull/222))
- Mise à jour de `libbrotli1` (CVE-2026-111497) dans `liquibase/Dockerfile`, pour que le scan Trivy de `release-dev` passe à nouveau. (MAIR-739, [#216](https://github.com/mairie360/Database/pull/216))
- Chemins `LIQUIBASE_SEARCH_PATH` mis à jour de `releases/v3.3.1` vers `releases/v3.4.0`, et tests GDPR du schéma (`tests/gdpr/inventory_to_sql.py`, inventaire chargé dans les tests). (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164) ; MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Versions de CICD alignées sur v4.4.1, v4.4.2 puis v4.4.3 pour les promotions (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214)), puis v4.12.0 (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164)).

## Différence dev → staging (en dev, pas encore en staging)

#### Nouveautés
- Journal de conformité `compliance_journal` (append-only, trigger `tr_immutable_compliance_journal`) et table `erasure_steps` pour le service de conformité de l'instance ; rôle `compliance_api` qui ne lit aucune table personnelle et passe par `fn_compliance_scan()`, `fn_erasure_targets(INT)` et `anonymize_user(INT)`. (MAIR-498, [#173](https://github.com/mairie360/Database/pull/173))
- Effacement d'un utilisateur par `anonymize_user(p_user_id INT)` (rôle `core_api`) : suppression des événements privés, transfert des autres événements, groupes et projets à un administrateur, suppression des lignes marquées `delete`, archivage puis effacement de l'identité du compte. Renvoie `{ user_id, already_anonymized, handed_over_to, deleted_private_events, revoked_sessions }`. Refusé pour l'id 1 et sans autre administrateur actif (`23001`). (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Export des données d'un utilisateur par `export_user_data(p_user_id INT)` (rôle `core_api`), et fonctions `fn_anonymize_archived_users(INTERVAL)` et `is_user_anonymized(INT)`. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Inventaire RGPD copié dans l'image `liquibase-migrations` à `/gdpr/inventory.yaml`, lisible par tout utilisateur de l'image. (MAIR-500, [#177](https://github.com/mairie360/Database/pull/177))

#### Changements de comportement
- `users_audit_log` n'enregistre plus les colonnes `password` ni `photo` de `users` (`fn_audit_and_mutate_user()`). La migration `mair-286-01` retire ces clés des lignes déjà présentes ; l'opération est irréversible (rollback sans effet). (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164))
- Lors de la suppression d'une ligne `users`, les conversations directes ne sont plus supprimées en cascade (`direct_user_low` et `direct_user_high` passent de `ON DELETE CASCADE` à `NO ACTION`), et les formations suivies (`user_courses.user_id`) sont conservées. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- La politique `users` de `retention_policies` est ajoutée : un compte archivé depuis plus d'un an (`ANONYMIZE`, durée modifiable par instance) est anonymisé automatiquement. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `restore_user()` refuse désormais un compte anonymisé (`is_user_anonymized()`). (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))

#### Technique
- Passage de `cicd.yml`, `promote-staging.yml`, `promote-prod.yml` et `gdpr-pr.yml` à mairie360/CICD v5.2.2, avec `ANTHROPIC_API_KEY` et `ANTHROPIC_WORKSPACE_ID` transmis pour les contrôles RGPD. Nouveau `cicd_version_test.sh`, lancé par `./test.sh`, qui vérifie que tous les workflows appellent la même version de CICD. (MAIR-771, [#218](https://github.com/mairie360/Database/pull/218))
- Nouveau workflow `gdpr-pr.yml` qui vérifie la section « Données personnelles » des PR, et section `redis` de l'inventaire (clés Redis, TTL maximum) avec le test `redis_prefixes_test.py`. (MAIR-295, [#168](https://github.com/mairie360/Database/pull/168) ; MAIR-499, [#175](https://github.com/mairie360/Database/pull/175) ; MAIR-497, [#222](https://github.com/mairie360/Database/pull/222))
- Mise à jour de `libbrotli1` (CVE-2026-111497) dans `liquibase/Dockerfile`, pour que le scan Trivy de `release-dev` passe à nouveau. (MAIR-739, [#216](https://github.com/mairie360/Database/pull/216))
- Chemins `LIQUIBASE_SEARCH_PATH` mis à jour de `releases/v3.3.1` vers `releases/v3.4.0`, et tests GDPR du schéma (`tests/gdpr/inventory_to_sql.py`, inventaire chargé dans les tests). (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164) ; MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Versions de CICD alignées sur v4.4.1, v4.4.2 puis v4.4.3 pour les promotions (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214)), puis v4.12.0 (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164)).

## Différence staging → prod (en staging, pas encore en prod)

_Rien._

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
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
