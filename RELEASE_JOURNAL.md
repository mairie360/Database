# Journal des releases — Database

<!-- release-journal-state {"dev": "c5b8e221f7e4fe8b85e4b3e7f7db4d8d5a75a08a", "prod": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "prod_tag": "v3.3.0", "staging": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "updated": {"dev": "2026-10-31 00:27 UTC", "prod": "2026-10-21 09:11 UTC", "staging": "2026-10-21 03:14 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.3.0 | `1706a71` | 2026-10-21 09:11 UTC |
| staging | — | `1706a71` | 2026-10-21 03:14 UTC |
| dev | — | `c5b8e22` | 2026-10-31 00:27 UTC |

## Ajouté sur main depuis la dernière release prod (v3.3.0)

#### Nouveautés
- Table `compliance_journal` : journal append-only des constats et effacements du service de conformité, sans valeur personnelle (protégé par le trigger `tr_immutable_compliance_journal`). Table `erasure_steps` : une ligne par utilisateur et par étape (`keycloak`, `resend`, `s3`, `redis`, `backup_key`, `database`). (MAIR-498, [#173](https://github.com/mairie360/Database/pull/173))
- Rôle `compliance_api` : ne lit aucune table personnelle, appelle `fn_compliance_scan()` et `fn_erasure_targets(user_id)` (SECURITY DEFINER), peut exécuter `anonymize_user(INT)` et `is_user_anonymized(INT)`. (MAIR-498, [#173](https://github.com/mairie360/Database/pull/173))
- `anonymize_user(p_user_id INT) RETURNS JSONB` (rôle `core_api`) : supprime les événements privés de l'utilisateur, transfère les autres événements, groupes et projets à l'administrateur actif le plus ancien, supprime les lignes marquées `delete`, archive le compte puis efface son identité (« Anonymized User », `anonymized-<id>@anonymized.invalid`, sans mot de passe, téléphone, photo ni biographie). Renvoie `{ user_id, already_anonymized, handed_over_to, deleted_private_events, revoked_sessions }`. Idempotent ; refusé pour l'id 1 et sans autre administrateur actif (`23001`). (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `export_user_data(p_user_id INT) RETURNS JSONB` (rôle `core_api`) : export des données de l'utilisateur, sans mot de passe. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `fn_anonymize_archived_users(INTERVAL)` : anonymise les comptes archivés depuis plus longtemps que la période de la politique `users` (1 an par défaut, `ANONYMIZE`, réglable par instance). (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Contrôle de cohérence du schéma : `gdpr/inventory.yaml` classe chaque colonne (291 colonnes, 46 tables) et ses sections `redis`, avec leur durée de vie maximale. (MAIR-285, [#154](https://github.com/mairie360/Database/pull/154) ; MAIR-499, [#175](https://github.com/mairie360/Database/pull/175))

#### Changements de comportement
- Effacement d'un utilisateur : `conversations.direct_user_low`, `conversations.direct_user_high` et `user_courses.user_id` passent de `ON DELETE CASCADE` à `NO ACTION`. Une conversation directe reste pour l'autre participant et les formations suivies sont conservées. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `restore_user()` refuse désormais un compte anonymisé (`is_user_anonymized()`). (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Lors de l'effacement, les identifiants de `users_audit_log` sont remplacés par des hachages `sha256:` salés. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `users_audit_log` n'enregistre plus `password` ni `photo` pour les nouvelles écritures sur `users`. (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164))

#### Corrections
- Image `liquibase-migrations` : Trivy bloquait `release-dev` sur CVE-2026-111497 (`libbrotli1` 1.1.0-2build2). Maintenant `libbrotli1` est mis à jour en 1.1.0-2ubuntu0.1 dans l'image. (MAIR-739, [#216](https://github.com/mairie360/Database/pull/216))
- Journal d'audit : avant, chaque écriture sur `users` copiait toute la ligne (hash du mot de passe, mots de passe en clair des comptes antérieurs à MAIR-169, photo). Maintenant ces colonnes sont exclues, et la migration `mair-286-01` retire `password` et `photo` des lignes existantes. Cette purge est irréversible ; elle est documentée dans `gdpr/purges.md`. (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164))

#### Technique
- Image `liquibase-migrations` : copie de `gdpr/inventory.yaml` dans `/gdpr/inventory.yaml`, lue par les sauvegardes scellées (MAIR-500, [#177](https://github.com/mairie360/Database/pull/177)). Le paquet `libbrotli1` est ajouté à la mise à jour d'OpenSSL.
- Tests RGPD du schéma (`tests/36`, `tests/40`, `tests/42`), chargement de l'inventaire dans `docker-compose-test.yml`, nouveaux rôles de mot de passe `compliance_api` dans les stacks Compose.
- `LIQUIBASE_SEARCH_PATH` pointe sur `releases/v3.4.0` (ex-`v3.3.1`) dans les stacks Compose.
- Workflow de checklist RGPD des PR (`gdpr-pr.yml`, MAIR-295, [#168](https://github.com/mairie360/Database/pull/168)).
- Mise à jour de CICD vers v4.12.0 dans `cicd.yml`, `promote-staging.yml` et `promote-prod.yml` (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164)), puis pins CICD v4.4.1, v4.4.2 et v4.4.3 (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214)).
- Documentation de `CLAUDE.md` pour les points précédents.

## Différence dev → staging (en dev, pas encore en staging)

#### Nouveautés
- Table `compliance_journal` : journal append-only des constats et effacements du service de conformité, sans valeur personnelle (protégé par le trigger `tr_immutable_compliance_journal`). Table `erasure_steps` : une ligne par utilisateur et par étape (`keycloak`, `resend`, `s3`, `redis`, `backup_key`, `database`). (MAIR-498, [#173](https://github.com/mairie360/Database/pull/173))
- Rôle `compliance_api` : ne lit aucune table personnelle, appelle `fn_compliance_scan()` et `fn_erasure_targets(user_id)` (SECURITY DEFINER), peut exécuter `anonymize_user(INT)` et `is_user_anonymized(INT)`. (MAIR-498, [#173](https://github.com/mairie360/Database/pull/173))
- `anonymize_user(p_user_id INT) RETURNS JSONB` (rôle `core_api`) : supprime les événements privés de l'utilisateur, transfère les autres événements, groupes et projets à l'administrateur actif le plus ancien, supprime les lignes marquées `delete`, archive le compte puis efface son identité (« Anonymized User », `anonymized-<id>@anonymized.invalid`, sans mot de passe, téléphone, photo ni biographie). Renvoie `{ user_id, already_anonymized, handed_over_to, deleted_private_events, revoked_sessions }`. Idempotent ; refusé pour l'id 1 et sans autre administrateur actif (`23001`). (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `export_user_data(p_user_id INT) RETURNS JSONB` (rôle `core_api`) : export des données de l'utilisateur, sans mot de passe. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `fn_anonymize_archived_users(INTERVAL)` : anonymise les comptes archivés depuis plus longtemps que la période de la politique `users` (1 an par défaut, `ANONYMIZE`, réglable par instance). (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Contrôle de cohérence du schéma : `gdpr/inventory.yaml` classe chaque colonne (291 colonnes, 46 tables) et ses sections `redis`, avec leur durée de vie maximale. (MAIR-285, [#154](https://github.com/mairie360/Database/pull/154) ; MAIR-499, [#175](https://github.com/mairie360/Database/pull/175))

#### Changements de comportement
- Effacement d'un utilisateur : `conversations.direct_user_low`, `conversations.direct_user_high` et `user_courses.user_id` passent de `ON DELETE CASCADE` à `NO ACTION`. Une conversation directe reste pour l'autre participant et les formations suivies sont conservées. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `restore_user()` refuse désormais un compte anonymisé (`is_user_anonymized()`). (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- Lors de l'effacement, les identifiants de `users_audit_log` sont remplacés par des hachages `sha256:` salés. (MAIR-289, [#166](https://github.com/mairie360/Database/pull/166))
- `users_audit_log` n'enregistre plus `password` ni `photo` pour les nouvelles écritures sur `users`. (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164))

#### Corrections
- Image `liquibase-migrations` : Trivy bloquait `release-dev` sur CVE-2026-111497 (`libbrotli1` 1.1.0-2build2). Maintenant `libbrotli1` est mis à jour en 1.1.0-2ubuntu0.1 dans l'image. (MAIR-739, [#216](https://github.com/mairie360/Database/pull/216))
- Journal d'audit : avant, chaque écriture sur `users` copiait toute la ligne (hash du mot de passe, mots de passe en clair des comptes antérieurs à MAIR-169, photo). Maintenant ces colonnes sont exclues, et la migration `mair-286-01` retire `password` et `photo` des lignes existantes. Cette purge est irréversible ; elle est documentée dans `gdpr/purges.md`. (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164))

#### Technique
- Image `liquibase-migrations` : copie de `gdpr/inventory.yaml` dans `/gdpr/inventory.yaml`, lue par les sauvegardes scellées (MAIR-500, [#177](https://github.com/mairie360/Database/pull/177)). Le paquet `libbrotli1` est ajouté à la mise à jour d'OpenSSL.
- Tests RGPD du schéma (`tests/36`, `tests/40`, `tests/42`), chargement de l'inventaire dans `docker-compose-test.yml`, nouveaux rôles de mot de passe `compliance_api` dans les stacks Compose.
- `LIQUIBASE_SEARCH_PATH` pointe sur `releases/v3.4.0` (ex-`v3.3.1`) dans les stacks Compose.
- Workflow de checklist RGPD des PR (`gdpr-pr.yml`, MAIR-295, [#168](https://github.com/mairie360/Database/pull/168)).
- Mise à jour de CICD vers v4.12.0 dans `cicd.yml`, `promote-staging.yml` et `promote-prod.yml` (MAIR-286, [#164](https://github.com/mairie360/Database/pull/164)), puis pins CICD v4.4.1, v4.4.2 et v4.4.3 (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210), [#212](https://github.com/mairie360/Database/pull/212), [#214](https://github.com/mairie360/Database/pull/214)).
- Documentation de `CLAUDE.md` pour les points précédents.

## Différence staging → prod (en staging, pas encore en prod)

_Rien._

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
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
