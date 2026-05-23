PeakBridge = PeakBridge or {}
PeakBridge.Server = PeakBridge.Server or {
    Ready = false,
    FrameworkName = 'standalone',
    FrameworkObject = nil,
    FrameworkShared = nil,
    InventoryName = nil,
    SQLDriver = nil,
    Callbacks = {},
    UsableItems = {},
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
                return function(...)
                    return qbx[key](qbx, ...)
                end
            end
        })
    }
    local shared = setmetatable({}, {
        __index = function(_, key)
            local map = {
                Jobs = 'GetJobs',
                Gangs = 'GetGangs',
                Vehicles = 'GetVehiclesByName',
                Weapons = 'GetWeapons',
                Locations = 'GetLocations',
            }
            if map[key] and qbx[map[key]] then
                local ok2, data = pcall(qbx[map[key]], qbx)
                if ok2 then return data end
            end
            if key == 'Items' and Shared.IsStarted('ox_inventory') then
                local ok2, data = pcall(function() return exports.ox_inventory:Items() end)
                if ok2 then return data end
            end
            return nil
        end
    })
    return object, shared
end

local function initializeFramework()
    local fw = detectFramework()
    PeakBridge.Server.FrameworkName = fw

    if fw == 'qbcore' and Shared.IsStarted('qb-core') then
        PeakBridge.Server.FrameworkObject = exports['qb-core']:GetCoreObject()
        PeakBridge.Server.FrameworkShared = PeakBridge.Server.FrameworkObject.Shared
    elseif fw == 'qbox' and Shared.IsStarted('qbx_core') then
        PeakBridge.Server.FrameworkObject, PeakBridge.Server.FrameworkShared = makeQboxObject()
    elseif fw == 'esx' and Shared.IsStarted('es_extended') then
        PeakBridge.Server.FrameworkObject = exports.es_extended:getSharedObject()
    elseif fw == 'vrp' and Shared.IsStarted('vrp') then
        local ok, obj = pcall(function() return exports.vrp:getInterface() end)
        if ok then PeakBridge.Server.FrameworkObject = obj end
    end
end

local function detectInventory()
    local configured = Shared.NormalizeName(Config.Inventory)
    if configured and configured ~= 'auto' then
        return configured ~= 'none' and configured or nil
    end

    local systems = {
        'ox_inventory',
        'qb-inventory',
        'ps-inventory',
        'qs-inventory',
        'codem-inventory',
        'gfx-inventory',
    }
    for _, name in ipairs(systems) do
        if Shared.IsStarted(name) then return name end
    end
    if PeakBridge.Server.FrameworkName == 'esx' then return 'esx_inventory' end
    return nil
end

local function detectSQL()
    local configured = Shared.NormalizeName(Config.SQL)
    if configured and configured ~= 'auto' then
        return configured ~= 'none' and configured or nil
    end
    if Shared.IsStarted('oxmysql') then return 'oxmysql' end
    if Shared.IsStarted('ghmattimysql') then return 'ghmattimysql' end
    if Shared.IsStarted('mysql-async') then return 'mysql-async' end
    return nil
end

local function getFrameworkPlayer(source)
    local fw = PeakBridge.Server.FrameworkName
    local obj = PeakBridge.Server.FrameworkObject
    if fw == 'qbcore' or fw == 'qbox' then
        return obj and obj.Functions and obj.Functions.GetPlayer and obj.Functions.GetPlayer(source) or nil
    elseif fw == 'esx' then
        return obj and obj.GetPlayerFromId and obj.GetPlayerFromId(source) or nil
    elseif fw == 'ox' and Shared.IsStarted('ox_core') then
        local ok, player = pcall(function() return exports.ox_core:GetPlayer(source) end)
        return ok and player or nil
    elseif fw == 'vrp' then
        return obj
    end
    return nil
end

function PeakBridge.Server.GetPlayer(source)
    return getFrameworkPlayer(source)
end

function PeakBridge.Server.GetIdentifier(source)
    local fw = PeakBridge.Server.FrameworkName
    local player = getFrameworkPlayer(source)
    if (fw == 'qbcore' or fw == 'qbox') and player and player.PlayerData then
        return player.PlayerData.citizenid or player.PlayerData.license
    elseif fw == 'esx' and player then
        if player.getIdentifier then return player.getIdentifier() end
        return player.identifier
    elseif fw == 'ox' and player then
        return player.charId or player.stateId or player.license
    end
    return GetPlayerIdentifier(source, 0)
end

function PeakBridge.Server.GetPlayerName(source)
    local fw = PeakBridge.Server.FrameworkName
    local player = getFrameworkPlayer(source)
    if (fw == 'qbcore' or fw == 'qbox') and player and player.PlayerData then
        local charinfo = player.PlayerData.charinfo or {}
        local name = ((charinfo.firstname or '') .. ' ' .. (charinfo.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
        if name ~= '' then return name end
    elseif fw == 'esx' and player and player.getName then
        return player.getName()
    end
    return GetPlayerName(source)
end

local function normalizeAccount(account)
    account = account or Config.DefaultMoneyAccount or 'cash'
    if PeakBridge.Server.FrameworkName == 'esx' and account == 'cash' then return 'money' end
    return account
end

function PeakBridge.Server.AddMoney(source, amount, account, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    account = normalizeAccount(account)
    reason = reason or Config.DefaultReason

    local fw = PeakBridge.Server.FrameworkName
    local player = getFrameworkPlayer(source)
    if (fw == 'qbcore' or fw == 'qbox') and player and player.Functions and player.Functions.AddMoney then
        return player.Functions.AddMoney(account, amount, reason) == true
    elseif fw == 'esx' and player then
        if account == 'money' and player.addMoney then
            player.addMoney(amount)
        elseif player.addAccountMoney then
            player.addAccountMoney(account, amount, reason)
        else
            return false
        end
        return true
    elseif fw == 'qbox' and Shared.IsStarted('qbx_core') then
        local ok, res = pcall(function() return exports.qbx_core:AddMoney(source, account, amount, reason) end)
        return ok and res == true
    end
    return false
end

function PeakBridge.Server.RemoveMoney(source, amount, account, reason)
    amount = tonumber(amount) or 0
    if amount <= 0 then return false end
    account = normalizeAccount(account)
    reason = reason or Config.DefaultReason

    local fw = PeakBridge.Server.FrameworkName
    local player = getFrameworkPlayer(source)
    if (fw == 'qbcore' or fw == 'qbox') and player and player.Functions and player.Functions.RemoveMoney then
        return player.Functions.RemoveMoney(account, amount, reason) == true
    elseif fw == 'esx' and player then
        if account == 'money' and player.removeMoney then
            player.removeMoney(amount)
        elseif player.removeAccountMoney then
            player.removeAccountMoney(account, amount, reason)
        else
            return false
        end
        return true
    elseif fw == 'qbox' and Shared.IsStarted('qbx_core') then
        local ok, res = pcall(function() return exports.qbx_core:RemoveMoney(source, account, amount, reason) end)
        return ok and res == true
    end
    return false
end

function PeakBridge.Server.GetMoney(source, account)
    account = normalizeAccount(account)
    local fw = PeakBridge.Server.FrameworkName
    local player = getFrameworkPlayer(source)
    if (fw == 'qbcore' or fw == 'qbox') and player and player.PlayerData and player.PlayerData.money then
        return player.PlayerData.money[account] or 0
    elseif fw == 'esx' and player then
        if account == 'money' and player.getMoney then return player.getMoney() or 0 end
        if player.getAccount then
            local acc = player.getAccount(account)
            return acc and acc.money or 0
        end
    end
    return 0
end

local function qbPlayerInventoryCall(source, method, item, count, slot, metadata)
    local player = getFrameworkPlayer(source)
    if player and player.Functions and player.Functions[method] then
        if method == 'AddItem' then
            return player.Functions.AddItem(item, count, slot, metadata) == true
        end
        return player.Functions.RemoveItem(item, count, slot) == true
    end
    return nil
end

function PeakBridge.Server.AddItem(source, item, count, metadata, slot)
    count = tonumber(count) or 1
    if not item or count <= 0 then return false end

    local inv = PeakBridge.Server.InventoryName
    if inv == 'ox_inventory' and Shared.IsStarted('ox_inventory') then
        local ok, res = pcall(function() return exports.ox_inventory:AddItem(source, item, count, metadata, slot) end)
        return ok and res == true
    elseif (inv == 'qb-inventory' or inv == 'ps-inventory') then
        local res = qbPlayerInventoryCall(source, 'AddItem', item, count, slot, metadata)
        if res ~= nil then return res end
        if Shared.IsStarted(inv) then
            local ok, out = pcall(function() return exports[inv]:AddItem(source, item, count, slot, metadata) end)
            return ok and out == true
        end
    elseif inv == 'qs-inventory' and Shared.IsStarted('qs-inventory') then
        local ok, res = pcall(function() return exports['qs-inventory']:AddItem(source, item, count, slot, metadata) end)
        return ok and res == true
    elseif inv == 'codem-inventory' and Shared.IsStarted('codem-inventory') then
        local ok, res = pcall(function() return exports['codem-inventory']:AddItem(source, item, count, slot, metadata) end)
        return ok and res == true
    elseif inv == 'gfx-inventory' and Shared.IsStarted('gfx-inventory') then
        local ok, res = pcall(function() return exports['gfx-inventory']:AddItem(source, item, count, metadata) end)
        return ok and res == true
    end

    local fw = PeakBridge.Server.FrameworkName
    local player = getFrameworkPlayer(source)
    if (fw == 'qbcore' or fw == 'qbox') then
        return qbPlayerInventoryCall(source, 'AddItem', item, count, slot, metadata) == true
    elseif fw == 'esx' and player and player.addInventoryItem then
        player.addInventoryItem(item, count)
        return true
    end
    return false
end

function PeakBridge.Server.RemoveItem(source, item, count, slot, metadata)
    count = tonumber(count) or 1
    if not item or count <= 0 then return false end

    local inv = PeakBridge.Server.InventoryName
    if inv == 'ox_inventory' and Shared.IsStarted('ox_inventory') then
        local ok, res = pcall(function() return exports.ox_inventory:RemoveItem(source, item, count, metadata, slot) end)
        return ok and res == true
    elseif (inv == 'qb-inventory' or inv == 'ps-inventory') then
        local res = qbPlayerInventoryCall(source, 'RemoveItem', item, count, slot, metadata)
        if res ~= nil then return res end
        if Shared.IsStarted(inv) then
            local ok, out = pcall(function() return exports[inv]:RemoveItem(source, item, count, slot) end)
            return ok and out == true
        end
    elseif inv == 'qs-inventory' and Shared.IsStarted('qs-inventory') then
        local ok, res = pcall(function() return exports['qs-inventory']:RemoveItem(source, item, count, slot) end)
        return ok and res == true
    elseif inv == 'codem-inventory' and Shared.IsStarted('codem-inventory') then
        local ok, res = pcall(function() return exports['codem-inventory']:RemoveItem(source, item, count, slot) end)
        return ok and res == true
    elseif inv == 'gfx-inventory' and Shared.IsStarted('gfx-inventory') then
        local ok, res = pcall(function() return exports['gfx-inventory']:RemoveItem(source, item, count) end)
        return ok and res == true
    end

    local fw = PeakBridge.Server.FrameworkName
    local player = getFrameworkPlayer(source)
    if (fw == 'qbcore' or fw == 'qbox') then
        return qbPlayerInventoryCall(source, 'RemoveItem', item, count, slot, metadata) == true
    elseif fw == 'esx' and player and player.removeInventoryItem then
        player.removeInventoryItem(item, count)
        return true
    end
    return false
end

function PeakBridge.Server.GetItemCount(source, item)
    if not item then return 0 end
    local inv = PeakBridge.Server.InventoryName
    if inv == 'ox_inventory' and Shared.IsStarted('ox_inventory') then
        local ok, count = pcall(function() return exports.ox_inventory:GetItemCount(source, item) end)
        if ok then return tonumber(count) or 0 end
    elseif inv == 'qs-inventory' and Shared.IsStarted('qs-inventory') then
        local ok, count = pcall(function() return exports['qs-inventory']:GetItemTotalAmount(source, item) end)
        if ok then return tonumber(count) or 0 end
    end

    local fw = PeakBridge.Server.FrameworkName
    local player = getFrameworkPlayer(source)
    if (fw == 'qbcore' or fw == 'qbox') and player and player.Functions and player.Functions.GetItemByName then
        local itemData = player.Functions.GetItemByName(item)
        return itemData and tonumber(itemData.amount or itemData.count) or 0
    elseif fw == 'esx' and player and player.getInventoryItem then
        local itemData = player.getInventoryItem(item)
        return itemData and tonumber(itemData.count or itemData.amount) or 0
    end
    return 0
end

function PeakBridge.Server.HasItem(source, item, count)
    return PeakBridge.Server.GetItemCount(source, item) >= (tonumber(count) or 1)
end

function PeakBridge.Server.RegisterUsableItem(item, cb)
    if not item or type(cb) ~= 'function' then return false end
    PeakBridge.Server.UsableItems[item] = cb
    local fw = PeakBridge.Server.FrameworkName
    local obj = PeakBridge.Server.FrameworkObject
    local function onUse(source, itemData)
        local handler = PeakBridge.Server.UsableItems[item]
        if handler then handler(source, item, itemData) end
    end

    if fw == 'qbox' and Shared.IsStarted('qbx_core') then
        local ok = pcall(function() exports.qbx_core:CreateUseableItem(item, function(source, itemData) onUse(source, itemData) end) end)
        return ok
    elseif fw == 'qbcore' and obj and obj.Functions and obj.Functions.CreateUseableItem then
        obj.Functions.CreateUseableItem(item, function(source, itemData) onUse(source, itemData) end)
        return true
    elseif fw == 'esx' and obj and obj.RegisterUsableItem then
        obj.RegisterUsableItem(item, function(source, itemData) onUse(source, itemData) end)
        return true
    end
    Shared.Warn('No usable item registration available for', item)
    return false
end

function PeakBridge.Server.RegisterCallback(name, cb)
    if not name or type(cb) ~= 'function' then return false end
    PeakBridge.Server.Callbacks[name] = cb
    return true
end

RegisterNetEvent('peak-bridge:server:triggerCallback', function(id, name, ...)
    local source = source
    local cb = PeakBridge.Server.Callbacks[name]
    if not cb then
        Shared.Warn('Callback not found:', name)
        TriggerClientEvent('peak-bridge:client:callbackResponse', source, id, nil)
        return
    end
    local ok, result = pcall(cb, source, ...)
    if not ok then
        Shared.Warn(('Callback error [%s]: %s'):format(tostring(name), tostring(result)))
        result = nil
    end
    TriggerClientEvent('peak-bridge:client:callbackResponse', source, id, result)
end)

function PeakBridge.Server.IsAdmin(source, opts)
    opts = opts or {}
    local ace = opts.ace or Config.AdminAce
    if ace and ace ~= '' and IsPlayerAceAllowed(source, ace) then return true end

    local groups = opts.groups or Config.AdminGroups
    local fw = PeakBridge.Server.FrameworkName
    local obj = PeakBridge.Server.FrameworkObject
    if (fw == 'qbcore' or fw == 'qbox') and obj and obj.Functions and obj.Functions.HasPermission then
        for _, group in ipairs(groups or {}) do
            if obj.Functions.HasPermission(source, group) then return true end
        end
    elseif fw == 'esx' and obj and obj.GetPlayerFromId then
        local player = obj.GetPlayerFromId(source)
        local group = player and player.getGroup and player.getGroup()
        return Shared.TableHas(groups, group)
    end
    return false
end

function PeakBridge.Server.ExecuteSql(query, params)
    local driver = PeakBridge.Server.SQLDriver
    if not driver then error('No SQL driver detected') end
    params = params or {}

    if driver == 'oxmysql' then
        if MySQL and MySQL.query and MySQL.query.await then
            return MySQL.query.await(query, params) or {}
        end
        local done, result = false, {}
        exports.oxmysql:execute(query, params, function(data) result = data or {}; done = true end)
        while not done do Wait(0) end
        return result
    elseif driver == 'ghmattimysql' then
        local done, result = false, {}
        exports.ghmattimysql:execute(query, params, function(data) result = data or {}; done = true end)
        while not done do Wait(0) end
        return result
    elseif driver == 'mysql-async' then
        local done, result = false, {}
        MySQL.Async.fetchAll(query, params, function(data) result = data or {}; done = true end)
        while not done do Wait(0) end
        return result
    end
    error(('Unsupported SQL driver: %s'):format(tostring(driver)))
end

exports('IsReady', function() return PeakBridge.Server.Ready end)
exports('GetFrameworkName', function() return PeakBridge.Server.FrameworkName end)
exports('GetFramework', function() return PeakBridge.Server.FrameworkObject end)
exports('GetInventoryName', function() return PeakBridge.Server.InventoryName end)
exports('GetSQLDriver', function() return PeakBridge.Server.SQLDriver end)
exports('GetPlayer', function(...) return PeakBridge.Server.GetPlayer(...) end)
exports('GetIdentifier', function(...) return PeakBridge.Server.GetIdentifier(...) end)
exports('GetPlayerName', function(...) return PeakBridge.Server.GetPlayerName(...) end)
exports('AddMoney', function(...) return PeakBridge.Server.AddMoney(...) end)
exports('RemoveMoney', function(...) return PeakBridge.Server.RemoveMoney(...) end)
exports('GetMoney', function(...) return PeakBridge.Server.GetMoney(...) end)
exports('AddItem', function(...) return PeakBridge.Server.AddItem(...) end)
exports('RemoveItem', function(...) return PeakBridge.Server.RemoveItem(...) end)
exports('HasItem', function(...) return PeakBridge.Server.HasItem(...) end)
exports('GetItemCount', function(...) return PeakBridge.Server.GetItemCount(...) end)
exports('RegisterUsableItem', function(...) return PeakBridge.Server.RegisterUsableItem(...) end)
exports('RegisterCallback', function(...) return PeakBridge.Server.RegisterCallback(...) end)
exports('IsAdmin', function(...) return PeakBridge.Server.IsAdmin(...) end)
exports('ExecuteSql', function(...) return PeakBridge.Server.ExecuteSql(...) end)

CreateThread(function()
    Wait(150)
    initializeFramework()
    PeakBridge.Server.InventoryName = detectInventory()
    PeakBridge.Server.SQLDriver = detectSQL()
    PeakBridge.Server.Ready = true
    Shared.Info(('Server ready. Framework: ^5%s^0 | Inventory: ^5%s^0 | SQL: ^5%s^0'):format(
        tostring(PeakBridge.Server.FrameworkName),
        tostring(PeakBridge.Server.InventoryName or 'none'),
        tostring(PeakBridge.Server.SQLDriver or 'none')
    ))
end)
