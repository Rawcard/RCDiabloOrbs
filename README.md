# RC Diablo Orbs

Fully customizable Diablo-style health and power orbs for World of Warcraft.

Works on Retail, MoP Classic, Cata, Wrath and TBC (one folder, a TOC for each client).

## Install

Download the latest zip from [CurseForge](https://www.curseforge.com/wow/addons) or from this repository's **Releases** page, and put the `RCDiabloOrbs` folder in your `Interface\AddOns` folder.

## Credits and license

Maintained by **Raw Card**, who took the project over with John Rubin's permission after he stopped working on it in 2014.

RC Diablo Orbs is based on Mistra's D3Orbs by John Rubin ("Mistra"), itself a rewrite of oUF_D3Orbs, whose orbs first appeared in RothUI by Zork (used with the original author's permission). The original license header is kept at the top of `RCDiabloOrbs.lua`.

## Releasing (for the maintainer)

1. Update the version in every `.toc` file and add the notes to the top of `CHANGELOG.md`.
2. On GitHub: **Releases** → **Draft a new release** → **Choose a tag** → type `v` plus the version (for example `v2.1.8.5`) → **Create new tag on publish** → **Publish release**.
3. The **Package and release** job (Actions tab) builds the zip, attaches it to the release, and uploads it to CurseForge (project `1378641`). It needs the `CF_API_KEY` secret (Settings → Secrets and variables → Actions).
