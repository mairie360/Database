# Journal des releases — Database

<!-- release-journal-state {"dev": "d0f441ef3fed0deb979db9257cb996e688bd1e15", "prod": "c4fa2dd7dfaa01a0f41c90c5bf004dce5703b86c", "prod_tag": "v3.4.0", "staging": "c4fa2dd7dfaa01a0f41c90c5bf004dce5703b86c", "updated": {"dev": "2026-11-18 00:26 UTC", "prod": "2026-11-12 23:38 UTC", "staging": "2026-11-12 22:33 UTC"}} -->
> Tenu à jour par la CI (`mairie360/CICD`, action `release/release-journal`) à chaque passage en dev, staging et prod. Ne pas modifier à la main : le fichier est réécrit au passage suivant.

| Environnement | Version | Commit | Mis à jour |
| --- | --- | --- | --- |
| prod | v3.4.0 | `c4fa2dd` | 2026-11-12 23:38 UTC |
| staging | — | `c4fa2dd` | 2026-11-12 22:33 UTC |
| dev | — | `d0f441e` | 2026-11-18 00:26 UTC |

## Ajouté sur main depuis la dernière release prod (v3.4.0)

- feat: MAIR-683 Link groups to projects (#245) ([#245](https://github.com/mairie360/Database/pull/245))
- feat: MAIR-695 Detect refresh token reuse (#243) ([#243](https://github.com/mairie360/Database/pull/243))
- feat: MAIR-810 Passkeys managed by Core ([#239](https://github.com/mairie360/Database/pull/239))
- feat: MAIR-808 Make the two-factor authentication mandatory (instance policy) ([#235](https://github.com/mairie360/Database/pull/235))
- fix: MAIR-535 Fix the ACL of group-owned events and cover the secured views ([#241](https://github.com/mairie360/Database/pull/241))
- fix: MAIR-805 Upgrade apt in the migrations image (CVE-2026-109518) ([#240](https://github.com/mairie360/Database/pull/240))
- feat: MAIR-805 Two-factor authentication by authenticator app (TOTP) and backup codes in Core ([#233](https://github.com/mairie360/Database/pull/233))
- fix: MAIR-535 Fix the ACL of group-owned events and cover the secured views ([#238](https://github.com/mairie360/Database/pull/238))
- ci: MAIR-1008 Nightly rehearsal of the promotion gates (#231) ([#231](https://github.com/mairie360/Database/pull/231))
- test: MAIR-239 Cover check_access and the session triggers with pgTAP and make the coverage reliable (#226) ([#226](https://github.com/mairie360/Database/pull/226))
- ci: MAIR-1003 Release prod: align internal versions and deploy ([#228](https://github.com/mairie360/Database/pull/228))

## Différence dev → staging (en dev, pas encore en staging)

- feat: MAIR-683 Link groups to projects (#245) ([#245](https://github.com/mairie360/Database/pull/245))
- feat: MAIR-695 Detect refresh token reuse (#243) ([#243](https://github.com/mairie360/Database/pull/243))
- feat: MAIR-810 Passkeys managed by Core ([#239](https://github.com/mairie360/Database/pull/239))
- feat: MAIR-808 Make the two-factor authentication mandatory (instance policy) ([#235](https://github.com/mairie360/Database/pull/235))
- fix: MAIR-535 Fix the ACL of group-owned events and cover the secured views ([#241](https://github.com/mairie360/Database/pull/241))
- fix: MAIR-805 Upgrade apt in the migrations image (CVE-2026-109518) ([#240](https://github.com/mairie360/Database/pull/240))
- feat: MAIR-805 Two-factor authentication by authenticator app (TOTP) and backup codes in Core ([#233](https://github.com/mairie360/Database/pull/233))
- fix: MAIR-535 Fix the ACL of group-owned events and cover the secured views ([#238](https://github.com/mairie360/Database/pull/238))
- ci: MAIR-1008 Nightly rehearsal of the promotion gates (#231) ([#231](https://github.com/mairie360/Database/pull/231))
- test: MAIR-239 Cover check_access and the session triggers with pgTAP and make the coverage reliable (#226) ([#226](https://github.com/mairie360/Database/pull/226))
- ci: MAIR-1003 Release prod: align internal versions and deploy ([#228](https://github.com/mairie360/Database/pull/228))

## Différence staging → prod (en staging, pas encore en prod)

_Rien._

> Résumé Claude indisponible pour ce passage : listes brutes des commits.

## Historique des passages

<!-- release-journal-history:start -->
| Date | Environnement | Version | Commit | Run |
| --- | --- | --- | --- | --- |
| 2026-11-18 00:26 UTC | dev | — | `d0f441e` | [run](https://github.com/mairie360/Database/actions/runs/44207282376) |
| 2026-11-18 00:12 UTC | dev | — | `3e9706f` | [run](https://github.com/mairie360/Database/actions/runs/44205338422) |
| 2026-11-17 20:55 UTC | dev | — | `08b194d` | [run](https://github.com/mairie360/Database/actions/runs/44173631410) |
| 2026-11-17 19:34 UTC | dev | — | `d7266ca` | [run](https://github.com/mairie360/Database/actions/runs/44159239092) |
| 2026-11-17 19:05 UTC | dev | — | `7350c33` | [run](https://github.com/mairie360/Database/actions/runs/44153931776) |
| 2026-11-12 23:38 UTC | prod | v3.4.0 | `c4fa2dd` | [run](https://github.com/mairie360/Database/actions/runs/43330181912) |
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
