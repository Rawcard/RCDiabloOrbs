# RC Diablo Orbs

Fully customizable Diablo-style health and power orbs for World of Warcraft.

Works on Retail (Midnight), MoP Classic, Cata, Wrath, TBC Anniversary, Classic Era and WoW Forever (one folder, a TOC for each client).

On Retail and WoW Forever the game hides exact health and power from addons in combat; the orbs then fill from the game's readable percentage.

## Install

Download the latest zip from [CurseForge](https://www.curseforge.com/wow/addons) or from this repository's **Releases** page, and put the `RCDiabloOrbs` folder in your `Interface\AddOns` folder.

## Credits and license

Maintained by **Raw Card**, who took the project over with John Rubin's permission after he stopped working on it in 2014.

RC Diablo Orbs is based on Mistra's D3Orbs by John Rubin ("Mistra"), itself a rewrite of oUF_D3Orbs, whose orbs first appeared in RothUI by Zork (used with the original author's permission). The original license header is kept at the top of `RCDiabloOrbs.lua`.

## Tests

`pip install lupa && python3 tools/test_clients.py` loads the addon (TOC, XML frames and Lua) on a simulated copy of every client and class and plays a short session, with hidden combat values on Retail and WoW Forever. It runs on every push.

## Releasing (for the maintainer)

1. Update the version in every `.toc` file and `RC32_ADDON_VERSION` in `RCDiabloOrbs.lua`, and put the notes in `CHANGELOG.md`.
2. On GitHub: **Releases** → **Draft a new release** → **Choose a tag** → type `v` plus the version (for example `v2.1.8.5`) → **Create new tag on publish** → **Publish release**.
3. The **Package and release** job (Actions tab) builds the zip, attaches it to the release, and uploads it to CurseForge (project `1378641`). It needs the `CF_API_KEY` secret (Settings → Secrets and variables → Actions).
