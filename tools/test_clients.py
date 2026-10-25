#!/usr/bin/env python3
"""Load RC Diablo Orbs on every WoW client and every class, the way the game
would (TOC -> XML -> Lua, XML frames and their scripts), and play a short
session: login, out of combat, a fight (with secret values on Retail and WoW
Forever), target and pet changes, the options window and slash commands.

  pip install lupa
  python3 tools/test_clients.py            all clients
  python3 tools/test_clients.py retail     one client

Fails on any Lua error.
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

import lupa.luajit21 as lupa_mod

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

CLASSIC9 = [("WARRIOR", 1), ("PALADIN", 2), ("HUNTER", 3), ("ROGUE", 4), ("PRIEST", 5), ("SHAMAN", 7), ("MAGE", 8), ("WARLOCK", 9), ("DRUID", 11)]
DK = [("DEATHKNIGHT", 6)]
MONK = [("MONK", 10)]
RETAIL_EXTRA = [("DEMONHUNTER", 12), ("EVOKER", 13)]

# flavor -> (TOC file, interface number, classes)
CLIENTS = {
    "era": ("RCDiabloOrbs_Vanilla.toc", 11508, CLASSIC9),
    "tbc": ("RCDiabloOrbs_TBC.toc", 20505, CLASSIC9),
    "wrath": ("RCDiabloOrbs_Wrath.toc", 30405, CLASSIC9 + DK),
    "cata": ("RCDiabloOrbs_Cata.toc", 40402, CLASSIC9 + DK),
    "mists": ("RCDiabloOrbs.toc", 50504, CLASSIC9 + DK + MONK),
    "retail": ("RCDiabloOrbs_Mainline.toc", 120005, CLASSIC9 + DK + MONK + RETAIL_EXTRA),
    "forever": ("RCDiabloOrbs_Camelot.toc", 16001, CLASSIC9),
}

ARGS = {
    "OnLoad": "self", "OnShow": "self", "OnHide": "self", "OnClick": "self, button, down",
    "OnEnter": "self, motion", "OnLeave": "self, motion", "OnMouseDown": "self, button", "OnMouseUp": "self, button",
    "OnValueChanged": "self, value, userInput", "OnDragStart": "self, button", "OnDragStop": "self",
    "OnUpdate": "self, elapsed", "OnEvent": "self, event, ...", "OnTextChanged": "self, userInput",
    "OnEnterPressed": "self", "OnEscapePressed": "self",
}
FRAME_TAGS = {"Frame", "Button", "CheckButton", "Slider", "EditBox", "ScrollFrame", "StatusBar", "GameTooltip", "Cooldown", "Model"}
REGION_TAGS = {"Texture", "FontString", "HighlightTexture", "NormalTexture", "PushedTexture", "CheckedTexture", "DisabledTexture"}
TEMPLATE_CHILDREN = ["Text", "Low", "High", "Button", "Left", "Middle", "Right", "Icon", "TextLeft1", "TextRight1"]


def strip(tag):
    return tag.split("}", 1)[-1]


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n") + '"'


def xml_to_lua(path):
    """Turn a WoW UI XML file into Lua that builds the same named frames."""
    tree = ET.parse(path)
    out = []
    loads = []
    counter = [0]

    def var():
        counter[0] += 1
        return "f%d" % counter[0]

    def walk(el, parent_var, parent_name):
        tag = strip(el.tag)
        if tag == "Script":
            f = el.get("file")
            if f:
                out.append("LOADFILE(%s)" % lua_str(f))
            elif el.text and el.text.strip():
                out.append("RUNCHUNK(%s, %s)" % (lua_str(el.text), lua_str(os.path.basename(path))))
            return
        if tag in FRAME_TAGS or tag in REGION_TAGS:
            name = el.get("name")
            if name and parent_name:
                name = name.replace("$parent", parent_name).replace("$Parent", parent_name)
            v = var()
            nm = lua_str(name) if name else "nil"
            if tag in FRAME_TAGS:
                parent = el.get("parent")
                pv = "_G[%s]" % lua_str(parent) if parent else (parent_var or "UIParent")
                out.append("local %s = CreateFrame(%s, %s, %s, %s)" % (v, lua_str(tag), nm, pv, lua_str(el.get("inherits") or "")))
                if el.get("hidden") != "true":
                    out.append("%s.shown = true" % v)
            else:
                out.append("local %s = %s:Create%s(%s)" % (v, parent_var or "UIParent", "FontString" if tag == "FontString" else "Texture", nm))
                if name:
                    out.append("_G[%s] = %s" % (lua_str(name), v))
            if el.get("parentKey"):
                owner = "_G[%s]" % lua_str(el.get("parent")) if el.get("parent") else parent_var
                if owner:
                    out.append("%s[%s] = %s" % (owner, lua_str(el.get("parentKey")), v))
            if name and el.get("inherits"):
                for child in TEMPLATE_CHILDREN:
                    out.append("if not _G[%s] then _G[%s] = CreateFrame('Frame', nil, %s) end" % (
                        lua_str(name + child), lua_str(name + child), v))
                out.append("%s.Text = _G[%s]" % (v, lua_str(name + "Text")))
            for child in el:
                ctag = strip(child.tag)
                if ctag == "Scripts":
                    for sc in child:
                        stag = strip(sc.tag)
                        body = sc.text or ""
                        fn = sc.get("function")
                        if fn:
                            out.append("%s:SetScript(%s, function(...) return _G[%s](...) end)" % (v, lua_str(stag), lua_str(fn)))
                        elif body.strip():
                            args = ARGS.get(stag, "self, ...")
                            out.append("%s:SetScript(%s, COMPILE(%s, %s, %s))" % (
                                v, lua_str(stag), lua_str(args), lua_str(body), lua_str("%s:%s" % (name or tag, stag))))
                            if stag == "OnLoad":
                                loads.append(v)
                else:
                    walk(child, v, name or parent_name)
            return
        for child in el:
            walk(child, parent_var, parent_name)

    walk(tree.getroot(), None, None)
    # OnLoad runs after the frame and its children exist
    body = "\n".join(out)
    body += "\n" + "\n".join("ONLOAD(%s)" % v for v in loads)
    return "do\n" + body + "\nend\n"


XML_NAMES = set()

RUN = r"""
local ADDON = "RCDiabloOrbs"
local function chunkFor(file)
	local f = assert(io.open(ADDON_DIR .. "/" .. file, "rb"))
	local src = f:read("*a"); f:close()
	src = src:gsub("^\239\187\191", "")
	return src
end
function LOADFILE(file)
	local fn, err = loadstring(chunkFor(file), "@" .. file)
	if not fn then error("LOAD " .. file .. ": " .. tostring(err)) end
	local ok, e = pcall(fn, ADDON, NS)
	if not ok then error("LOAD " .. file .. ": " .. tostring(e)) end
end
function RUNCHUNK(src, name)
	local fn = assert(loadstring(src, "@" .. name))
	fn(ADDON, NS)
end
function COMPILE(args, body, name)
	local fn, err = loadstring("return function(" .. args .. ")\n" .. body .. "\nend", "@" .. name)
	if not fn then error("XML script " .. name .. ": " .. tostring(err)) end
	return fn()
end
function ONLOAD(f)
	local fn = f.scripts.OnLoad
	if fn then
		local ok, err = pcall(fn, f)
		if not ok then error("OnLoad " .. tostring(f.__gname) .. ": " .. tostring(err)) end
	end
end
NS = {}

local function fire(ev, ...)
	for _, f in ipairs(ALLFRAMES) do
		local fn = f.scripts.OnEvent
		if fn and (not f.events or f.events[ev]) then
			local ok, err = pcall(fn, f, ev, ...)
			if not ok then error("EVENT " .. ev .. " (" .. tostring(f.__gname) .. "): " .. tostring(err)) end
		end
	end
end
FIRE = fire
local function update(dt)
	local due = TIMERS
	TIMERS = {}
	for _, fn in ipairs(due) do
		local ok, err = pcall(fn)
		if not ok then error("timer: " .. tostring(err)) end
	end
	for i = 1, #ALLFRAMES do
		local f = ALLFRAMES[i]
		local fn = f.scripts.OnUpdate
		if fn and f.shown then
			local ok, err = pcall(fn, f, dt)
			if not ok then error("OnUpdate (" .. tostring(f.__gname) .. "): " .. tostring(err)) end
		end
	end
end
local function step(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then error(label .. ": " .. tostring(err)) end
end

-- load the TOC's files in order
for line in io.lines(ADDON_DIR .. "/" .. TOC_FILE) do
	line = line:gsub("\r", ""):gsub("^\239\187\191", "")
	if line ~= "" and not line:match("^#") then
		if line:match("%.xml$") then
			local code = XML[line]
			assert(code, "no XML loader output for " .. line)
			local fn, err = loadstring(code, "@" .. line)
			if not fn then error("XML " .. line .. ": " .. tostring(err)) end
			step("XML " .. line, fn)
		elseif line:match("%.lua$") then
			LOADFILE(line)
		end
	end
end

fire("ADDON_LOADED", ADDON)
fire("VARIABLES_LOADED")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
fire("PLAYER_SPECIALIZATION_CHANGED", "player")
for i = 1, 10 do NOW = NOW + 0.1; update(0.1) end

-- out of combat, then a target and a pet
TARGET = true; fire("PLAYER_TARGET_CHANGED")
PET = true; fire("UNIT_PET", "player")
for i = 1, 10 do NOW = NOW + 0.1; update(0.1) end

-- a fight
COMBAT = true
fire("PLAYER_REGEN_DISABLED")
fire("PLAYER_ENTER_COMBAT")
for t = 1, 60 do
	NOW = NOW + 0.1
	if t % 10 == 0 then
		HEALTH = HEALTH - 700; POWER = (POWER + 13) % 100
		fire("UNIT_HEALTH", "player"); fire("UNIT_POWER_UPDATE", "player", "MANA"); fire("UNIT_POWER_FREQUENT", "player", "MANA")
		fire("UNIT_HEALTH", "target"); fire("UNIT_AURA", "target"); fire("UNIT_AURA", "player")
		fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 116)
		fire("UNIT_COMBO_POINTS", "player")
	end
	if t == 30 then TARGET = false; fire("PLAYER_TARGET_CHANGED") end
	if t == 35 then TARGET = true; fire("PLAYER_TARGET_CHANGED") end
	update(0.1)
end
COMBAT = false
fire("PLAYER_REGEN_ENABLED")
fire("PLAYER_LEAVE_COMBAT")
for i = 1, 10 do NOW = NOW + 0.1; update(0.1) end

-- the options window and every slash command it registered
if RC32GUI then
	step("open options", function() RC32GUI:Show() end)
	for i = 1, 3 do update(0.1) end
	step("close options", function() RC32GUI:Hide() end)
end
local cmds = {}
for k in pairs(SlashCmdList) do cmds[#cmds + 1] = k end
table.sort(cmds)
for _, k in ipairs(cmds) do
	for _, arg in ipairs({ "", "test", "reset" }) do
		step("slash " .. k .. " " .. arg, SlashCmdList[k], arg)
		update(0.1)
	end
end
update(0.1)

local missing = {}
for k in pairs(MISSING) do missing[#missing + 1] = k end
table.sort(missing)
REPORT_MISSING = table.concat(missing, " ")
"""


def run(flavor, cls, cid, xml_code):
    toc, build, _ = CLIENTS[flavor]
    L = lupa_mod.LuaRuntime(unpack_returned_tuples=True)
    g = L.globals()
    g.ADDON_DIR = ROOT
    g.TOC_FILE = toc
    g.BUILD_TOC = build
    g.FLAVOR = flavor
    g.CLASS_FILE = cls
    g.CLASS_ID = cid
    L.execute(open(os.path.join(ROOT, "tools", "wow_env.lua"), encoding="utf-8").read())
    xml_table = L.eval("{}")
    for k, v in xml_code.items():
        xml_table[k] = v
    g.XML = xml_table
    names = L.eval("{}")
    for n in XML_NAMES:
        names[n] = True
    g.XMLNAMES = names
    L.execute(RUN)
    return str(g.REPORT_MISSING)


def main():
    flavors = sys.argv[1:] or list(CLIENTS)
    xml_code = {}
    for fn in os.listdir(ROOT):
        if fn.endswith(".xml"):
            xml_code[fn] = xml_to_lua(os.path.join(ROOT, fn))
            XML_NAMES.update(re.findall(r'name="([A-Za-z_][A-Za-z0-9_]*)"', open(os.path.join(ROOT, fn), encoding="utf-8-sig").read()))
    failed = 0
    for flavor in flavors:
        toc = CLIENTS[flavor][0]
        if not os.path.exists(os.path.join(ROOT, toc)):
            failed += 1
            print("FAIL %-7s no %s" % (flavor, toc))
            continue
        missing = set()
        bad = []
        for cls, cid in CLIENTS[flavor][2]:
            try:
                missing.update(run(flavor, cls, cid, xml_code).split())
            except Exception as e:  # noqa: BLE001
                bad.append((cls, str(e).split("\nstack traceback")[0][:500]))
        if bad:
            failed += 1
            print("FAIL %-7s %d/%d classes" % (flavor, len(bad), len(CLIENTS[flavor][2])))
            seen = set()
            for cls, err in bad:
                if err in seen:
                    print("       %-11s (same)" % cls)
                    continue
                seen.add(err)
                print("       %-11s %s" % (cls, err))
        else:
            print("OK   %-7s all %d classes" % (flavor, len(CLIENTS[flavor][2])))
        if missing and os.environ.get("SHOW_MISSING"):
            print("       not modelled: " + " ".join(sorted(missing)))
    print("ALL PASS" if not failed else "%d FAILED" % failed)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
