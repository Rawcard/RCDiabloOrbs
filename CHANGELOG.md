# RC Diablo Orbs 2.1.8.7

- **WoW Forever** is now listed on CurseForge, so the CurseForge app offers it to Forever players. (The addon already worked on Forever since 2.1.8.5.)

## RC Diablo Orbs 2.1.8.6

- **Wrath Titan Reforged supported** (client 3.80), checked in the Chinese game language.
- Warlock resources (Soul Shards, Burning Embers, Demonic Fury) are now detected in every game language; they looked spells up by their English names.
- Release jobs updated to GitHub's newer Node 24 actions (no more Node.js 20 warning).

## RC Diablo Orbs 2.1.8.5

Works on every WoW client: Retail (Midnight), MoP Classic, Cata, Wrath, TBC Anniversary, Classic Era and WoW Forever.

- **Retail and WoW Forever:** the orbs keep working in combat. These clients hide your exact health and power from addons during combat; the orbs now fill from the game's readable percentage instead, and the numbers on them still show.
- **Retail:** fixed errors at login (spell and aura functions Retail removed, and the combat log, which Retail no longer lets addons use). This also brings back the DoT tracker and the Battle Rez panel there.
- **Retail:** Demon Hunter and Evoker no longer break the addon at login, and have their own orb colors.
- **Retail:** Warlocks track Soul Shards in every spec.
- **Classic Era and WoW Forever:** now supported (new TOC files).
- Class detection works in every game language, not just English.
- Combo points, Holy Power, Chi and Soul Shards keep updating in combat on Retail and WoW Forever.
- Tooltips, the DoT tracker and the Battle Rez panel no longer error on values Retail and WoW Forever hide in combat.
- Fixed the options window sliders using an old function some clients no longer have.
