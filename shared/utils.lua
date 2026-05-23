PeakBridge = PeakBridge or {}
PeakBridge.Config = PeakBridgeConfig or {}
PeakBridge.Shared = PeakBridge.Shared or {}

local aliases = {
    qbx = 'qbox',
    ['qb_inventory'] = 'qb-inventory',
    ['qs_inventory'] = 'qs-inventory',
    ['ps_inventory'] = 'ps-inventory',
    ['codem_inventory'] = 'codem-inventory',
    ['gfx_inventory'] = 'gfx-inventory',
    rcore_clothes = 'rcore_clothing',
    ['qb_target'] = 'qb-target',
}

function PeakBridge.Shared.NormalizeName(value)
    if value == nil then return nil end
    local normalized = tostring(value)
    return aliases[normalized] or normalized
end

function PeakBridge.Shared.IsStarted(resource)
    return resource and GetResourceState(resource) == 'started'
end

function PeakBridge.Shared.Debug(...)
    if not PeakBridge.Config.Debug then return end
    print('^5[peak-bridge]^0', ...)
end

function PeakBridge.Shared.Info(...)
    print('^5[peak-bridge]^0', ...)
end

function PeakBridge.Shared.Warn(...)
    print('^3[peak-bridge]^0', ...)
end

function PeakBridge.Shared.SafeCall(fn, ...)
    local ok, result, extra = pcall(fn, ...)
    if not ok then
        PeakBridge.Shared.Debug(result)
        return false, nil
    end
    return true, result, extra
end

function PeakBridge.Shared.TableHas(list, value)
    if not list then return false end
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end
