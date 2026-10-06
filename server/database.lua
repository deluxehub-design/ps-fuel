PSFuelDatabase = PSFuelDatabase or {}
PSFuelDatabase.Ready = false

local function columnExists(tableName, columnName)
    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
    ]], { tableName, columnName })
    return tonumber(count) and tonumber(count) > 0 or false
end

local function indexExists(tableName, indexName)
    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?
    ]], { tableName, indexName })
    return tonumber(count) and tonumber(count) > 0 or false
end

local function ensureLegacySchema()
    -- Every migration statement is hard-coded. Do not build SQL identifiers from runtime values.
    if not columnExists('ps_fuel_vehicles', 'leak_level') then
        MySQL.query.await('ALTER TABLE `ps_fuel_vehicles` ADD COLUMN `leak_level` tinyint unsigned NOT NULL DEFAULT 0')
    end
    if not columnExists('ps_fuel_stations', 'stock') then
        MySQL.query.await('ALTER TABLE `ps_fuel_stations` ADD COLUMN `stock` decimal(12,2) NOT NULL DEFAULT 10000.00')
    end
    if not columnExists('ps_fuel_stations', 'capacity') then
        MySQL.query.await('ALTER TABLE `ps_fuel_stations` ADD COLUMN `capacity` decimal(12,2) NOT NULL DEFAULT 10000.00')
    end
    if not indexExists('ps_fuel_vehicles', 'idx_ps_fuel_vehicles_updated') then
        MySQL.query.await('ALTER TABLE `ps_fuel_vehicles` ADD INDEX `idx_ps_fuel_vehicles_updated` (`updated_at`)')
    end
    if not indexExists('ps_fuel_stations', 'idx_ps_fuel_stations_owner') then
        MySQL.query.await('ALTER TABLE `ps_fuel_stations` ADD INDEX `idx_ps_fuel_stations_owner` (`owner_citizenid`)')
    end
    if not indexExists('ps_fuel_transactions', 'idx_ps_fuel_transactions_citizen') then
        MySQL.query.await('ALTER TABLE `ps_fuel_transactions` ADD INDEX `idx_ps_fuel_transactions_citizen` (`citizenid`,`created_at`)')
    end
end

function PSFuelDatabase.Audit(action, source, citizenid, details)
    if PSFuelDatabase.Ready ~= true or (PSFuelConfig.Logging or {}).DatabaseAudit ~= true then return end
    local encoded = type(details) == 'string' and details or json.encode(details or {})
    MySQL.insert([[INSERT INTO ps_fuel_audit_logs (action, source, citizenid, details)
        VALUES (?, ?, ?, ?)]], {
        tostring(action or 'unknown'):sub(1, 64),
        tonumber(source) or 0,
        citizenid and tostring(citizenid):sub(1, 64) or nil,
        encoded,
    })
end


local function standaloneWalletDefaults()
    local cfg = (PSFuelConfig.Framework or {}).Standalone or {}
    return math.max(0, math.floor(tonumber(cfg.StartingCash) or 50000)),
        math.max(0, math.floor(tonumber(cfg.StartingBank) or 100000))
end

function PSFuelDatabase.GetWalletBalances(identifier)
    if not PSFuelDatabase.Ready or not identifier then return {} end
    local cash, bank = standaloneWalletDefaults()
    MySQL.insert.await([[INSERT IGNORE INTO ps_fuel_wallets (identifier, cash, bank) VALUES (?, ?, ?)]],
        { tostring(identifier), cash, bank })
    return MySQL.single.await('SELECT cash, bank FROM ps_fuel_wallets WHERE identifier = ?', { tostring(identifier) }) or {}
end

function PSFuelDatabase.GetWalletBalance(identifier, account)
    if not identifier then return 0 end
    local balances = PSFuelDatabase.GetWalletBalances(identifier)
    return tonumber(balances[tostring(account or 'bank'):lower()]) or 0
end

function PSFuelDatabase.RemoveWalletMoney(identifier, account, amount)
    if not identifier then return false end
    account = tostring(account or 'bank'):lower()
    if account ~= 'cash' and account ~= 'bank' then return false end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local affected
    if account == 'cash' then
        affected = MySQL.update.await(
            'UPDATE ps_fuel_wallets SET cash = cash - ? WHERE identifier = ? AND cash >= ?',
            { amount, tostring(identifier), amount }
        )
    else
        affected = MySQL.update.await(
            'UPDATE ps_fuel_wallets SET bank = bank - ? WHERE identifier = ? AND bank >= ?',
            { amount, tostring(identifier), amount }
        )
    end
    return affected and affected > 0 or amount == 0
end

function PSFuelDatabase.AddWalletMoney(identifier, account, amount)
    if not identifier then return false end
    account = tostring(account or 'bank'):lower()
    if account ~= 'cash' and account ~= 'bank' then return false end
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    local cash, bank = standaloneWalletDefaults()
    MySQL.insert.await([[INSERT IGNORE INTO ps_fuel_wallets (identifier, cash, bank) VALUES (?, ?, ?)]],
        { tostring(identifier), cash, bank })
    local affected
    if account == 'cash' then
        affected = MySQL.update.await(
            'UPDATE ps_fuel_wallets SET cash = cash + ? WHERE identifier = ?',
            { amount, tostring(identifier) }
        )
    else
        affected = MySQL.update.await(
            'UPDATE ps_fuel_wallets SET bank = bank + ? WHERE identifier = ?',
            { amount, tostring(identifier) }
        )
    end
    return affected and affected > 0 or amount == 0
end

function PSFuelDatabase.Ensure()
    local ok, err = pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_vehicles` (
            `plate` varchar(16) NOT NULL,
            `fuel` decimal(6,2) NOT NULL DEFAULT 100.00,
            `leak_level` tinyint unsigned NOT NULL DEFAULT 0,
            `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            PRIMARY KEY (`plate`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_stations` (
            `station_id` varchar(64) NOT NULL,
            `label` varchar(100) NOT NULL,
            `owner_citizenid` varchar(64) DEFAULT NULL,
            `owner_name` varchar(100) DEFAULT NULL,
            `balance` bigint NOT NULL DEFAULT 0,
            `price_multiplier` decimal(4,2) NOT NULL DEFAULT 1.00,
            `total_sales` bigint NOT NULL DEFAULT 0,
            `total_litres` decimal(12,2) NOT NULL DEFAULT 0.00,
            `stock` decimal(12,2) NOT NULL DEFAULT 10000.00,
            `capacity` decimal(12,2) NOT NULL DEFAULT 10000.00,
            PRIMARY KEY (`station_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_transactions` (
            `id` bigint unsigned NOT NULL AUTO_INCREMENT,
            `station_id` varchar(64) NOT NULL,
            `citizenid` varchar(64) DEFAULT NULL,
            `player_name` varchar(100) DEFAULT NULL,
            `amount_paid` int NOT NULL DEFAULT 0,
            `fuel_amount` decimal(8,2) NOT NULL DEFAULT 0.00,
            `transaction_type` varchar(32) NOT NULL DEFAULT 'fuel',
            `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`id`),
            KEY `idx_station_created` (`station_id`,`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_settings` (
            `setting_key` varchar(64) NOT NULL,
            `setting_value` varchar(255) NOT NULL,
            PRIMARY KEY (`setting_key`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])


        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_audit_logs` (
            `id` bigint unsigned NOT NULL AUTO_INCREMENT,
            `action` varchar(64) NOT NULL,
            `source` int NOT NULL DEFAULT 0,
            `citizenid` varchar(64) DEFAULT NULL,
            `details` longtext DEFAULT NULL,
            `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`id`),
            KEY `idx_ps_fuel_audit_action_created` (`action`,`created_at`),
            KEY `idx_ps_fuel_audit_citizen` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_vehicle_profiles` (
            `model_hash` bigint NOT NULL,
            `model_name` varchar(80) NOT NULL,
            `fuel_type` varchar(16) NOT NULL DEFAULT 'petrol',
            `fast_charge_enabled` tinyint(1) NOT NULL DEFAULT 0,
            `updated_by` varchar(64) DEFAULT NULL,
            `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            PRIMARY KEY (`model_hash`),
            KEY `idx_ps_fuel_vehicle_type` (`fuel_type`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_wallets` (
            `identifier` varchar(128) NOT NULL,
            `cash` bigint NOT NULL DEFAULT 0,
            `bank` bigint NOT NULL DEFAULT 0,
            `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_reward_claims` (
            `claim_key` varchar(128) NOT NULL,
            `citizenid` varchar(64) DEFAULT NULL,
            `reward_type` varchar(32) NOT NULL,
            `amount` int NOT NULL DEFAULT 0,
            `status` varchar(16) NOT NULL DEFAULT 'reserved',
            `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
            `paid_at` timestamp NULL DEFAULT NULL,
            PRIMARY KEY (`claim_key`),
            KEY `idx_ps_fuel_reward_citizen` (`citizenid`,`created_at`),
            KEY `idx_ps_fuel_reward_status` (`status`,`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_custom_stations` (
            `station_id` varchar(64) NOT NULL,
            `label` varchar(100) NOT NULL,
            `x` decimal(12,4) NOT NULL,
            `y` decimal(12,4) NOT NULL,
            `z` decimal(12,4) NOT NULL,
            `heading` decimal(8,3) NOT NULL DEFAULT 0.000,
            `pump_model` varchar(80) NOT NULL DEFAULT 'prop_gas_pump_1a',
            `purchase_price` int NOT NULL DEFAULT 200000,
            `capacity` decimal(12,2) NOT NULL DEFAULT 15000.00,
            `created_by` varchar(64) DEFAULT NULL,
            `active` tinyint(1) NOT NULL DEFAULT 1,
            `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`station_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])
        -- 3.6.0 hotfix: keep custom-station migrations hard-coded and scanner-safe.
        -- The removed generic ensureColumn helper was still referenced here in the first 3.6.0 build.
        if not columnExists('ps_fuel_custom_stations', 'heading') then
            MySQL.query.await('ALTER TABLE `ps_fuel_custom_stations` ADD COLUMN `heading` decimal(8,3) NOT NULL DEFAULT 0.000')
        end
        if not columnExists('ps_fuel_custom_stations', 'pump_model') then
            MySQL.query.await("ALTER TABLE `ps_fuel_custom_stations` ADD COLUMN `pump_model` varchar(80) NOT NULL DEFAULT 'prop_gas_pump_1a'")
        end

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_custom_chargers` (
            `charger_id` varchar(64) NOT NULL,
            `station_id` varchar(64) NOT NULL,
            `label` varchar(100) NOT NULL,
            `x` decimal(12,4) NOT NULL,
            `y` decimal(12,4) NOT NULL,
            `z` decimal(12,4) NOT NULL,
            `heading` decimal(8,3) NOT NULL DEFAULT 0.000,
            `fast_charge` tinyint(1) NOT NULL DEFAULT 1,
            `created_by` varchar(64) DEFAULT NULL,
            `active` tinyint(1) NOT NULL DEFAULT 1,
            `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
            PRIMARY KEY (`charger_id`),
            KEY `idx_ps_fuel_custom_charger_station` (`station_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_npc_deliveries` (
            `delivery_id` varchar(96) NOT NULL,
            `station_id` varchar(64) NOT NULL,
            `owner_identifier` varchar(64) DEFAULT NULL,
            `amount` decimal(12,2) NOT NULL DEFAULT 0.00,
            `delivered` decimal(12,2) NOT NULL DEFAULT 0.00,
            `cost` int NOT NULL DEFAULT 0,
            `status` varchar(24) NOT NULL DEFAULT 'ordered',
            `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
            `completed_at` timestamp NULL DEFAULT NULL,
            PRIMARY KEY (`delivery_id`),
            KEY `idx_ps_fuel_npc_delivery_station` (`station_id`,`status`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

        ensureLegacySchema()

        MySQL.query.await([[
            INSERT INTO ps_fuel_settings (setting_key, setting_value)
            VALUES ('market_multiplier', '1.0')
            ON DUPLICATE KEY UPDATE setting_key = VALUES(setting_key)
        ]])
    end)

    if not ok then
        PSFuelDatabase.Ready = false
        print(('[ps-fuel] Database initialisation failed: %s'):format(err))
        return false
    end

    PSFuelDatabase.Ready = true
    print('[ps-fuel] Database ready.')
    return true
end
