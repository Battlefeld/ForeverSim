"""Permissive WoW client mock that loads the whole ForeverSim addon and records UI state.

Used by test_window_ui.py (smoke test) and render_window.py (PNG preview of the real Lua layout).
Every frame, texture and font string keeps what the addon set on it: anchors, size, textures,
colours, text and visibility.
"""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent

MOCK = r'''
frames = {}
local methods = {}
local noop = function() end
local function new(kind, parent, layer)
    local f = setmetatable({scripts = {}, events = {}, shown = true, parent = parent, kind = kind, layer = layer, points = {}, alpha = 1},
        {__index = function(_, k) return methods[k] or (type(k) == 'string' and k:match('^[A-Z]') and noop or nil) end})
    frames[#frames + 1] = f
    return f
end
function methods:SetText(t) self.text = t end
function methods:GetText() return self.text end
function methods:SetScript(k, f) self.scripts[k] = f end
function methods:GetScript(k) return self.scripts[k] end
function methods:HookScript(k, f) local prev = self.scripts[k]; self.scripts[k] = function(...) if prev then prev(...) end; f(...) end end
function methods:RegisterEvent(e) self.events[e] = true end
function methods:SetPoint(...) self.points[#self.points + 1] = {...} end
function methods:ClearAllPoints() self.points = {}; self.allPoints = nil end
function methods:SetAllPoints(rel) self.allPoints = rel or true end
function methods:SetSize(w, h) self.width = w; self.height = h end
function methods:SetWidth(w) self.width = w end
function methods:SetHeight(h) self.height = h end
function methods:GetWidth() return self.width or 1920 end
function methods:GetHeight() return self.height or 1080 end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(v) self.shown = v and true or false end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:SetParent(p) self.parent = p end
function methods:GetFrameLevel() return 1 end
function methods:GetEffectiveScale() return 1 end
function methods:GetStringWidth() return math.floor(#(self.text or '') * (self.fontSize or 12) * .55) end
function methods:SetFont(_, size) self.fontSize = size end
function methods:GetFont() return 'Fonts\\FRIZQT__.TTF', self.fontSize or 12, '' end
function methods:SetFontObject() end
function methods:SetJustifyH(j) self.justifyH = j end
function methods:SetJustifyV(j) self.justifyV = j end
function methods:SetTextColor(r, g, b, a) self.textColor = {r, g, b, a or 1} end
function methods:SetTexture(path) if type(path) == 'string' or type(path) == 'number' then self.file = path; self.color = nil else self.file = nil end end
function methods:SetColorTexture(r, g, b, a) self.color = {r, g, b, a or 1}; self.file = nil end
function methods:SetVertexColor(r, g, b, a) self.vertex = {r, g, b, a or 1} end
function methods:SetAlpha(a) self.alpha = a end
function methods:SetDesaturated(v) self.desaturated = v end
function methods:SetTexCoord(...) self.texCoord = {...} end
function methods:SetBackdrop(b) self.backdrop = b end
function methods:SetBackdropColor(r, g, b, a) self.bdColor = {r, g, b, a or 1} end
function methods:SetBackdropBorderColor(r, g, b, a) self.bdBorder = {r, g, b, a or 1} end
function methods:SetNormalTexture(path) local t = self:CreateTexture(nil, 'ARTWORK'); t:SetTexture(path); t:SetAllPoints() end
function methods:SetThumbTexture(t) self.thumb = t end
function methods:SetMinMaxValues(a, b) self.minV, self.maxV = a, b end
function methods:SetChecked(v) self.checked = v end
function methods:GetChecked() return self.checked end
function methods:SetValue(v) self.value = v; if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end end
function methods:GetValue() return self.value end
function methods:SetEnabled(v) self.enabled = v end
function methods:GetCenter() return 0, 0 end
function methods:CreateFontString(_, layer) return new('FontString', self, layer or 'OVERLAY') end
function methods:CreateTexture(_, layer) return new('Texture', self, layer or 'ARTWORK') end
function methods:CreateLine(_, layer) return new('Line', self, layer or 'ARTWORK') end
function methods:CreateAnimationGroup() local g = new('Anim', nil); function g:CreateAnimation() return new('Anim', nil) end; return g end
function CreateFrame(kind, name, parent, template)
    local f = new(kind or 'Frame', parent)
    f.template = template
    if template == 'UICheckButtonTemplate' then
        local box = f:CreateTexture(nil, 'BACKGROUND'); box:SetColorTexture(.05, .05, .06, 1); box:SetAllPoints(); box.checkBox = true
    end
    if name then _G[name] = f end
    return f
end
UIParent = CreateFrame(); UIParent.width, UIParent.height = 1920, 1080
GameTooltip = CreateFrame()
GameFontNormal = CreateFrame()
SlashCmdList = {}
level, inCombat = 60, false
function UnitLevel() return level end
function UnitClass() return 'Jäger', 'HUNTER' end
function UnitName() return 'Test' end
function UnitRace() return 'Orc', 'Orc' end
function UnitFactionGroup() return 'Horde' end
function UnitExists(unit) return unit == 'player' or unit == 'target' end
function UnitHealth() return 1000 end
function UnitHealthMax() return 1000 end
function UnitPower() return 500 end
function UnitPowerMax() return 1000 end
function GetTime() return 100 end
function InCombatLockdown() return inCombat end
function GetInventorySlotInfo(name) return 1, 'Interface\\PaperDoll\\UI-PaperDoll-Slot-Head' end
function GetInventoryItemTexture() return 'Interface\\Icons\\INV_Helmet_08' end
function GetInventoryItemQuality() return 3 end
function GetActionInfo(slot) if slot == 3 then return 'spell', 19434 end end
function GetBindingKey(cmd) if cmd == 'ACTIONBUTTON3' then return '3' end end
function IsSpellInRange() return 1 end
'''


def load_addon():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCK)
    compile_lua = lua.eval('function(s, n) local f, e = loadstring(s, n); assert(f, e); return f end')
    for line in (ROOT / 'ForeverSimBridge.toc').read_text(encoding='utf-8-sig').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        compile_lua((ROOT / line.replace('\\', '/')).read_text(encoding='utf-8-sig'), '@' + line)()
    return lua
