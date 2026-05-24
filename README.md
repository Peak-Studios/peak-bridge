# peak-bridge

`peak-bridge` is the shared integration layer for future Peak resources. It centralizes framework, inventory, SQL, callback, money, notification, progress, text UI, and appearance bridge logic so new scripts do not copy the same code.

`peak-barbers` now depends on this bridge, and new Peak resources should use it instead of copying local framework bridge logic.

## Load Order

```cfg
ensure ox_lib       # required by peak-bridge for lib.notify/progress/text UI support
ensure oxmysql      # optional, needed only when SQL is oxmysql
ensure peak-bridge
ensure peak-your-resource
```

Future Peak resources should add:

```lua
dependency 'peak-bridge'
```

## Configuration

Edit `shared/config.lua`.

- `PeakBridgeConfig.Framework`: `auto`, `qbox`, `qbx`, `qbcore`, `esx`, `ox`, `vrp`, `standalone`
- `PeakBridgeConfig.Inventory`: `auto`, `ox_inventory`, `qb-inventory`, `qb_inventory`, `ps-inventory`, `qs-inventory`, `qs_inventory`, `codem-inventory`, `gfx-inventory`, `esx_inventory`, `none`
- `PeakBridgeConfig.SQL`: `auto`, `oxmysql`, `ghmattimysql`, `mysql-async`, `none`
- `PeakBridgeConfig.Notify`: `auto`, `ox_lib`, `qb-core`, `esx`, `native`
- `PeakBridgeConfig.Target`: `auto`, `ox_target`, `qb-target`, `none`
- `PeakBridgeConfig.Progress`: `auto`, `ox_lib`, `progressbar`, `wait`
- `PeakBridgeConfig.Appearance`: `auto`, `illenium-appearance`, `fivem-appearance`, `qb-clothing`, `rcore_clothing`, `rcore_clothes`, `skinchanger`, `none`

Aliases are normalized internally, so `qbx` becomes `qbox`, `qb_inventory` becomes `qb-inventory`, `qs_inventory` becomes `qs-inventory`, and `rcore_clothes` becomes `rcore_clothing`.

## Server Exports

```lua
local bridge = exports['peak-bridge']

local ready = bridge:IsReady()
local frameworkName = bridge:GetFrameworkName()
local framework = bridge:GetFramework()
local inventoryName = bridge:GetInventoryName()
local sqlDriver = bridge:GetSQLDriver()

local player = bridge:GetPlayer(source)
local identifier = bridge:GetIdentifier(source)
local name = bridge:GetPlayerName(source)

bridge:AddMoney(source, 500, 'cash', 'job payout')
bridge:RemoveMoney(source, 75, 'cash', 'purchase')
local cash = bridge:GetMoney(source, 'cash')

bridge:AddItem(source, 'water', 1, { quality = 100 })
bridge:RemoveItem(source, 'water', 1)
local count = bridge:GetItemCount(source, 'water')
local hasItem = bridge:HasItem(source, 'water', 1)

bridge:RegisterUsableItem('water', function(source, item, itemData)
    -- handle item use
end)

bridge:RegisterCallback('my-resource:getData', function(source, id)
    return { id = id }
end)

local isAdmin = bridge:IsAdmin(source, {
    ace = 'command.myadmin',
    groups = { 'admin', 'god' },
})

local rows = bridge:ExecuteSql('SELECT * FROM users WHERE identifier = ?', { identifier })
```

## Client Exports

```lua
local bridge = exports['peak-bridge']

local ready = bridge:IsReady()
local frameworkName = bridge:GetFrameworkName()
local framework = bridge:GetFramework()

local data = bridge:GetPlayerData()
local job = bridge:GetPlayerJob()

local result = bridge:TriggerCallback('my-resource:getData', 123)

bridge:Notify('Saved', 'success', 5000, 'Peak')
local completed = bridge:ProgressBar('Working...', 5000, {
    dict = 'amb@world_human_hammering@male@base',
    anim = 'base',
    disableMove = true,
    disableCombat = true,
})

bridge:ShowTextUI('[E] Interact', 'right-center')
bridge:HideTextUI()

local appearance = bridge:GetAppearance()
bridge:SaveAppearance()
bridge:ReloadAppearance()

local model = bridge:LoadModel('s_m_m_trucker_01')
bridge:LoadAnimDict('missheistdockssetup1clipboard@base')
```

## Callback Transport

Callbacks use `peak-bridge` events:

- `peak-bridge:server:triggerCallback`
- `peak-bridge:client:callbackResponse`

New scripts only need `RegisterCallback` on the server and `TriggerCallback` on the client.

## Requirements

- FiveM artifact with Lua 5.4 enabled.
- `ox_lib` started before `peak-bridge`.
- A supported framework/inventory/SQL resource only if the matching feature is used.
