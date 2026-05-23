PeakBridge = PeakBridge or {}
PeakBridge.Client = PeakBridge.Client or {
    Ready = false,
    FrameworkName = 'standalone',
    FrameworkObject = nil,
    FrameworkShared = nil,
    NotifySystem = 'native',
    TargetSystem = nil,
    ProgressSystem = 'wait',
    AppearanceSystem = nil,
    PendingCallbacks = {},
    CallbackId = 0,
}

local Config = PeakBridge.Config
local Shared = PeakBridge.Shared

local function detectFramework()
    local configured = Shared.NormalizeName(Config.Framework)
    if configured and configured ~= 'auto' then return configured end
    if Shared.IsStarted('qbx_core') then return 'qbox' end
    if Shared.IsStarted('qb-core') then return 'qbcore' end
    if Shared.IsStarted('es_extended') then return 'esx' end
    if Shared.IsStarted('ox_core') then return 'ox' end
    if Shared.IsStarted('vrp') then return 'vrp' end
    return 'standalone'
end

local function makeQboxObject()
    local ok, obj = pcall(function() return exports.qbx_core:GetCoreObject() end)
    if ok and obj then return obj, obj.Shared end

    local qbx = exports.qbx_core
    local object = {
        Functions = setmetatable({}, {
            __index = function(_, key)
                if key == 'GetPlayerData' then
                    return function()
                        if rawget(_G, 'QBX') and QBX.PlayerData then return QBX.PlayerData end
                        local ok2, data = pcall(qbx.GetPlayerData, qbx)
                        return (ok2 and data) or {}
                    end
                end
                return function(...)
                    return qbx[key](qbx, ...)
                end
            end
        })
    }
    return object, nil
end

local function initializeFramework()
    local fw = detectFramework()
    PeakBridge.Client.FrameworkName = fw

    if fw == 'qbcore' and Shared.IsStarted('qb-core') then
        PeakBridge.Client.FrameworkObject = exports['qb-core']:GetCoreObject()
        PeakBridge.Client.FrameworkShared = PeakBridge.Client.FrameworkObject.Shared
    elseif fw == 'qbox' and Shared.IsStarted('qbx_core') then
        PeakBridge.Client.FrameworkObject, PeakBridge.Client.FrameworkShared = makeQboxObject()
    elseif fw == 'esx' and Shared.IsStarted('es_extended') then
        PeakBridge.Client.FrameworkObject = exports.es_extended:getSharedObject()
    end
end

local function detectNotify()
    local configured = Shared.NormalizeName(Config.Notify)
    if configured and configured ~= 'auto' then return configured end
    if Shared.IsStarted('ox_lib') then return 'ox_lib' end
    if Shared.IsStarted('qb-core') then return 'qb-core' end
    if Shared.IsStarted('es_extended') then return 'esx' end
    return 'native'
end

local function detectTarget()
    local configured = Shared.NormalizeName(Config.Target)
    if configured and configured ~= 'auto' then return configured ~= 'none' and configured or nil end
    if Shared.IsStarted('ox_target') then return 'ox_target' end
    if Shared.IsStarted('qb-target') then return 'qb-target' end
    return nil
end

local function detectProgress()
    local configured = Shared.NormalizeName(Config.Progress)
    if configured and configured ~= 'auto' then return configured end
    if Shared.IsStarted('ox_lib') then return 'ox_lib' end
    if Shared.IsStarted('progressbar') then return 'progressbar' end
    return 'wait'
end

local function detectAppearance()
    local configured = Shared.NormalizeName(Config.Appearance)
    if configured and configured ~= 'auto' then return configured ~= 'none' and configured or nil end
    local systems = { 'illenium-appearance', 'fivem-appearance', 'qb-clothing', 'rcore_clothing', 'skinchanger' }
    for _, system in ipairs(systems) do
        if Shared.IsStarted(system) then return system end
    end
    return nil
end

function PeakBridge.Client.TriggerCallback(name, ...)
    local p = promise.new()
    PeakBridge.Client.CallbackId = PeakBridge.Client.CallbackId + 1
    local id = PeakBridge.Client.CallbackId
    PeakBridge.Client.PendingCallbacks[id] = p
    TriggerServerEvent('peak-bridge:server:triggerCallback', id, name, ...)

    SetTimeout(Config.CallbackTimeout or 15000, function()
        if PeakBridge.Client.PendingCallbacks[id] then
            PeakBridge.Client.PendingCallbacks[id]:reject(('Callback timeout: %s'):format(tostring(name)))
            PeakBridge.Client.PendingCallbacks[id] = nil
        end
    end)

    return Citizen.Await(p)
end

RegisterNetEvent('peak-bridge:client:callbackResponse', function(id, data)
    local p = PeakBridge.Client.PendingCallbacks[id]
    if not p then return end
    p:resolve(data)
    PeakBridge.Client.PendingCallbacks[id] = nil
end)

function PeakBridge.Client.GetPlayerData()
    local fw = PeakBridge.Client.FrameworkName
    local obj = PeakBridge.Client.FrameworkObject
    if (fw == 'qbcore' or fw == 'qbox') and obj and obj.Functions and obj.Functions.GetPlayerData then
        return obj.Functions.GetPlayerData()
    elseif fw == 'esx' and obj and obj.GetPlayerData then
        return obj.GetPlayerData()
    elseif fw == 'ox' and Shared.IsStarted('ox_core') then
        local ok, data = pcall(function() return exports.ox_core:GetPlayerData() end)
        return ok and data or nil
    end
    return nil
end

function PeakBridge.Client.GetPlayerJob()
    local data = PeakBridge.Client.GetPlayerData()
    if not data or not data.job then
        return { name = 'unemployed', label = 'Unemployed', grade = 0, grade_name = '' }
    end
    local job = data.job
    local grade = job.grade or {}
    if type(grade) == 'table' then
        return {
            name = job.name or 'unemployed',
            label = job.label or job.name or 'Unemployed',
            grade = grade.level or grade.grade or 0,
            grade_name = grade.name or '',
        }
    end
    return {
        name = job.name or 'unemployed',
        label = job.label or job.name or 'Unemployed',
        grade = grade or 0,
        grade_name = job.grade_name or '',
    }
end

function PeakBridge.Client.Notify(text, notifyType, duration, title)
    notifyType = notifyType or 'info'
    duration = duration or 5000
    local system = PeakBridge.Client.NotifySystem

    if system == 'ox_lib' and lib and lib.notify then
        local oxType = notifyType == 'info' and 'inform' or notifyType
        lib.notify({ title = title or 'Notification', description = text, type = oxType, duration = duration })
    elseif system == 'qb-core' and PeakBridge.Client.FrameworkObject and PeakBridge.Client.FrameworkObject.Functions then
        local qbType = notifyType == 'info' and 'primary' or (notifyType == 'warning' and 'error' or notifyType)
        PeakBridge.Client.FrameworkObject.Functions.Notify(text, qbType, duration)
    elseif system == 'esx' and PeakBridge.Client.FrameworkObject and PeakBridge.Client.FrameworkObject.ShowNotification then
        PeakBridge.Client.FrameworkObject.ShowNotification(text)
    else
        SetNotificationTextEntry('STRING')
        AddTextComponentSubstringPlayerName(text)
        DrawNotification(false, false)
    end
end

function PeakBridge.Client.ProgressBar(label, duration, settings)
    settings = settings or {}
    duration = tonumber(duration) or 1000
    local system = PeakBridge.Client.ProgressSystem

    if system == 'ox_lib' and lib and lib.progressBar then
        local options = {
            duration = duration,
            label = label,
            useWhileDead = settings.useWhileDead == true,
            canCancel = settings.canCancel ~= false,
            disable = {
                move = settings.disableMove ~= false,
                car = settings.disableCarMove ~= false,
                combat = settings.disableCombat ~= false,
            },
        }
        if settings.dict and settings.anim then
            options.anim = { dict = settings.dict, clip = settings.anim }
        end
        if settings.prop then
            options.prop = {
                model = settings.prop,
                bone = settings.bone or 57005,
                pos = settings.propPos or vec3(0.0, 0.0, 0.0),
                rot = settings.propRot or vec3(0.0, 0.0, 0.0),
            }
        end
        return lib.progressBar(options) == true
    elseif system == 'progressbar' and exports.progressbar then
        local p = promise.new()
        exports.progressbar:Progress({
            name = 'peak_bridge_progress',
            duration = duration,
            label = label,
            useWhileDead = settings.useWhileDead == true,
            canCancel = settings.canCancel ~= false,
            controlDisables = {
                disableMovement = settings.disableMove ~= false,
                disableCarMovement = settings.disableCarMove ~= false,
                disableCombat = settings.disableCombat ~= false,
            },
            animation = settings.dict and settings.anim and { animDict = settings.dict, anim = settings.anim } or nil,
            prop = settings.prop and { model = settings.prop, bone = settings.bone or 57005 } or nil,
        }, function(cancelled)
            p:resolve(not cancelled)
        end)
        return Citizen.Await(p)
    end

    Wait(duration)
    return true
end

function PeakBridge.Client.ShowTextUI(text, position)
    position = position or 'right-center'
    if Shared.IsStarted('ox_lib') and lib and lib.showTextUI then
        lib.showTextUI(text, { position = position })
    elseif PeakBridge.Client.FrameworkName == 'qbcore' or PeakBridge.Client.FrameworkName == 'qbox' then
        pcall(function() exports['qb-core']:DrawText(text, position) end)
    elseif PeakBridge.Client.FrameworkName == 'esx' and PeakBridge.Client.FrameworkObject and PeakBridge.Client.FrameworkObject.TextUI then
        PeakBridge.Client.FrameworkObject.TextUI(text)
    end
end

function PeakBridge.Client.HideTextUI()
    if Shared.IsStarted('ox_lib') and lib and lib.hideTextUI then
        lib.hideTextUI()
    elseif PeakBridge.Client.FrameworkName == 'qbcore' or PeakBridge.Client.FrameworkName == 'qbox' then
        pcall(function() exports['qb-core']:HideText() end)
    elseif PeakBridge.Client.FrameworkName == 'esx' and PeakBridge.Client.FrameworkObject and PeakBridge.Client.FrameworkObject.HideUI then
        PeakBridge.Client.FrameworkObject.HideUI()
    end
end

function PeakBridge.Client.GetAppearance()
    local system = PeakBridge.Client.AppearanceSystem
    local ped = PlayerPedId()
    if system == 'illenium-appearance' or system == 'fivem-appearance' then
        local ok, data = pcall(function() return exports[system]:getPedAppearance(ped) end)
        return ok and data or nil
    elseif system == 'rcore_clothing' then
        local ok, data = pcall(function() return exports['rcore_clothing']:getPlayerSkin(false) end)
        return ok and data or nil
    elseif system == 'skinchanger' then
        local p = promise.new()
        TriggerEvent('skinchanger:getSkin', function(skin) p:resolve(skin) end)
        return Citizen.Await(p)
    end
    return nil
end

function PeakBridge.Client.SaveAppearance()
    local system = PeakBridge.Client.AppearanceSystem
    local appearance = PeakBridge.Client.GetAppearance()
    if not appearance then return false end

    if system == 'illenium-appearance' then
        TriggerServerEvent('illenium-appearance:server:saveAppearance', appearance)
        return true
    elseif system == 'fivem-appearance' then
        TriggerServerEvent('fivem-appearance:save', appearance)
        return true
    elseif system == 'rcore_clothing' then
        local ok = pcall(function() exports['rcore_clothing']:setPlayerSkin(appearance, false) end)
        return ok
    elseif system == 'skinchanger' then
        TriggerServerEvent('skinchanger:save', appearance)
        return true
    elseif system == 'qb-clothing' then
        TriggerEvent('qb-clothing:client:saveCurrentClothes')
        return true
    end
    return false
end

function PeakBridge.Client.ReloadAppearance()
    local system = PeakBridge.Client.AppearanceSystem
    if system == 'illenium-appearance' or system == 'fivem-appearance' then
        TriggerEvent(system .. ':client:reloadSkin')
        return true
    elseif system == 'qb-clothing' then
        local ok = pcall(function() exports['qb-clothing']:reloadSkin() end)
        return ok
    elseif system == 'rcore_clothing' then
        TriggerServerEvent('rcore_clothing:reloadSkin')
        return true
    elseif system == 'skinchanger' then
        local skin = PeakBridge.Client.GetAppearance()
        if skin then
            TriggerEvent('skinchanger:loadSkin', skin)
            return true
        end
    end
    return false
end

function PeakBridge.Client.LoadModel(model)
    local hash = type(model) == 'number' and model or GetHashKey(model)
    if not IsModelInCdimage(hash) then return false end
    RequestModel(hash)
    while not HasModelLoaded(hash) do Wait(0) end
    return hash
end

function PeakBridge.Client.LoadAnimDict(dict)
    if not dict or not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(0) end
    return true
end

exports('IsReady', function() return PeakBridge.Client.Ready end)
exports('GetFrameworkName', function() return PeakBridge.Client.FrameworkName end)
exports('GetFramework', function() return PeakBridge.Client.FrameworkObject end)
exports('TriggerCallback', function(...) return PeakBridge.Client.TriggerCallback(...) end)
exports('GetPlayerData', function(...) return PeakBridge.Client.GetPlayerData(...) end)
exports('GetPlayerJob', function(...) return PeakBridge.Client.GetPlayerJob(...) end)
exports('Notify', function(...) return PeakBridge.Client.Notify(...) end)
exports('ProgressBar', function(...) return PeakBridge.Client.ProgressBar(...) end)
exports('ShowTextUI', function(...) return PeakBridge.Client.ShowTextUI(...) end)
exports('HideTextUI', function(...) return PeakBridge.Client.HideTextUI(...) end)
exports('SaveAppearance', function(...) return PeakBridge.Client.SaveAppearance(...) end)
exports('ReloadAppearance', function(...) return PeakBridge.Client.ReloadAppearance(...) end)
exports('GetAppearance', function(...) return PeakBridge.Client.GetAppearance(...) end)
exports('LoadModel', function(...) return PeakBridge.Client.LoadModel(...) end)
exports('LoadAnimDict', function(...) return PeakBridge.Client.LoadAnimDict(...) end)

CreateThread(function()
    Wait(500)
    initializeFramework()
    PeakBridge.Client.NotifySystem = detectNotify()
    PeakBridge.Client.TargetSystem = detectTarget()
    PeakBridge.Client.ProgressSystem = detectProgress()
    PeakBridge.Client.AppearanceSystem = detectAppearance()
    PeakBridge.Client.Ready = true
    Shared.Debug(('Client ready. Framework: %s | Notify: %s | Target: %s | Progress: %s | Appearance: %s'):format(
        tostring(PeakBridge.Client.FrameworkName),
        tostring(PeakBridge.Client.NotifySystem),
        tostring(PeakBridge.Client.TargetSystem or 'none'),
        tostring(PeakBridge.Client.ProgressSystem),
        tostring(PeakBridge.Client.AppearanceSystem or 'none')
    ))
end)
