-- /fsim, /fus and every route open the one ForeverSim window.
-- Overview, Talente and Rotation Style are its tabs; everything else is drawn on the "Mehr" page
-- of the same window (UI/Shell.lua only supplies the views, it has no frame of its own).
local P = FUSLive
local App, D = P.app, P.dashboard
if not App or not D then return end
local open = App.Open
function App.Open(tab, subtab, key)
    if InCombatLockdown and InCombatLockdown() then App.deferred = {tab, subtab, key}; return end
    if tab == nil or tab == 'overview' or tab == 'rotation' or tab == 'talents' or tab == 'quests' then
        D.Show(tab == 'talents' and 'talents' or tab == 'rotation' and 'style' or tab == 'quests' and 'quests' or 'overview')
        return
    end
    D.Show('more')
    return open(tab, subtab, key)
end
function App.Toggle() D.Toggle() end
local hide = App.Hide
function App.Hide() D.Hide(); hide() end
if P.dashboardUI then P.dashboardUI.Show = App.Open; P.dashboardUI.Toggle = App.Toggle end
