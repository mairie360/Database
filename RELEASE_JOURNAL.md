# Journal des releases — Database

<!-- release-journal-state {"dev": "c4fa2dd7dfaa01a0f41c90c5bf004dce5703b86c", "prod": "1706a71bfaea64d866c1dfe4289fe8d9d3f5199c", "prod_tag": "v3.3.0", "staging": "c4fa2dd7dfaa01a0f41c90c5bf004dce5703b86c", "updated": {"dev": "2026-11-04 14:08 UTC", "prod": "2026-10-21 09:11 UTC", "staging": "2026-11-12 22:33 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.3.0 | `1706a71` | 2026-10-21 09:11 UTC |
| staging | — | `c4fa2dd` | 2026-11-12 22:33 UTC |
| dev | — | `c4fa2dd` | 2026-11-04 14:08 UTC |

## Ajouté sur main depuis la dernière release prod (v3.3.0)

- docs: MAIR-609 Core/BFF_user - Accès temporaire à la console Keycloak pour les admins de mairie (#224) ([#224](https://github.com/mairie360/Database/pull/224))
- fix: MAIR-497 RGPD - Simulation d'usage et revue IA des logs et de la base avant la prod ([#222](https://github.com/mairie360/Database/pull/222))
- ci: MAIR-771 APIs, BFFs, Database : monter CICD en v5.2.2 pour activer les contrôles RGPD (#218) ([#218](https://github.com/mairie360/Database/pull/218))
- fix: MAIR-739 Database : mettre à jour libbrotli1 dans l'image liquibase-migrations (CVE-2026-111497) (#216) ([#216](https://github.com/mairie360/Database/pull/216))
- feat: MAIR-500 Chiffrer les sauvegardes avec une clé par utilisateur, détruite à son effacement (#177) ([#177](https://github.com/mairie360/Database/pull/177))
- feat: MAIR-498 Service de conformité de l'instance : scan permanent, effacement centralisé et journal des fuites (#173) ([#173](https://github.com/mairie360/Database/pull/173))
- feat: MAIR-499 Rendre le TTL obligatoire sur Redis dans les APIs et les BFFs (#175) ([#175](https://github.com/mairie360/Database/pull/175))
- feat: MAIR-289 Anonymiser et exporter les données d'un utilisateur, avec tests d'effacement (#166) ([#166](https://github.com/mairie360/Database/pull/166))
- ci: MAIR-295 Ajouter une checklist RGPD aux PR et des rappels d'échéances automatiques (#168) ([#168](https://github.com/mairie360/Database/pull/168))
- fix: MAIR-286 Tester la conformité RGPD du schéma et exclure les mots de passe du journal d'audit (#164) ([#164](https://github.com/mairie360/Database/pull/164))
- docs: MAIR-285 Inventorier les données personnelles du schéma et tester sa complétude (#154) ([#154](https://github.com/mairie360/Database/pull/154))
- ci: MAIR-612 Release prod: align internal versions and deploy (#214) ([#214](https://github.com/mairie360/Database/pull/214))
- ci: MAIR-612 Release prod: align internal versions and deploy (#212) ([#212](https://github.com/mairie360/Database/pull/212))
- ci: MAIR-612 Release prod: align internal versions and deploy (#210) ([#210](https://github.com/mairie360/Database/pull/210))

## Différence dev → staging (en dev, pas encore en staging)

_Rien._

## Différence staging → prod (en staging, pas encore en prod)

- docs: MAIR-609 Core/BFF_user - Accès temporaire à la console Keycloak pour les admins de mairie (#224) ([#224](https://github.com/mairie360/Database/pull/224))
- fix: MAIR-497 RGPD - Simulation d'usage et revue IA des logs et de la base avant la prod ([#222](https://github.com/mairie360/Database/pull/222))
- ci: MAIR-771 APIs, BFFs, Database : monter CICD en v5.2.2 pour activer les contrôles RGPD (#218) ([#218](https://github.com/mairie360/Database/pull/218))
- fix: MAIR-739 Database : mettre à jour libbrotli1 dans l'image liquibase-migrations (CVE-2026-111497) (#216) ([#216](https://github.com/mairie360/Database/pull/216))
- feat: MAIR-500 Chiffrer les sauvegardes avec une clé par utilisateur, détruite à son effacement (#177) ([#177](https://github.com/mairie360/Database/pull/177))
- feat: MAIR-498 Service de conformité de l'instance : scan permanent, effacement centralisé et journal des fuites (#173) ([#173](https://github.com/mairie360/Database/pull/173))
- feat: MAIR-499 Rendre le TTL obligatoire sur Redis dans les APIs et les BFFs (#175) ([#175](https://github.com/mairie360/Database/pull/175))
- feat: MAIR-289 Anonymiser et exporter les données d'un utilisateur, avec tests d'effacement (#166) ([#166](https://github.com/mairie360/Database/pull/166))
- ci: MAIR-295 Ajouter une checklist RGPD aux PR et des rappels d'échéances automatiques (#168) ([#168](https://github.com/mairie360/Database/pull/168))
- fix: MAIR-286 Tester la conformité RGPD du schéma et exclure les mots de passe du journal d'audit (#164) ([#164](https://github.com/mairie360/Database/pull/164))
- docs: MAIR-285 Inventorier les données personnelles du schéma et tester sa complétude (#154) ([#154](https://github.com/mairie360/Database/pull/154))
- ci: MAIR-612 Release prod: align internal versions and deploy (#214) ([#214](https://github.com/mairie360/Database/pull/214))
- ci: MAIR-612 Release prod: align internal versions and deploy (#212) ([#212](https://github.com/mairie360/Database/pull/212))
- ci: MAIR-612 Release prod: align internal versions and deploy (#210) ([#210](https://github.com/mairie360/Database/pull/210))

> Résumé Claude indisponible pour ce passage : listes brutes des commits.

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
| 2026-11-12 22:33 UTC | staging | — | `c4fa2dd` | [run](https://github.com/mairie360/Database/actions/runs/43320791982) |
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
