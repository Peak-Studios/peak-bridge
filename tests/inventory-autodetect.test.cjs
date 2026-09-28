const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const { LuaFactory } = require('wasmoon');

test('auto inventory detection switches between Peak, QB, and framework fallback at runtime', async () => {
    const factory = new LuaFactory();
    const lua = await factory.createEngine();
    try {
        const root = path.join(__dirname, '..');
        const prelude = `
          local states = {
            ['qb-core'] = 'started',
            ['qb-inventory'] = 'started',
            ['peak-qb-inventory'] = 'stopped',
          }
          local calls = { qbAdd = 0, qbRemove = 0, qbCount = 0, peakAdd = 0, peakRemove = 0, peakCount = 0,
            nativeAdd = 0, nativeRemove = 0, nativeCount = 0 }
          local qbItems = { phone = 6 }
          local peakItems = { phone = { 2, 3 } }
          local bridgeExports = {}
          local player = { Functions = {
            AddItem = function(item, count) calls.nativeAdd = calls.nativeAdd + 1; calls.nativeAddArgs = { item, count }; return true end,
            RemoveItem = function(item, count) calls.nativeRemove = calls.nativeRemove + 1; calls.nativeRemoveArgs = { item, count }; return true end,
            GetItemByName = function(item)
              calls.nativeCount = calls.nativeCount + 1
              if item == 'phone' then return { amount = 7 } end
            end,
          } }
          local qbInventory = {
            AddItem = function(_, source, item, count, slot, metadata)
              calls.qbAdd = calls.qbAdd + 1; calls.qbAddArgs = { source, item, count, slot, metadata }; return true
            end,
            RemoveItem = function(_, source, item, count, slot)
              calls.qbRemove = calls.qbRemove + 1; calls.qbRemoveArgs = { source, item, count, slot }; return true
            end,
            GetItemCount = function(_, source, item)
              calls.qbCount = calls.qbCount + 1; calls.qbCountSource = source
              return qbItems[item] or 0
            end,
          }
          local peakInventory = {
            AddItem = function(_, source, item, count, slot, metadata)
              calls.peakAdd = calls.peakAdd + 1; calls.peakAddArgs = { source, item, count, slot, metadata }; return true
            end,
            RemoveItem = function(_, source, item, count, slot)
              calls.peakRemove = calls.peakRemove + 1; calls.peakRemoveArgs = { source, item, count, slot }; return true
            end,
            GetItemCount = function(_, source, item)
              calls.peakCount = calls.peakCount + 1
              calls.peakCountSource = source
              local total = 0
              for _, amount in ipairs(peakItems[item] or {}) do total = total + amount end
              return total
            end,
          }
          local qbCore = { GetCoreObject = function()
            return { Functions = { GetPlayer = function() return player end } }
          end }
          exports = setmetatable({}, {
            __index = function(_, name)
              if name == 'qb-core' then return qbCore end
              if name == 'qb-inventory' then return qbInventory end
              if name == 'peak-qb-inventory' then return peakInventory end
            end,
            __call = function(_, name, callback) bridgeExports[name] = callback end,
          })
          GetResourceState = function(name) return states[name] or 'stopped' end
          RegisterNetEvent = function() end
          AddEventHandler = function() end
          CreateThread = function(fn) fn() end
          Wait = function() end
          GetPlayerName = function() return 'Mock Player' end
          GetPlayerIdentifier = function() return 'license:mock' end
          RegisterCommand = function() end
          MySQL = {}
        `;
        const config = fs.readFileSync(path.join(root, 'shared', 'config.lua'), 'utf8');
        const utils = fs.readFileSync(path.join(root, 'shared', 'utils.lua'), 'utf8');
        const server = fs.readFileSync(path.join(root, 'server', 'main.lua'), 'utf8');

        await lua.doString(prelude + config + utils + server + `
          assert(PeakBridge.Server.FrameworkName == 'qbcore', 'auto framework detection should select QBCore')
          assert(bridgeExports.GetInventoryName() == 'qb-inventory', 'auto detection should select started QB inventory')

          assert(PeakBridge.Server.AddItem(7, 'phone', 1, { source = 'qb' }, 3), 'QB export add should succeed')
          assert(calls.qbAdd == 1 and calls.peakAdd == 0 and calls.nativeAdd == 0, 'QB was not the selected add route')
          assert(calls.qbAddArgs[1] == 7 and calls.qbAddArgs[2] == 'phone' and calls.qbAddArgs[4] == 3,
            'QB add export argument contract changed')
          assert(PeakBridge.Server.GetItemCount(7, 'phone') == 6 and calls.qbCount == 1,
            'QB item count export should be used while Peak is stopped')
          assert(calls.qbCountSource == 7, 'QB item count export source argument changed')

          states['peak-qb-inventory'] = 'started'
          assert(bridgeExports.GetInventoryName() == 'peak-qb-inventory', 'Peak should take priority when started')
          assert(PeakBridge.Server.AddItem(7, 'phone', 2, { source = 'peak' }, 4), 'Peak export add should succeed')
          assert(calls.peakAdd == 1 and calls.qbAdd == 1 and calls.nativeAdd == 0, 'Peak was not the selected add route')
          assert(calls.peakAddArgs[1] == 7 and calls.peakAddArgs[2] == 'phone' and calls.peakAddArgs[4] == 4,
            'Peak add export argument contract changed')
          assert(PeakBridge.Server.RemoveItem(7, 'phone', 1, 4), 'Peak export remove should succeed')
          assert(calls.peakRemove == 1 and calls.qbRemove == 0, 'Peak was not the selected remove route')
          assert(PeakBridge.Server.GetItemCount(7, 'phone') == 5 and calls.peakCount == 1 and calls.qbCount == 1,
            'Peak count should aggregate all item stacks')
          assert(calls.peakCountSource == 7, 'Peak item count export source argument changed')

          states['peak-qb-inventory'] = 'stopped'
          assert(bridgeExports.GetInventoryName() == 'qb-inventory', 'stopping Peak should restore QB autodetection')
          assert(PeakBridge.Server.RemoveItem(7, 'phone', 1, 3), 'QB export remove should succeed after Peak stops')
          assert(calls.qbRemove == 1 and calls.peakRemove == 1, 'QB should receive remove after Peak stops')
          assert(PeakBridge.Server.GetItemCount(7, 'phone') == 6 and calls.qbCount == 2,
            'QB count should resume after Peak stops')

          states['qb-inventory'] = 'stopped'
          assert(bridgeExports.GetInventoryName() == nil, 'no inventory should be detected after both resources stop')
          assert(PeakBridge.Server.AddItem(7, 'phone', 1, {}, nil), 'QBCore player fallback should work with no inventory resource')
          assert(PeakBridge.Server.RemoveItem(7, 'phone', 1, nil), 'QBCore player remove fallback should work with no inventory resource')
          assert(calls.nativeAdd == 1 and calls.nativeRemove == 1, 'framework fallback should handle mutations after both stop')
          assert(calls.nativeAddArgs[1] == 'phone' and calls.nativeAddArgs[2] == 1 and
            calls.nativeRemoveArgs[1] == 'phone' and calls.nativeRemoveArgs[2] == 1,
            'QBCore framework fallback mutation argument contract changed')
          assert(PeakBridge.Server.GetItemCount(7, 'phone') == 7 and calls.nativeCount == 1,
            'framework item count fallback should work after both inventory resources stop')

          states['peak-qb-inventory'] = 'started'
          assert(bridgeExports.GetInventoryName() == 'peak-qb-inventory', 'Peak should be detected when started later')
          assert(PeakBridge.Server.GetItemCount(7, 'phone') == 5 and calls.peakCount == 2,
            'Peak count route should recover after a stop/start cycle')
        `);
    } finally {
        lua.global.close();
    }
});
