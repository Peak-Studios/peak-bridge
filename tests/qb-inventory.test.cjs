const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');
const { LuaFactory } = require('wasmoon');

test('QBCore bridge routes item operations through the detected qb-inventory export', async () => {
    const factory = new LuaFactory();
    const lua = await factory.createEngine();
    try {
        const prelude = `
          local calls = { add = 0, remove = 0, nativeAdd = 0, nativeRemove = 0, nativeCount = 0, partialMutations = 0 }
          local items = { phone = { 2, 2 }, simcard = {} }
          local failCountExport = false
          local rejectAdd = false
          local exportMissingAdd = false
          local exportMissingRemove = false
          local partialThenThrow = false
          local inventory = {}
          function inventory:AddItem(source, item, count, slot, metadata)
            calls.add = calls.add + 1
            calls.addArgs = { source, item, count, slot, metadata }
            if exportMissingAdd then error('No such export AddItem in resource qb-inventory') end
            if partialThenThrow then
              calls.partialMutations = calls.partialMutations + 1
              error('mock inventory failure after mutation')
            end
            if rejectAdd then return false end
            return true
          end
          function inventory:RemoveItem(source, item, count, slot)
            calls.remove = calls.remove + 1
            calls.removeArgs = { source, item, count, slot }
            if exportMissingRemove then error('No such export RemoveItem in resource qb-inventory') end
            return true
          end
          function inventory:GetItemCount(source, item)
            if failCountExport then error('mock export unavailable') end
            local total = 0
            for _, amount in ipairs(items[item] or {}) do total = total + amount end
            return total
          end
          local player = { Functions = {
            AddItem = function() calls.nativeAdd = calls.nativeAdd + 1; return true end,
            RemoveItem = function() calls.nativeRemove = calls.nativeRemove + 1; return true end,
            GetItemByName = function(item)
              calls.nativeCount = calls.nativeCount + 1
              if item == 'phone' then return { amount = 7 } end
            end,
          } }
          PeakBridge = {
            Config = { Framework = 'qbcore', Inventory = 'qb-inventory', SQL = 'none' },
            Shared = {
              NormalizeName = function(name) return name end,
              IsStarted = function(name) return name == 'qb-inventory' or name == 'qb-core' end,
              Info = function() end,
              Warn = function() end,
            },
            Server = {
              FrameworkName = 'qbcore',
              FrameworkObject = { Functions = { GetPlayer = function() return player end } },
            },
          }
          exports = setmetatable({}, {
            __index = function(_, name) if name == 'qb-inventory' then return inventory end end,
            __call = function() end,
          })
          RegisterNetEvent = function() end
          AddEventHandler = function() end
          CreateThread = function() end
          Wait = function() end
          GetResourceState = function() return 'started' end
          GetPlayerName = function() return 'Mock Player' end
          GetPlayerIdentifier = function() return 'license:mock' end
          RegisterCommand = function() end
          MySQL = {}
        `;
        const bridgeSource = fs.readFileSync(path.join(__dirname, '..', 'server', 'main.lua'), 'utf8');
        await lua.doString(prelude + bridgeSource + `
          assert(PeakBridge.Server.AddItem(7, 'simcard', 1, { sim_id = 'SIM-ABC' }, 4),
            'SIM item should be added through the active inventory export')
          assert(calls.add == 1 and calls.nativeAdd == 0, 'AddItem bypassed qb-inventory')
          assert(calls.addArgs[1] == 7 and calls.addArgs[2] == 'simcard' and calls.addArgs[3] == 1,
            'AddItem source/name/count contract changed')
          assert(calls.addArgs[4] == 4 and calls.addArgs[5].sim_id == 'SIM-ABC',
            'AddItem did not reorder bridge metadata/slot into the inventory export contract')

          assert(PeakBridge.Server.RemoveItem(7, 'simcard', 1, 4), 'SIM item removal should use inventory export')
          assert(calls.remove == 1 and calls.nativeRemove == 0, 'RemoveItem bypassed qb-inventory')
          assert(calls.removeArgs[1] == 7 and calls.removeArgs[2] == 'simcard' and
            calls.removeArgs[3] == 1 and calls.removeArgs[4] == 4, 'RemoveItem export argument order changed')

          assert(PeakBridge.Server.GetItemCount(7, 'phone') == 4,
            'split stack count must be read from qb-inventory, not QBCore Player.Functions')
          assert(calls.nativeCount == 0, 'item count lookup bypassed qb-inventory')

          failCountExport = true
          assert(PeakBridge.Server.GetItemCount(7, 'phone') == 7,
            'framework item lookup should remain a fallback when inventory count export errors')
          assert(calls.nativeCount == 1, 'framework count fallback was not used after export error')

          exportMissingAdd = true
          assert(PeakBridge.Server.AddItem(7, 'simcard', 1, {}, nil),
            'QB player method should be used when the inventory export is demonstrably absent')
          assert(calls.nativeAdd == 1, 'missing AddItem export did not use QB player fallback')
          exportMissingAdd = false

          exportMissingRemove = true
          assert(PeakBridge.Server.RemoveItem(7, 'simcard', 1, nil),
            'QB player method should be used when RemoveItem export is demonstrably absent')
          assert(calls.nativeRemove == 1, 'missing RemoveItem export did not use QB player fallback')
          exportMissingRemove = false

          rejectAdd = true
          assert(PeakBridge.Server.AddItem(7, 'simcard', 1, {}, nil) == false,
            'inventory rejection must not be reported as success')
          assert(calls.add == 3 and calls.nativeAdd == 1,
            'explicit inventory rejection must not fall through to framework mutation')
          rejectAdd = false

          partialThenThrow = true
          assert(PeakBridge.Server.AddItem(7, 'simcard', 1, {}, nil) == false,
            'inventory error after an ambiguous partial mutation must fail closed')
          assert(calls.partialMutations == 1 and calls.nativeAdd == 1,
            'ambiguous export error fell through and risked a duplicate item')
        `);
    } finally {
        lua.global.close();
    }
});
