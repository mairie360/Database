# Journal des releases — Database

<!-- release-journal-state {"dev": "ba1419d2379a62863c1ff61084a9d825c25277fd", "prod": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "prod_tag": "v3.3.0", "staging": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "updated": {"dev": "2026-11-02 23:56 UTC", "prod": "2026-10-21 09:11 UTC", "staging": "2026-10-21 03:14 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.3.0 | `1706a71` | 2026-10-21 09:11 UTC |
| staging | — | `1706a71` | 2026-10-21 03:14 UTC |
| dev | — | `ba1419d` | 2026-11-02 23:56 UTC |

## Ajouté sur main depuis la dernière release prod (v3.3.0)

#### Nouveautés
- Journal de conformité de l'instance : tables `compliance_journal` (append-only, `tr_immutable_compliance_journal`, `UPDATE` et `DELETE` refusés) et `erasure_steps`, rôle `compliance_api` (ne lit aucune table personnelle, exige `-Dcompliance_api_password` au déploiement), fonctions `fn_compliance_scan()` et `fn_erasure_targets(user_id)`. (MAIR-498, [#173](https://github.com/mairie360/Database/pull/173))
- Effacement et export d'un utilisateur, réservés à `core_api` : `anonymize_user(p_user_id INT)` renvoie `{ user_id, already_anonymized, handed_over_to, deleted_private_events, revoked_sessions }`, `export_user_data(p_user_id INT)` renvoie les données de l'utilisateur, `fn_anonymize_archived_users(INTERVAL)` et `is_user_anonymized(INT)`. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Sauvegardes : l'image `liquibase-migrations` contient `/gdpr/inventory.yaml`, lu par les sauvegardes scellées du schéma déployé. (MAIR-500, [#177](https://github.com/mairie360/Database/pull/177))

#### Changements de comportement
- Un compte archivé est anonymisé après la durée de la politique `users` (1 an par défaut, réglable par instance) : nom, e-mail, mot de passe, téléphone, photo et biographie sont effacés, les événements privés supprimés, les autres événements, groupes et projets transférés à un administrateur. Avant, rien n'était anonymisé. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `restore_user()` refuse un compte anonymisé. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Les clés `direct_user_low` / `direct_user_high` de `conversations` et `user_courses.user_id` passent de `ON DELETE CASCADE` à `NO ACTION` : une conversation directe et les formations suivies ne sont plus supprimées avec l'utilisateur, et un `DELETE` physique d'un utilisateur qui les référence est refusé par la base. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))

#### Corrections
- Journal d'audit des comptes : `users_audit_log` copiait la ligne complète de `users` dans `previous_data` / `new_data`. Avant : le hash des mots de passe, les mots de passe en clair des comptes antérieurs à MAIR-169 et les photos étaient conservés. Maintenant : le trigger exclut `password` et `photo`, et la migration `mair-286-01` retire ces clés des lignes existantes. La purge est irréversible (rollback sans effet) et sa trace est dans `gdpr/purges.md`. (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164))

#### Technique
- Versions CICD alignées sur les workflows : v4.4.1, v4.4.2 et v4.4.3 (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214)), puis v4.12.0 (MAIR-286, MAIR-295, [#168](https://github.com/mairie360/Database/pull/168)) et v5.2.2 (MAIR-771, [#218](https://github.com/mairie360/Database/pull/218)), avec le test `cicd_version_test.sh`.
- Inventaire RGPD `gdpr/inventory.yaml` (MAIR-285, [#154](https://github.com/mairie360/Database/pull/154)), section Redis (MAIR-499, [#175](https://github.com/mairie360/Database/pull/175)), tests de schéma RGPD, image Liquibase avec `libbrotli1` mis à niveau (MAIR-739, [#216](https://github.com/mairie360/Database/pull/216)).

## Différence dev → staging (en dev, pas encore en staging)

#### Nouveautés
- Journal de conformité de l'instance : tables `compliance_journal` (append-only, `tr_immutable_compliance_journal`, `UPDATE` et `DELETE` refusés) et `erasure_steps`, rôle `compliance_api` (ne lit aucune table personnelle, exige `-Dcompliance_api_password` au déploiement), fonctions `fn_compliance_scan()` et `fn_erasure_targets(user_id)`. (MAIR-498, [#173](https://github.com/mairie360/Database/pull/173))
- Effacement et export d'un utilisateur, réservés à `core_api` : `anonymize_user(p_user_id INT)` renvoie `{ user_id, already_anonymized, handed_over_to, deleted_private_events, revoked_sessions }`, `export_user_data(p_user_id INT)` renvoie les données de l'utilisateur, `fn_anonymize_archived_users(INTERVAL)` et `is_user_anonymized(INT)`. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Sauvegardes : l'image `liquibase-migrations` contient `/gdpr/inventory.yaml`, lu par les sauvegardes scellées du schéma déployé. (MAIR-500, [#177](https://github.com/mairie360/Database/pull/177))

#### Changements de comportement
- Un compte archivé est anonymisé après la durée de la politique `users` (1 an par défaut, réglable par instance) : nom, e-mail, mot de passe, téléphone, photo et biographie sont effacés, les événements privés supprimés, les autres événements, groupes et projets transférés à un administrateur. Avant, rien n'était anonymisé. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `restore_user()` refuse un compte anonymisé. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Les clés `direct_user_low` / `direct_user_high` de `conversations` et `user_courses.user_id` passent de `ON DELETE CASCADE` à `NO ACTION` : une conversation directe et les formations suivies ne sont plus supprimées avec l'utilisateur, et un `DELETE` physique d'un utilisateur qui les référence est refusé par la base. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))

#### Corrections
- Journal d'audit des comptes : `users_audit_log` copiait la ligne complète de `users` dans `previous_data` / `new_data`. Avant : le hash des mots de passe, les mots de passe en clair des comptes antérieurs à MAIR-169 et les photos étaient conservés. Maintenant : le trigger exclut `password` et `photo`, et la migration `mair-286-01` retire ces clés des lignes existantes. La purge est irréversible (rollback sans effet) et sa trace est dans `gdpr/purges.md`. (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164))

#### Technique
- Versions CICD alignées sur les workflows : v4.4.1, v4.4.2 et v4.4.3 (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214)), puis v4.12.0 (MAIR-286, MAIR-295, [#168](https://github.com/mairie360/Database/pull/168)) et v5.2.2 (MAIR-771, [#218](https://github.com/mairie360/Database/pull/218)), avec le test `cicd_version_test.sh`.
- Inventaire RGPD `gdpr/inventory.yaml` (MAIR-285, [#154](https://github.com/mairie360/Database/pull/154)), section Redis (MAIR-499, [#175](https://github.com/mairie360/Database/pull/175)), tests de schéma RGPD, image Liquibase avec `libbrotli1` mis à niveau (MAIR-739, [#216](https://github.com/mairie360/Database/pull/216)).

## Différence staging → prod (en staging, pas encore en prod)

_Rien._

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
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
