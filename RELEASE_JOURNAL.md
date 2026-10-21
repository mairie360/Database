# Journal des releases — Database

<!-- release-journal-state {"dev": "ef11982b0c1fe21d4ad0daeddbe8cfba6a9891f0", "prod": "5fe90c1df8f337fc22e88966780bc518b7220251", "prod_tag": "v3.2.0", "staging": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "updated": {"dev": "2026-10-21 03:50 UTC", "staging": "2026-10-21 03:14 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.2.0 | `5fe90c1` | — |
| staging | — | `1706a71` | 2026-10-21 03:14 UTC |
| dev | — | `ef11982` | 2026-10-21 03:50 UTC |

## Ajouté sur main depuis la dernière release prod (v3.2.0)

#### Nouveautés
- Nouveau rôle Postgres `compliance_api` (login, sans attribut élevé, mot de passe via `-Dcompliance_api_password`). Il ne reçoit que les droits partagés (lecture de `users (id, email, is_archived)` et `check_access()`) et n'a aucune table propre. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Changements de comportement
- Toutes les APIs peuvent désormais lire `users.email`, y compris `core_api` (qui ne lisait que `id`), `calendar_api` (qui lisait `id, is_archived`) et `project_api`, `message_api`, `elearning_api`. Rien n'est retiré : c'est une extension de privilèges, à relire côté sécurité. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Corrections
- Avant : les tokens Keycloak étaient refusés sur Project, Calendar, Message et ELearning, car la recherche de l'utilisateur par e-mail (`get_user_id_by_email`) échouait avec l'erreur `42501` hors de `core_api`. Maintenant : la lecture de `users (id, email, is_archived)` est accordée à toutes les APIs, et cette recherche réussit. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Technique
- Les tests des APIs s'exécutent sous le rôle Postgres de chaque API (`-D<role>_password` ajouté à `docker-compose*.yml`, `bench/` et `tests/upgrade/run.sh`), et `20_api_roles_test.sql` passe de 33 à 36 tests. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))
- Mises à jour CI : pin de mairie360/CICD v4.2.1 → v4.2.2 → v4.3.1 (ajout des secrets `ANTHROPIC_API_KEY`, `RELEASE_APP_ID` et `RELEASE_APP_PK` pour le journal des releases), promotion staging et prod séparée du workflow de base avec `renovate.json` et `CLAUDE.md` mis à jour. (MAIR-571, [#202](https://github.com/mairie360/Database/pull/202) ; MAIR-494, [#207](https://github.com/mairie360/Database/pull/207) ; [#200](https://github.com/mairie360/Database/pull/200) et [#204](https://github.com/mairie360/Database/pull/204) via Renovate)

## Différence dev → staging (en dev, pas encore en staging)

#### Technique
- Correction du pin CICD pour la promotion en prod : `cicd.yml`, `promote-staging.yml` et `promote-prod.yml` passent de mairie360/CICD v4.4.0 à v4.4.1 (le dry run de semantic-release de v4.4.0 ne lisait pas son miroir). Aucun changement fonctionnel côté base. (MAIR-612, [#210](https://github.com/mairie360/Database/pull/210))

## Différence staging → prod (en staging, pas encore en prod)

#### Changements de comportement
- Toutes les APIs peuvent désormais lire `users.email`, y compris `core_api` (qui ne lisait que `id`), `calendar_api` (qui lisait `id, is_archived`) et `project_api`, `message_api`, `elearning_api`. Rien n'est retiré : c'est une extension de privilèges. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Corrections
- Avant : les tokens Keycloak étaient refusés sur Project, Calendar, Message et ELearning (erreur `42501` sur `get_user_id_by_email` hors de `core_api`). Maintenant : la lecture de `users (id, email, is_archived)` est accordée à toutes les APIs et cette recherche réussit. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))

#### Technique
- Nouveau rôle `compliance_api` (sans table propre) et tests des APIs exécutés sous leur rôle Postgres, `20_api_roles_test.sql` passant de 33 à 36 tests. Le diff de #187 est tronqué : la liste complète des tests n'a pas été vérifiée. (MAIR-556, [#187](https://github.com/mairie360/Database/pull/187))
- Mises à jour CI : pin mairie360/CICD v4.2.2 → v4.3.1 (secrets du journal des releases), promotion staging et prod manuelle (`promote-staging.yml`, `promote-prod.yml`), et Renovate ajusté. Aucun effet sur l'application. (MAIR-571, [#202](https://github.com/mairie360/Database/pull/202) ; MAIR-494, [#207](https://github.com/mairie360/Database/pull/207) ; [#200](https://github.com/mairie360/Database/pull/200) et [#204](https://github.com/mairie360/Database/pull/204))

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
| 2026-10-21 03:50 UTC | dev | — | `ef11982` | [run](https://github.com/mairie360/Database/actions/runs/39540422847) |
| 2026-10-21 03:14 UTC | staging | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39537392312) |
| 2026-10-21 01:37 UTC | dev | — | `1706a71` | [run](https://github.com/mairie360/Database/actions/runs/39527984881) |
| 2026-10-20 19:11 UTC | dev | — | `cb09f08` | [run](https://github.com/mairie360/Database/actions/runs/39480797338) |
| 2026-10-19 20:05 UTC | dev | — | `34b5230` | [run](https://github.com/mairie360/Database/actions/runs/39315794981) |
<!-- release-journal-history:end -->
