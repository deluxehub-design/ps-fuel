PSFuelDatabase = PSFuelDatabase or {}
PSFuelDatabase.Ready = false

local function ensureColumn(tableName, columnName, definition)
    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
    ]], { tableName, columnName })

    if tonumber(count) == 0 then
        MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(tableName, columnName, definition))
    end
end

local function ensureIndex(tableName, indexName, columns)
    local count = MySQL.scalar.await([[
        SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND INDEX_NAME = ?
    ]], { tableName, indexName })

    if tonumber(count) == 0 then
        MySQL.query.await(('ALTER TABLE `%s` ADD INDEX `%s` (%s)'):format(tableName, indexName, columns))
    end
end

local function importSchema()
    local sql = LoadResourceFile(GetCurrentResourceName(), 'install/ps-fuel.sql')
    if not sql or sql == '' then
        error('install/ps-fuel.sql could not be loaded')
    end

    sql = sql:gsub('/%*.-%*/', '')
    sql = sql:gsub('%-%-[^\r\n]*', '')

    local imported = 0
    for statement in sql:gmatch('([^;]+);') do
        statement = statement:match('^%s*(.-)%s*$')
        if statement and statement ~= '' then
            MySQL.query.await(statement)
            imported = imported + 1
        end
    end

    if imported == 0 then
        error('install/ps-fuel.sql did not contain any executable statements')
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

function PSFuelDatabase.Ensure()
    local ok, err = pcall(function()
        importSchema()

        ensureColumn('ps_fuel_vehicles', 'leak_level', 'tinyint unsigned NOT NULL DEFAULT 0')
        ensureColumn('ps_fuel_stations', 'stock', 'decimal(12,2) NOT NULL DEFAULT 10000.00')
        ensureColumn('ps_fuel_stations', 'capacity', 'decimal(12,2) NOT NULL DEFAULT 10000.00')

        ensureIndex('ps_fuel_vehicles', 'idx_ps_fuel_vehicles_updated', '`updated_at`')
        ensureIndex('ps_fuel_stations', 'idx_ps_fuel_stations_owner', '`owner_citizenid`')
        ensureIndex('ps_fuel_transactions', 'idx_ps_fuel_transactions_citizen', '`citizenid`,`created_at`')
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
