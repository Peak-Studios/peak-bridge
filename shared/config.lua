PeakBridgeConfig = PeakBridgeConfig or {}

-- Framework: 'auto', 'qbox', 'qbx', 'qbcore', 'esx', 'ox', 'vrp', 'standalone'
PeakBridgeConfig.Framework = 'auto'

-- Inventory: 'auto', 'ox_inventory', 'qb-inventory', 'qb_inventory', 'ps-inventory',
-- 'qs-inventory', 'qs_inventory', 'codem-inventory', 'gfx-inventory', 'esx_inventory', 'none'
PeakBridgeConfig.Inventory = 'auto'

-- SQL: 'auto', 'oxmysql', 'ghmattimysql', 'mysql-async', 'none'
PeakBridgeConfig.SQL = 'auto'

-- Client systems.
PeakBridgeConfig.Notify = 'auto' -- 'auto', 'ox_lib', 'qb-core', 'esx', 'native'
PeakBridgeConfig.Target = 'auto' -- 'auto', 'ox_target', 'qb-target', 'none'
PeakBridgeConfig.Progress = 'auto' -- 'auto', 'ox_lib', 'progressbar', 'wait'
PeakBridgeConfig.Appearance = 'auto' -- 'auto', 'illenium-appearance', 'fivem-appearance', 'qb-clothing', 'rcore_clothing', 'rcore_clothes', 'skinchanger', 'none'

PeakBridgeConfig.CallbackTimeout = 15000
PeakBridgeConfig.DefaultMoneyAccount = 'cash'
PeakBridgeConfig.DefaultReason = 'peak-bridge'

PeakBridgeConfig.AdminAce = 'command'
PeakBridgeConfig.AdminGroups = { 'admin', 'superadmin', 'god' }
PeakBridgeConfig.Debug = false
