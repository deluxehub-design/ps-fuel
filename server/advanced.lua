PSFuelAdvanced = PSFuelAdvanced or {}
local A = PSFuelAdvanced
local S = PSFuelAdvancedShared
local ready = false
local chargerLocks = {}
local repairSessions = {}
local suspicious = {}
local wholesaleMultiplier = 1.0

local unlockedFleetCards = {}

local function pinHash(pin)
    local hash = 5381
    for i = 1, #tostring(pin or '') do hash = ((hash * 33) + tostring(pin):byte(i)) % 2147483647 end
    return tostring(hash)
end

local function cfg(path, fallback)
    local value = PSFuelConfig.Advanced
    for key in tostring(path):gmatch('[^.]+') do
        value = type(value) == 'table' and value[key] or nil
        if value == nil then return fallback end
    end
    return value
end

local function identifier(source)
    local player = PSFuelFramework and PSFuelFramework.GetPlayer and PSFuelFramework.GetPlayer(source)
    return player and PSFuelFramework.GetIdentifier(player), player
end

local function vehicleClass(vehicle, reported)
    local value
    if vehicle and vehicle ~= 0 then
        local ok, state = pcall(function() return Entity(vehicle).state end)
        if ok and state then value = tonumber(state.psFuelClass) end
    end
    value = value or tonumber(reported)
    if not value or value < 0 or value > 22 then return 0 end
    return math.floor(value)
end

local function playerName(player)
    if not player then return 'Unknown' end
    local data = player.PlayerData or {}
    local char = data.charinfo or {}
    local name = ((char.firstname or '') .. ' ' .. (char.lastname or '')):gsub('^%s*(.-)%s*$', '%1')
    return name ~= '' and name or data.name or 'Unknown'
end


local function baseFuelFamily(model, class, electric)
    if electric then return 'electric' end
    local diesel = PSFuelConfig.FuelTypes and PSFuelConfig.FuelTypes.diesel or {}
    if diesel.Models and diesel.Models[tonumber(model)] == true then return 'diesel' end
    if diesel.AllowedClasses and diesel.AllowedClasses[tonumber(class)] == true then return 'diesel' end
    return 'petrol'
end

local function discord(title, description, fields)
    local dc = cfg('Discord', {})
    if dc.Enabled ~= true or not dc.Webhook or dc.Webhook == '' then return end
    local payload = {
        username = 'PS Fuel 3.4.0',
        embeds = {{
            title = title,
            description = description,
            color = 1752220,
            fields = fields or {},
            footer = { text = os.date('!%Y-%m-%d %H:%M:%S UTC') }
        }}
    }
    PerformHttpRequest(dc.Webhook, function() end, 'POST', json.encode(payload), { ['Content-Type']='application/json' })
end

local function ensureSchema()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_vehicle_energy` (
        `plate` varchar(16) NOT NULL,
        `model_hash` bigint NOT NULL DEFAULT 0,
        `capacity` decimal(10,2) NOT NULL DEFAULT 60.00,
        `fuel_family` varchar(16) NOT NULL DEFAULT 'petrol',
        `last_fuel_type` varchar(24) DEFAULT NULL,
        `recommended_octane` smallint NOT NULL DEFAULT 87,
        `mixture_json` longtext DEFAULT NULL,
        `contamination` decimal(6,3) NOT NULL DEFAULT 0.000,
        `filter_condition` decimal(6,2) NOT NULL DEFAULT 100.00,
        `pump_condition` decimal(6,2) NOT NULL DEFAULT 100.00,
        `injector_condition` decimal(6,2) NOT NULL DEFAULT 100.00,
        `tank_condition` decimal(6,2) NOT NULL DEFAULT 100.00,
        `charging_port_condition` decimal(6,2) NOT NULL DEFAULT 100.00,
        `ev_battery_health` decimal(6,2) NOT NULL DEFAULT 100.00,
        `odometer_km` decimal(12,2) NOT NULL DEFAULT 0.00,
        `lifetime_fuel` decimal(14,3) NOT NULL DEFAULT 0.000,
        `lifetime_cost` bigint NOT NULL DEFAULT 0,
        `trip_distance_km` decimal(12,3) NOT NULL DEFAULT 0.000,
        `trip_fuel` decimal(12,3) NOT NULL DEFAULT 0.000,
        `trip_cost` bigint NOT NULL DEFAULT 0,
        `trip_idle_fuel` decimal(12,3) NOT NULL DEFAULT 0.000,
        `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (`plate`), KEY `idx_psfuel_energy_model` (`model_hash`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_vehicle_history` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `plate` varchar(16) NOT NULL,
        `station_id` varchar(64) DEFAULT NULL,
        `fuel_type` varchar(24) NOT NULL,
        `volume` decimal(10,3) NOT NULL DEFAULT 0,
        `amount_paid` int NOT NULL DEFAULT 0,
        `odometer_km` decimal(12,2) DEFAULT NULL,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY (`id`), KEY `idx_psfuel_history_plate` (`plate`,`created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_fleet_accounts` (
        `account_id` varchar(64) NOT NULL,
        `label` varchar(100) NOT NULL,
        `job_name` varchar(64) DEFAULT NULL,
        `balance` bigint NOT NULL DEFAULT 0,
        `daily_limit` int NOT NULL DEFAULT 2500,
        `active` tinyint(1) NOT NULL DEFAULT 1,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY (`account_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_fleet_cards` (
        `card_id` varchar(64) NOT NULL,
        `account_id` varchar(64) NOT NULL,
        `holder_identifier` varchar(64) DEFAULT NULL,
        `holder_name` varchar(100) DEFAULT NULL,
        `pin_hash` varchar(128) DEFAULT NULL,
        `daily_limit` int NOT NULL DEFAULT 0,
        `spent_today` int NOT NULL DEFAULT 0,
        `spent_date` date DEFAULT NULL,
        `allowed_fuels` longtext DEFAULT NULL,
        `allowed_stations` longtext DEFAULT NULL,
        `active` tinyint(1) NOT NULL DEFAULT 1,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY (`card_id`), KEY `idx_psfuel_card_account` (`account_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_fleet_card_transactions` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `card_id` varchar(64) NOT NULL,
        `account_id` varchar(64) NOT NULL,
        `station_id` varchar(64) DEFAULT NULL,
        `fuel_type` varchar(24) DEFAULT NULL,
        `amount` int NOT NULL DEFAULT 0,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY (`id`), KEY `idx_psfuel_fleet_tx_card` (`card_id`,`created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_loyalty` (
        `identifier` varchar(64) NOT NULL,
        `points` bigint NOT NULL DEFAULT 0,
        `lifetime_spend` bigint NOT NULL DEFAULT 0,
        `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_station_employees` (
        `station_id` varchar(64) NOT NULL,
        `identifier` varchar(64) NOT NULL,
        `name` varchar(100) DEFAULT NULL,
        `role` varchar(32) NOT NULL DEFAULT 'employee',
        `permissions` longtext DEFAULT NULL,
        `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
        PRIMARY KEY (`station_id`,`identifier`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_station_advanced` (
        `station_id` varchar(64) NOT NULL,
        `supplier_id` varchar(64) DEFAULT 'localfuel',
        `maintenance` decimal(6,2) NOT NULL DEFAULT 100.00,
        `storage_level` tinyint unsigned NOT NULL DEFAULT 0,
        `pump_level` tinyint unsigned NOT NULL DEFAULT 0,
        `charger_level` tinyint unsigned NOT NULL DEFAULT 0,
        `security_level` tinyint unsigned NOT NULL DEFAULT 0,
        `tanker_level` tinyint unsigned NOT NULL DEFAULT 0,
        `delivery_costs` bigint NOT NULL DEFAULT 0,
        `robbery_losses` bigint NOT NULL DEFAULT 0,
        `ev_revenue` bigint NOT NULL DEFAULT 0,
        `promotion_per_litre` decimal(8,3) NOT NULL DEFAULT 0.000,
        PRIMARY KEY (`station_id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_tanker_cargo` (
        `plate` varchar(16) NOT NULL,
        `fuel_type` varchar(24) NOT NULL DEFAULT 'diesel',
        `amount` decimal(12,2) NOT NULL DEFAULT 0,
        `capacity` decimal(12,2) NOT NULL DEFAULT 30000,
        `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
        PRIMARY KEY (`plate`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_private_points` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `owner_identifier` varchar(64) DEFAULT NULL,
        `station_id` varchar(64) DEFAULT NULL,
        `point_type` varchar(24) NOT NULL,
        `label` varchar(100) NOT NULL,
        `coords_json` longtext NOT NULL,
        `auth_json` longtext DEFAULT NULL,
        `active` tinyint(1) NOT NULL DEFAULT 1,
        PRIMARY KEY (`id`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[CREATE TABLE IF NOT EXISTS `ps_fuel_spills` (
        `id` bigint unsigned NOT NULL AUTO_INCREMENT,
        `station_id` varchar(64) DEFAULT NULL,
        `coords_json` longtext NOT NULL,
        `severity` decimal(5,2) NOT NULL DEFAULT 1.00,
        `expires_at` datetime NOT NULL,
        PRIMARY KEY (`id`), KEY `idx_psfuel_spill_expiry` (`expires_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]])

    MySQL.query.await([[INSERT IGNORE INTO ps_fuel_settings (setting_key, setting_value) VALUES ('wholesale_multiplier','1.0')]])
    wholesaleMultiplier = tonumber(MySQL.scalar.await("SELECT setting_value FROM ps_fuel_settings WHERE setting_key='wholesale_multiplier'")) or 1.0
    ready = true
    print('[ps-fuel] Advanced 3.4.0 database ready.')
end

CreateThread(function()
    while not MySQL do Wait(100) end
    Wait(500)
    local ok, err = pcall(ensureSchema)
    if not ok then print(('[ps-fuel] Advanced database error: %s'):format(err)) end
end)

local function plateRow(plate)
    plate = S.TrimPlate(plate)
    if plate == '' then return nil end
    return MySQL.single.await('SELECT * FROM ps_fuel_vehicle_energy WHERE plate = ?', { plate })
end

function A.GetVehicleState(plate, model, class, electric, familyOverride)
    plate = S.TrimPlate(plate)
    if plate == '' then return nil end
    local tank = S.GetTankProfile(model, class, electric)
    local family = familyOverride or baseFuelFamily(model, class, electric)
    local octane = S.RecommendedOctane(model, class)
    MySQL.insert.await([[INSERT IGNORE INTO ps_fuel_vehicle_energy
        (plate, model_hash, capacity, fuel_family, recommended_octane) VALUES (?, ?, ?, ?, ?)]],
        { plate, tonumber(model) or 0, tank.capacity, family, octane })
    return plateRow(plate)
end

function A.GetLoyaltyDiscount(source)
    if cfg('Loyalty.Enabled', true) ~= true then return 0 end
    if cfg('Loyalty.RequireCard', false) == true and PSFuelInventory.GetCount(source,cfg('Loyalty.CardItem','ps_fuel_loyalty_card')) < 1 then return 0 end
    local id = identifier(source)
    if not id then return 0 end
    local row = MySQL.single.await('SELECT points FROM ps_fuel_loyalty WHERE identifier = ?', { id })
    local points = tonumber(row and row.points) or 0
    local best = 0
    for _, tier in ipairs(cfg('Loyalty.Tiers', {})) do
        if points >= (tonumber(tier.points) or 0) then best = tonumber(tier.discount) or best end
    end
    return math.max(0, math.min(50, best))
end

local function addLoyalty(source, amount)
    if cfg('Loyalty.Enabled', true) ~= true then return end
    local id = identifier(source)
    if not id then return end
    local rate = tonumber(cfg('Loyalty.PointsPerCurrency', 1)) or 1
    local points = math.max(0, math.floor((tonumber(amount) or 0) * rate))
    MySQL.query.await([[INSERT INTO ps_fuel_loyalty (identifier, points, lifetime_spend) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE points = points + VALUES(points), lifetime_spend = lifetime_spend + VALUES(lifetime_spend)]],
        { id, points, math.max(0, math.floor(tonumber(amount) or 0)) })
end

local function decodeList(value)
    if type(value) == 'table' then return value end
    if type(value) ~= 'string' or value == '' then return nil end
    local ok, result = pcall(json.decode, value)
    return ok and result or nil
end

local function listAllows(list, key)
    if not list then return true end
    if list[key] == true then return true end
    for _, value in pairs(list) do if tostring(value) == tostring(key) then return true end end
    return false
end

function A.TryFleetPayment(source, amount, stationId, fuelType)
    if cfg('Fleet.Enabled', true) ~= true then return false, 'disabled' end
    local item = cfg('Fleet.AutoUseFuelCard', false) == true and PSFuelInventory and PSFuelInventory.FindItem and PSFuelInventory.FindItem(source, cfg('Fleet.FuelCardItem', 'ps_fuel_card')) or nil
    if not item and cfg('Fleet.AllowDepartmentAccounts', true) == true then
        local player=PSFuelFramework.GetPlayer(source)
        local job=player and PSFuelFramework.GetJob(player) or {}
        local jobName=tostring(job.name or '')
        if jobName~='' and (cfg('Fleet.Jobs',{})[jobName] == true) then
            local account=MySQL.single.await([[SELECT * FROM ps_fuel_fleet_accounts WHERE active=1 AND (job_name=? OR account_id=?) LIMIT 1]],{jobName,'job:'..jobName})
            if account then
                local affected=MySQL.update.await('UPDATE ps_fuel_fleet_accounts SET balance=balance-? WHERE account_id=? AND balance>=?',{amount,account.account_id,amount})
                if affected and affected>0 then
                    MySQL.insert.await([[INSERT INTO ps_fuel_fleet_card_transactions (card_id,account_id,station_id,fuel_type,amount) VALUES (?,?,?,?,?)]],{'DEPT:'..jobName,account.account_id,stationId,fuelType,amount})
                    return true,{accountId=account.account_id,department=jobName}
                end
                return false,'fleet_balance'
            end
        end
    end
    if not item then return false, 'no_card' end
    local metadata = item.metadata or item.info or {}
    local cardId = metadata.cardId or metadata.card_id
    if not cardId then return false, 'invalid_card' end
    local card = MySQL.single.await('SELECT * FROM ps_fuel_fleet_cards WHERE card_id = ? AND active = 1', { tostring(cardId) })
    if not card then return false, 'inactive_card' end
    if card.pin_hash and card.pin_hash ~= '' then
        local unlocked=unlockedFleetCards[source]
        if not unlocked or unlocked.cardId~=card.card_id or unlocked.expires<GetGameTimer() then return false,'pin_required' end
    end
    if not listAllows(decodeList(card.allowed_fuels), fuelType) or not listAllows(decodeList(card.allowed_stations), stationId) then
        return false, 'not_authorised'
    end
    local today = os.date('%Y-%m-%d')
    local spent = card.spent_date == today and tonumber(card.spent_today) or 0
    local limit = tonumber(card.daily_limit) or 0
    if limit > 0 and spent + amount > limit then return false, 'daily_limit' end
    local affected = MySQL.update.await([[UPDATE ps_fuel_fleet_accounts SET balance = balance - ?
        WHERE account_id = ? AND active = 1 AND balance >= ?]], { amount, card.account_id, amount })
    if not affected or affected < 1 then return false, 'fleet_balance' end
    MySQL.update.await([[UPDATE ps_fuel_fleet_cards SET spent_today = ?, spent_date = ? WHERE card_id = ?]],
        { spent + amount, today, card.card_id })
    MySQL.insert.await([[INSERT INTO ps_fuel_fleet_card_transactions (card_id,account_id,station_id,fuel_type,amount) VALUES (?,?,?,?,?)]],
        {card.card_id,card.account_id,stationId,fuelType,amount})
    return true, { accountId=card.account_id, cardId=card.card_id, item=item }
end

function A.RefundFleetPayment(context, amount)
    if not context or not context.accountId then return end
    MySQL.update.await('UPDATE ps_fuel_fleet_accounts SET balance = balance + ? WHERE account_id = ?', { amount, context.accountId })
end

function A.RecordPurchase(data)
    if not ready or type(data) ~= 'table' then return end
    local plate = S.TrimPlate(data.plate)
    local volume = math.max(0, tonumber(data.volume) or 0)
    local price = math.max(0, math.floor(tonumber(data.price) or 0))
    local fuelType = tostring(data.fuelType or 'petrol')
    local family = S.FuelFamily(fuelType)
    local model = tonumber(data.model) or 0
    local class = tonumber(data.class) or 0
    local electric = family == 'electric'
    local state = A.GetVehicleState(plate, model, class, electric, data.baseFuelType)

    if state then
        local mixture = decodeList(state.mixture_json) or {}
        mixture[fuelType] = (tonumber(mixture[fuelType]) or 0) + volume
        local total = 0
        for _, value in pairs(mixture) do total = total + math.max(0, tonumber(value) or 0) end
        local contamination = tonumber(state.contamination) or 0
        local intended = tostring(state.fuel_family or family)
        local selectedCfg=(PSFuelConfig.FuelTypes or {})[fuelType]
        local flexMismatch=selectedCfg and selectedCfg.requiresFlexFuel==true and not S.IsFlexFuel(model)
        if (family ~= intended and family ~= 'electric') or flexMismatch then
            contamination = S.Clamp(contamination + (volume / math.max(1, tonumber(state.capacity) or 60)), 0, 1)
        elseif cfg('FuelQuality.DilutionRecovery', true) == true then
            contamination = S.Clamp(contamination - (volume / math.max(1, tonumber(state.capacity) or 60)) * 0.75, 0, 1)
        end
        MySQL.update.await([[UPDATE ps_fuel_vehicle_energy SET last_fuel_type=?, mixture_json=?, contamination=?,
            lifetime_fuel=lifetime_fuel+?, lifetime_cost=lifetime_cost+?, trip_fuel=trip_fuel+?, trip_cost=trip_cost+? WHERE plate=?]],
            { fuelType, json.encode(mixture), contamination, volume, price, volume, price, plate })
        MySQL.insert.await([[INSERT INTO ps_fuel_vehicle_history (plate,station_id,fuel_type,volume,amount_paid,odometer_km)
            VALUES (?,?,?,?,?,?)]], { plate, data.stationId, fuelType, volume, price, tonumber(state.odometer_km) or 0 })
    end

    if data.stationId then
        MySQL.insert.await('INSERT IGNORE INTO ps_fuel_station_advanced (station_id) VALUES (?)', { data.stationId })
        local ev = electric and price or 0
        local wear = math.max(0, volume / 1000 * (tonumber(cfg('StationMaintenance.WearPer1000Litres', 0.35)) or 0.35))
        MySQL.update.await([[UPDATE ps_fuel_station_advanced SET maintenance=GREATEST(0,maintenance-?), ev_revenue=ev_revenue+? WHERE station_id=?]],
            { wear, ev, data.stationId })
    end
    addLoyalty(data.source, price)
    TriggerEvent('ps-fuel:fuelPurchased', data)
    TriggerClientEvent('ps-fuel:client:fuelPurchased', data.source, data)
    if cfg('Discord.Events.purchases', true) == true then
        discord('Fuel purchase', ('%s purchased %.2f units of %s for %s%s'):format(data.playerName or 'Player', volume, fuelType, cfg('Units.CurrencySymbol','£'), price))
    end
end

function A.UpdateTelemetry(plate, data)
    if not ready then return false end
    plate = S.TrimPlate(plate)
    if plate == '' or type(data) ~= 'table' then return false end
    local distance = S.Clamp(data.distanceKm or 0, 0, 25)
    local idle = S.Clamp(data.idleFuel or 0, 0, 10)
    local wearCfg = cfg('Wear', {})
    local energy = MySQL.single.await('SELECT contamination FROM ps_fuel_vehicle_energy WHERE plate=?', { plate }) or {}
    local contamination = S.Clamp(energy.contamination or 0, 0, 1)
    local elapsedMinutes = S.Clamp(data.elapsedMinutes or 0.5, 0, 2)
    local wrongFuelWear = contamination * elapsedMinutes * (tonumber(cfg('FuelQuality.WrongFuelWearPerMinute', 1.25)) or 1.25)
    local filterWear = distance / 100 * (tonumber(wearCfg.FilterWearPer100Km) or 0.4)
    local pumpWear = distance / 100 * (tonumber(wearCfg.PumpWearPer100Km) or 0.25) + wrongFuelWear
    local injectorWear = distance / 100 * (tonumber(wearCfg.InjectorWearPer100Km) or 0.3) + wrongFuelWear
    local batteryWear = distance / 1000 * (tonumber(wearCfg.EVBatteryDegradationPer1000Km) or 0.1)
    MySQL.update.await([[UPDATE ps_fuel_vehicle_energy SET
        odometer_km=odometer_km+?, trip_distance_km=trip_distance_km+?, trip_idle_fuel=trip_idle_fuel+?,
        filter_condition=GREATEST(0,filter_condition-?), pump_condition=GREATEST(0,pump_condition-?),
        injector_condition=GREATEST(0,injector_condition-?), ev_battery_health=GREATEST(50,ev_battery_health-?) WHERE plate=?]],
        { distance, distance, idle, filterWear, pumpWear, injectorWear, batteryWear, plate })
    return true
end

function A.GetTrip(plate)
    local row = plateRow(plate)
    if not row then return nil end
    local distance = tonumber(row.trip_distance_km) or 0
    local fuel = tonumber(row.trip_fuel) or 0
    local l100 = distance > 0.05 and (fuel / distance * 100) or 0
    return {
        plate = S.TrimPlate(plate), distanceKm=distance, fuelUsed=fuel, cost=tonumber(row.trip_cost) or 0,
        idleFuel=tonumber(row.trip_idle_fuel) or 0, averageL100=l100, odometerKm=tonumber(row.odometer_km) or 0,
        batteryHealth=tonumber(row.ev_battery_health) or 100, filter=tonumber(row.filter_condition) or 100,
        pump=tonumber(row.pump_condition) or 100, injectors=tonumber(row.injector_condition) or 100,
        contamination=tonumber(row.contamination) or 0, recommendedOctane=tonumber(row.recommended_octane) or 87,
        capacity=tonumber(row.capacity) or 60, lastFuelType=row.last_fuel_type,
    }
end

function A.ResetTrip(plate)
    return (MySQL.update.await([[UPDATE ps_fuel_vehicle_energy SET trip_distance_km=0,trip_fuel=0,trip_cost=0,trip_idle_fuel=0 WHERE plate=?]], { S.TrimPlate(plate) }) or 0) > 0
end

function A.GetStationAdvanced(stationId)
    MySQL.insert.await('INSERT IGNORE INTO ps_fuel_station_advanced (station_id) VALUES (?)', { stationId })
    local row = MySQL.single.await('SELECT * FROM ps_fuel_station_advanced WHERE station_id=?', { stationId }) or {}
    local analytics = MySQL.single.await([[SELECT COUNT(*) transactions, COALESCE(SUM(amount_paid),0) revenue,
        COALESCE(SUM(fuel_amount),0) volume, COALESCE(AVG(amount_paid),0) average_transaction
        FROM ps_fuel_transactions WHERE station_id=?]], { stationId }) or {}
    local fuels = MySQL.query.await([[SELECT transaction_type, COUNT(*) transactions, COALESCE(SUM(fuel_amount),0) volume,
        COALESCE(SUM(amount_paid),0) revenue FROM ps_fuel_transactions WHERE station_id=? GROUP BY transaction_type ORDER BY volume DESC]], { stationId }) or {}
    local employees = MySQL.query.await('SELECT identifier,name,role,permissions FROM ps_fuel_station_employees WHERE station_id=? ORDER BY role,name', { stationId }) or {}
    return { station=row, analytics=analytics, fuelBreakdown=fuels, employees=employees, wholesaleMultiplier=wholesaleMultiplier }
end

function A.GetWholesaleMultiplier() return wholesaleMultiplier end
function A.GetStationPromotion(stationId)
    local value=MySQL.scalar.await('SELECT promotion_per_litre FROM ps_fuel_station_advanced WHERE station_id=?',{stationId})
    return math.max(0,tonumber(value) or 0)
end


function A.AcquireCharger(source, chargerId)
    if cfg('EV.ChargerOccupancy', true) ~= true or not chargerId then return true end
    local lock=chargerLocks[tostring(chargerId)]
    if lock and lock.source~=source and lock.expires>GetGameTimer() then return false end
    chargerLocks[tostring(chargerId)]={source=source,expires=GetGameTimer()+600000,fullSince=nil}
    return true
end

function A.MarkChargerFull(source, chargerId)
    local lock=chargerLocks[tostring(chargerId or '')]
    if lock and lock.source==source and not lock.fullSince then lock.fullSince=GetGameTimer() end
end

function A.ReleaseCharger(source, chargerId)
    local key=tostring(chargerId or '')
    local lock=chargerLocks[key]
    if lock and lock.source==source then chargerLocks[key]=nil end
end

CreateThread(function()
    while true do
        Wait(60000)
        local ev=cfg('EV',{})
        local grace=(tonumber(ev.IdleFeeGraceMinutes) or 5)*60000
        local fee=math.max(0,math.floor(tonumber(ev.IdleFeePerMinute) or 5))
        for key,lock in pairs(chargerLocks) do
            if lock.expires<GetGameTimer() then chargerLocks[key]=nil
            elseif ev.IdleFeeEnabled==true and lock.fullSince and GetGameTimer()-lock.fullSince>grace and fee>0 then
                local player=PSFuelFramework.GetPlayer(lock.source)
                if player and PSFuelFramework.RemoveMoney(player,'bank',fee,'ps-fuel-ev-idle-fee') then
                    TriggerClientEvent('ox_lib:notify',lock.source,{title='PS Fuel',description=('EV charger idle fee: %s%d.'):format(cfg('Units.CurrencySymbol','£'),fee),type='warning'})
                end
            end
        end
    end
end)


lib.callback.register('ps-fuel:server:getVehicleAdvanced', function(source, netId, reportedClass)
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle == 0 or GetEntityType(vehicle) ~= 2 then return nil end
    if not PSFuelSecurity.PlayerNearEntity(source, vehicle, 12.0) then return nil end
    local plate = GetVehicleNumberPlateText(vehicle)
    local model = GetEntityModel(vehicle)
    local class = vehicleClass(vehicle, reportedClass)
    local electric=(PSFuelConfig.Electric or {}).Models and (PSFuelConfig.Electric or {}).Models[model]==true
    if not electric then local dbType=MySQL.scalar.await('SELECT fuel_type FROM ps_fuel_vehicle_profiles WHERE model_hash=?',{model}); electric=dbType=='electric' end
    local baseFamily = baseFuelFamily(model, class, electric)
    local row = A.GetVehicleState(plate, model, class, electric, baseFamily)
    return A.GetTrip(plate) or row
end)

lib.callback.register('ps-fuel:server:getTrip', function(source, plate) return A.GetTrip(plate) end)
lib.callback.register('ps-fuel:server:resetTrip', function(source, plate) return { success=A.ResetTrip(plate) } end)
lib.callback.register('ps-fuel:server:getStationAdvanced', function(source, stationId) return A.GetStationAdvanced(tostring(stationId or '')) end)

RegisterNetEvent('ps-fuel:server:telemetry', function(plate, data)
    if type(data) ~= 'table' then return end
    A.UpdateTelemetry(plate, data)
end)

RegisterNetEvent('ps-fuel:server:suspicious', function(reason, details)
    local source = source
    suspicious[source] = (suspicious[source] or 0) + 1
    if cfg('Discord.Events.suspicious', true) == true then discord('Suspicious fuel activity', ('source %s: %s'):format(source, tostring(reason)), {{name='Details',value='```'..json.encode(details or {})..'```'}}) end
end)

local function canRepair(source)
    local repair = PSFuelConfig.LeakRepair or {}
    if repair.RequireJobOrAce ~= true then return true end
    if IsPlayerAceAllowed(source, (PSFuelConfig.Leaks or {}).RepairAce or 'ps-fuel.repair') or IsPlayerAceAllowed(source, PSFuelConfig.AdminAce or 'ps-fuel.admin') then return true end
    local id, player = identifier(source)
    if not player then return false end
    local job = PSFuelFramework.GetJob(player)
    local required = (PSFuelConfig.Leaks or {}).RepairJobs and (PSFuelConfig.Leaks or {}).RepairJobs[job.name]
    local grade = tonumber(job.grade and (job.grade.level or job.grade.grade) or job.grade) or 0
    return required ~= nil and grade >= (tonumber(required) or 0)
end

local function beginRepair(source)
    local repair = PSFuelConfig.LeakRepair or {}
    local vehicle = GetVehiclePedIsIn(GetPlayerPed(source), false)
    if vehicle == 0 then
        local coords = GetEntityCoords(GetPlayerPed(source))
        for _, entity in ipairs(GetAllVehicles()) do
            if #(GetEntityCoords(entity)-coords) <= (tonumber(repair.Distance) or 4.0) then vehicle=entity break end
        end
    end
    if vehicle == 0 or not PSFuelSecurity.PlayerNearEntity(source, vehicle, tonumber(repair.Distance) or 4.0) then
        TriggerClientEvent('ps-fuel:client:repairRejected', source, 'Move closer to the damaged vehicle.') return
    end
    if not canRepair(source) then TriggerClientEvent('ps-fuel:client:repairRejected', source, 'You are not authorised to repair fuel leaks.') return end
    local plate = S.TrimPlate(GetVehicleNumberPlateText(vehicle))
    local row = MySQL.single.await('SELECT leak_level FROM ps_fuel_vehicles WHERE plate=?', { plate })
    local level = tonumber(row and row.leak_level) or 0
    if level <= 0 then TriggerClientEvent('ps-fuel:client:repairRejected', source, 'This vehicle has no fuel leak.') return end
    local token = ('%s:%s:%s'):format(source, os.time(), math.random(100000,999999))
    repairSessions[source] = { token=token, netId=NetworkGetNetworkIdFromEntity(vehicle), plate=plate, level=level, expires=GetGameTimer()+30000 }
    TriggerClientEvent('ps-fuel:client:startLeakRepair', source, repairSessions[source])
end

CreateThread(function()
    Wait(1000)
    local repair = PSFuelConfig.LeakRepair or {}
    if repair.Enabled ~= true or not repair.Item then return end
    local ok = PSFuelFramework.RegisterUsableItem(repair.Item, function(source) beginRepair(source) end)
    if not ok then print(('[ps-fuel] Unable to register leak repair item %s with %s.'):format(repair.Item, PSFuelFramework.GetName())) end
end)

RegisterNetEvent('ps-fuel:server:finishLeakRepair', function(token, success)
    local source = source
    local session = repairSessions[source]
    repairSessions[source] = nil
    if not session or session.token ~= token or session.expires < GetGameTimer() then return end
    if success ~= true then return end
    local vehicle = NetworkGetEntityFromNetworkId(session.netId)
    if vehicle == 0 or not PSFuelSecurity.PlayerNearEntity(source, vehicle, tonumber((PSFuelConfig.LeakRepair or {}).Distance) or 4.0) then return end
    local row = MySQL.single.await('SELECT leak_level FROM ps_fuel_vehicles WHERE plate=?', { session.plate })
    if not row or tonumber(row.leak_level) <= 0 then return end
    if (PSFuelConfig.LeakRepair or {}).ConsumeOnSuccess ~= false then
        local _, player = identifier(source)
        local removed = PSFuelInventory.ConsumeOne(source, player, (PSFuelConfig.LeakRepair or {}).Item or 'fuel_repair_kit')
        if removed ~= true then TriggerClientEvent('ps-fuel:client:repairRejected', source, 'The repair kit is no longer in your inventory.') return end
    end
    MySQL.update.await('UPDATE ps_fuel_vehicles SET leak_level=0 WHERE plate=?', { session.plate })
    TriggerClientEvent('ps-fuel:client:leakRepairComplete', source, session.netId)
    TriggerEvent('ps-fuel:fuelLeakRepaired', source, session.plate, session.level)
end)

RegisterCommand('fuelloyaltycard', function(source)
    if source==0 or cfg('Loyalty.Enabled',true)~=true then return end
    local id,player=identifier(source)
    if not id or not player then return end
    local itemName=cfg('Loyalty.CardItem','ps_fuel_loyalty_card')
    if PSFuelInventory.GetCount(source,itemName)>0 then return TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description='You already have a loyalty card.',type='inform'}) end
    local cost=math.max(0,tonumber(cfg('Loyalty.CardCost',25)) or 25)
    if cost>0 and (PSFuelFramework.GetMoney(player,'bank')<cost or PSFuelFramework.RemoveMoney(player,'bank',cost,'ps-fuel-loyalty-card')~=true) then
        return TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description='Unable to pay for the loyalty card.',type='error'})
    end
    local ok=PSFuelInventory.AddItem(source,player,itemName,1,{owner=id,issued=os.date('%Y-%m-%d')})
    if not ok and cost>0 then PSFuelFramework.AddMoney(player,'bank',cost,'ps-fuel-loyalty-card-refund') end
    TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description=ok and 'Loyalty card issued.' or 'Inventory is full.',type=ok and 'success' or 'error'})
end,false)

RegisterCommand('fuelcardpin', function(source,args)
    if source==0 then return end
    local item=PSFuelInventory.FindItem(source,cfg('Fleet.FuelCardItem','ps_fuel_card'))
    local metadata=item and (item.metadata or item.info) or {}
    local cardId=metadata.cardId or metadata.card_id
    if not cardId then return TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description='No fleet fuel card found.',type='error'}) end
    local card=MySQL.single.await('SELECT card_id,pin_hash FROM ps_fuel_fleet_cards WHERE card_id=? AND active=1',{tostring(cardId)})
    if not card then return TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description='Fuel card is inactive.',type='error'}) end
    if not card.pin_hash or card.pin_hash=='' then
        unlockedFleetCards[source]={cardId=card.card_id,expires=GetGameTimer()+300000}
        return TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description='Fuel card does not require a PIN.',type='success'})
    end
    if pinHash(args[1] or '')~=card.pin_hash then return TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description='Incorrect fuel-card PIN.',type='error'}) end
    unlockedFleetCards[source]={cardId=card.card_id,expires=GetGameTimer()+300000}
    TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description='Fuel card unlocked for five minutes.',type='success'})
end,false)

RegisterCommand('fueltripreset', function(source)
    if source == 0 then return end
    TriggerClientEvent('ps-fuel:client:resetTrip', source)
end, false)

RegisterCommand('fuelcardissue', function(source, args)
    if source == 0 or not IsPlayerAceAllowed(source, PSFuelConfig.AdminAce or 'ps-fuel.admin') then return end
    local target = tonumber(args[1])
    local accountId = tostring(args[2] or '')
    if not target or accountId == '' then return TriggerClientEvent('ox_lib:notify', source, {title='PS Fuel',description='Usage: /fuelcardissue [server id] [account id] [daily limit]',type='error'}) end
    local targetId, targetPlayer = identifier(target)
    if not targetId then return end
    local account = MySQL.single.await('SELECT * FROM ps_fuel_fleet_accounts WHERE account_id=? AND active=1', { accountId })
    if not account then return TriggerClientEvent('ox_lib:notify', source, {title='PS Fuel',description='Fleet account not found.',type='error'}) end
    local cardId = ('FC-%06d-%d'):format(math.random(0,999999), os.time())
    local limit = tonumber(args[3]) or tonumber(account.daily_limit) or tonumber(cfg('Fleet.DefaultDailyLimit',2500))
    local pin=tostring(args[4] or '')
    local storedPin=pin~='' and pinHash(pin) or nil
    MySQL.insert.await([[INSERT INTO ps_fuel_fleet_cards (card_id,account_id,holder_identifier,holder_name,pin_hash,daily_limit) VALUES (?,?,?,?,?,?)]],
        { cardId, accountId, targetId, playerName(targetPlayer), storedPin, limit })
    local metadata = { cardId=cardId, accountId=accountId, company=account.label, driver=playerName(targetPlayer), dailyLimit=limit, pinProtected=storedPin~=nil }
    PSFuelInventory.AddItem(target, targetPlayer, cfg('Fleet.FuelCardItem','ps_fuel_card'), 1, metadata)
end, false)

RegisterCommand('fuelfleetcreate', function(source, args)
    if source == 0 or not IsPlayerAceAllowed(source, PSFuelConfig.AdminAce or 'ps-fuel.admin') then return end
    local id = tostring(args[1] or '')
    local balance = math.max(0, math.floor(tonumber(args[2]) or 0))
    local label = table.concat(args, ' ', 3); if label == '' then label=id end
    if id == '' then return end
    local jobName=id:match('^job:(.+)$')
    MySQL.query.await([[INSERT INTO ps_fuel_fleet_accounts (account_id,label,job_name,balance,daily_limit) VALUES (?,?,?,?,?)
        ON DUPLICATE KEY UPDATE label=VALUES(label),job_name=VALUES(job_name),balance=VALUES(balance)]], { id,label,jobName,balance,cfg('Fleet.DefaultDailyLimit',2500) })
end, false)

CreateThread(function()
    while true do
        Wait(math.max(5, tonumber(cfg('Market.WholesaleUpdateMinutes',45))) * 60000)
        if cfg('Market.Enabled',true) == true then
            local step = tonumber(cfg('Market.Step',0.06)) or 0.06
            wholesaleMultiplier = S.Clamp(wholesaleMultiplier + ((math.random()*2-1)*step), cfg('Market.MinMultiplier',0.72), cfg('Market.MaxMultiplier',1.45))
            MySQL.update.await("UPDATE ps_fuel_settings SET setting_value=? WHERE setting_key='wholesale_multiplier'", { tostring(wholesaleMultiplier) })
            TriggerClientEvent('ps-fuel:client:wholesaleChanged', -1, wholesaleMultiplier)
        end
        MySQL.update.await('DELETE FROM ps_fuel_spills WHERE expires_at < NOW()')
    end
end)

exports('GetVehicleEnergyState', function(plate) return A.GetTrip(plate) end)
exports('GetWholesaleMultiplier', function() return wholesaleMultiplier end)
exports('CreateFleetAccount', function(accountId,label,balance,dailyLimit,jobName)
    jobName=jobName or tostring(accountId or ''):match('^job:(.+)$')
    MySQL.query.await([[INSERT INTO ps_fuel_fleet_accounts (account_id,label,job_name,balance,daily_limit) VALUES (?,?,?,?,?)
        ON DUPLICATE KEY UPDATE label=VALUES(label),job_name=VALUES(job_name)]], { accountId,label,jobName,balance or 0,dailyLimit or cfg('Fleet.DefaultDailyLimit',2500) }) return true
end)
exports('RegisterPrivateEnergyPoint', function(data)
    if type(data)~='table' or not data.label or not data.pointType or not data.coords then return nil end
    return MySQL.insert.await([[INSERT INTO ps_fuel_private_points (owner_identifier,station_id,point_type,label,coords_json,auth_json)
        VALUES (?,?,?,?,?,?)]], { data.ownerIdentifier,data.stationId,data.pointType,data.label,json.encode(data.coords),json.encode(data.auth or {}) })
end)
exports('GetTankerCargo', function(plate) return MySQL.single.await('SELECT * FROM ps_fuel_tanker_cargo WHERE plate=?',{S.TrimPlate(plate)}) end)
exports('SetTankerCargo', function(plate,fuelType,amount,capacity)
    MySQL.query.await([[INSERT INTO ps_fuel_tanker_cargo (plate,fuel_type,amount,capacity) VALUES (?,?,?,?)
        ON DUPLICATE KEY UPDATE fuel_type=VALUES(fuel_type),amount=LEAST(VALUES(amount),capacity),capacity=VALUES(capacity)]],
        {S.TrimPlate(plate),fuelType,amount,capacity or cfg('Tankers.DefaultCapacity',30000)}) return true
end)

local function stationAccess(source, stationId)
    local id = identifier(source)
    if not id then return false, false end
    local station = MySQL.single.await('SELECT owner_citizenid,balance,capacity,stock FROM ps_fuel_stations WHERE station_id=?',{stationId})
    if not station then return false,false end
    local owner = station.owner_citizenid == id
    local admin = IsPlayerAceAllowed(source, PSFuelConfig.AdminAce or 'ps-fuel.admin')
    if owner or admin then return true, owner, station end
    local employee = MySQL.single.await('SELECT role,permissions FROM ps_fuel_station_employees WHERE station_id=? AND identifier=?',{stationId,id})
    return employee ~= nil, false, station, employee
end

A.CanAccessStation = stationAccess

lib.callback.register('ps-fuel:server:setSupplier', function(source, stationId, supplierId)
    local allowed = stationAccess(source, stationId)
    local suppliers = cfg('Suppliers.Contracts', {})
    if not allowed or not suppliers[supplierId] then return {success=false,message='Supplier unavailable.'} end
    MySQL.query.await([[INSERT INTO ps_fuel_station_advanced (station_id,supplier_id) VALUES (?,?) ON DUPLICATE KEY UPDATE supplier_id=VALUES(supplier_id)]],{stationId,supplierId})
    return {success=true,message=('Supplier changed to %s.'):format(suppliers[supplierId].label or supplierId)}
end)

lib.callback.register('ps-fuel:server:orderNpcDelivery', function(source, stationId, amount)
    local allowed, _, station = stationAccess(source, stationId)
    if not allowed or not station then return {success=false,message='No station access.'} end
    local adv = MySQL.single.await('SELECT supplier_id FROM ps_fuel_station_advanced WHERE station_id=?',{stationId}) or {}
    local supplierId = adv.supplier_id or 'localfuel'
    local supplier = cfg('Suppliers.Contracts', {})[supplierId]
    if not supplier then return {success=false,message='No supplier contract selected.'} end
    amount = math.max(tonumber(supplier.minimumOrder) or 500, math.floor(tonumber(amount) or tonumber(supplier.minimumOrder) or 500))
    local space = math.max(0,(tonumber(station.capacity) or 0)-(tonumber(station.stock) or 0))
    amount = math.min(amount,space)
    if amount<=0 then return {success=false,message='Station storage is full.'} end
    local wholesale = tonumber(cfg('Market.BaseWholesalePrice',1.10)) * wholesaleMultiplier
    local cost = math.ceil(amount * wholesale * (tonumber(supplier.priceMultiplier) or 1))
    local affected = MySQL.update.await('UPDATE ps_fuel_stations SET balance=balance-? WHERE station_id=? AND balance>=?',{cost,stationId,cost})
    if not affected or affected<1 then return {success=false,message=('Station balance needs %s%d.'):format(cfg('Units.CurrencySymbol','£'),cost)} end
    MySQL.insert.await('INSERT IGNORE INTO ps_fuel_station_advanced (station_id) VALUES (?)',{stationId})
    MySQL.update.await('UPDATE ps_fuel_station_advanced SET delivery_costs=delivery_costs+? WHERE station_id=?',{cost,stationId})
    local deliveryMs = math.max(1,tonumber(supplier.deliveryMinutes) or 12)*60000
    SetTimeout(deliveryMs,function()
        local reliability = tonumber(supplier.reliability) or 1
        if math.random() <= reliability then
            MySQL.update.await('UPDATE ps_fuel_stations SET stock=LEAST(capacity,stock+?) WHERE station_id=?',{amount,stationId})
            TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description=('NPC delivery arrived: %.0f L.'):format(amount),type='success'})
        else
            local refund=math.floor(cost*.85)
            MySQL.update.await('UPDATE ps_fuel_stations SET balance=balance+? WHERE station_id=?',{refund,stationId})
            TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description=('Supplier failed delivery. %s%d refunded.'):format(cfg('Units.CurrencySymbol','£'),refund),type='error'})
        end
    end)
    return {success=true,message=('NPC delivery ordered: %.0f L for %s%d.'):format(amount,cfg('Units.CurrencySymbol','£'),cost)}
end)

lib.callback.register('ps-fuel:server:upgradeStation', function(source, stationId, upgrade)
    local allowed, owner, station = stationAccess(source,stationId)
    if not allowed or not station or not owner and not IsPlayerAceAllowed(source,PSFuelConfig.AdminAce or 'ps-fuel.admin') then return {success=false,message='Only the owner or admin can upgrade this station.'} end
    local valid={storage='storage_level',pumps='pump_level',chargers='charger_level',security='security_level',tanker='tanker_level'}
    local column=valid[upgrade]
    if not column then return {success=false,message='Invalid upgrade.'} end
    MySQL.insert.await('INSERT IGNORE INTO ps_fuel_station_advanced (station_id) VALUES (?)',{stationId})
    local row=MySQL.single.await(('SELECT `%s` level FROM ps_fuel_station_advanced WHERE station_id=?'):format(column),{stationId}) or {}
    local level=tonumber(row.level) or 0
    local prices=(cfg('StationUpgrades.Levels',{})[upgrade] or {})
    local nextLevel=level+1
    local cost=tonumber(prices[nextLevel+1])
    if not cost then return {success=false,message='This upgrade is already maxed.'} end
    local affected=MySQL.update.await('UPDATE ps_fuel_stations SET balance=balance-? WHERE station_id=? AND balance>=?',{cost,stationId,cost})
    if not affected or affected<1 then return {success=false,message='Station balance is too low.'} end
    MySQL.update.await(('UPDATE ps_fuel_station_advanced SET `%s`=? WHERE station_id=?'):format(column),{nextLevel,stationId})
    if upgrade=='storage' then MySQL.update.await('UPDATE ps_fuel_stations SET capacity=capacity+? WHERE station_id=?',{5000*nextLevel,stationId}) end
    return {success=true,message=('%s upgraded to level %d.'):format(upgrade,nextLevel)}
end)

lib.callback.register('ps-fuel:server:setPromotion', function(source,stationId,amount)
    local allowed=stationAccess(source,stationId)
    if not allowed then return {success=false,message='No station access.'} end
    amount=S.Clamp(amount or 0,0,1.0)
    MySQL.insert.await('INSERT IGNORE INTO ps_fuel_station_advanced (station_id) VALUES (?)',{stationId})
    MySQL.update.await('UPDATE ps_fuel_station_advanced SET promotion_per_litre=? WHERE station_id=?',{amount,stationId})
    return {success=true,message=('Promotion set to %s%.3f per litre.'):format(cfg('Units.CurrencySymbol','£'),amount)}
end)

lib.callback.register('ps-fuel:server:addStationEmployee', function(source, stationId, targetIdentifier, name, role)
    local allowed, owner = stationAccess(source,stationId)
    if not allowed or not owner and not IsPlayerAceAllowed(source,PSFuelConfig.AdminAce or 'ps-fuel.admin') then return {success=false,message='Only the station owner can manage employees.'} end
    targetIdentifier=tostring(targetIdentifier or '')
    if targetIdentifier=='' then return {success=false,message='Identifier required.'} end
    role=tostring(role or 'employee'):sub(1,32)
    local permissions = role=='manager' and {pricing=true,orders=true,analytics=true} or {analytics=true}
    MySQL.query.await([[INSERT INTO ps_fuel_station_employees (station_id,identifier,name,role,permissions) VALUES (?,?,?,?,?)
        ON DUPLICATE KEY UPDATE name=VALUES(name),role=VALUES(role),permissions=VALUES(permissions)]],{stationId,targetIdentifier,tostring(name or targetIdentifier):sub(1,100),role,json.encode(permissions)})
    return {success=true,message='Employee saved.'}
end)

lib.callback.register('ps-fuel:server:removeStationEmployee', function(source, stationId, targetIdentifier)
    local allowed, owner = stationAccess(source,stationId)
    if not allowed or not owner and not IsPlayerAceAllowed(source,PSFuelConfig.AdminAce or 'ps-fuel.admin') then return {success=false,message='Only the station owner can manage employees.'} end
    MySQL.update.await('DELETE FROM ps_fuel_station_employees WHERE station_id=? AND identifier=?',{stationId,tostring(targetIdentifier or '')})
    return {success=true,message='Employee removed.'}
end)

lib.callback.register('ps-fuel:server:repairStation', function(source, stationId)
    local allowed, _, station=stationAccess(source,stationId)
    if not allowed or not station then return {success=false,message='No station access.'} end
    local row=MySQL.single.await('SELECT maintenance FROM ps_fuel_station_advanced WHERE station_id=?',{stationId}) or {maintenance=100}
    local missing=math.max(0,100-(tonumber(row.maintenance) or 100))
    local cost=math.ceil(missing*80)
    if cost<=0 then return {success=false,message='Station equipment is already in good condition.'} end
    local affected=MySQL.update.await('UPDATE ps_fuel_stations SET balance=balance-? WHERE station_id=? AND balance>=?',{cost,stationId,cost})
    if not affected or affected<1 then return {success=false,message='Station balance is too low.'} end
    MySQL.update.await('UPDATE ps_fuel_station_advanced SET maintenance=100 WHERE station_id=?',{stationId})
    return {success=true,message=('Station maintenance completed for %s%d.'):format(cfg('Units.CurrencySymbol','£'),cost)}
end)

lib.callback.register('ps-fuel:server:siphonFuel', function(source, netId, requested, fuelType, reportedClass)
    local siphon = cfg('Siphoning', {})
    if siphon.Enabled ~= true then return { success = false, message = 'Siphoning is disabled.' } end
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle == 0 or GetEntityType(vehicle) ~= 2 or not PSFuelSecurity.PlayerNearEntity(source, vehicle, 5.0) then
        return { success = false, message = 'Move closer to the vehicle.' }
    end
    if PSFuelInventory.GetCount(source, siphon.Item or 'siphon_hose') < 1 then
        return { success = false, message = 'You need a siphon hose.' }
    end
    local player = PSFuelFramework.GetPlayer(source)
    if not player then return { success = false, message = 'Player data unavailable.' } end
    local model, class = GetEntityModel(vehicle), vehicleClass(vehicle, reportedClass)
    local profile = S.GetTankProfile(model, class, false)
    local currentPct = tonumber(Entity(vehicle).state.fuel) or tonumber(GetVehicleFuelLevel(vehicle)) or 0
    local available = S.PercentToVolume(currentPct, profile.capacity)
    local amount = math.min(math.max(0, tonumber(requested) or 0), tonumber(siphon.MaximumLitres) or 20, available)
    if amount <= 0 then return { success = false, message = 'The tank is empty.' } end
    local item = S.FuelFamily(fuelType) == 'diesel' and 'diesel_can_20l' or 'fuel_can_20l'
    if not PSFuelInventory.AddItem(source, player, item, 1, { fuel = amount, capacity = 20, fuelType = fuelType }) then
        return { success = false, message = 'Inventory is full.' }
    end
    local newPct = S.VolumeToPercent(available - amount, profile.capacity)
    Entity(vehicle).state:set('fuel', newPct, true)
    Entity(vehicle).state:set('recoilFuel', newPct, true)
    if math.random(100) <= tonumber(siphon.PoliceChance or 20) then
        TriggerEvent('ps-fuel:server:fuelTheftDispatch', { source = source, netId = netId, amount = amount })
    end
    return { success = true, fuel = newPct, amount = amount, message = ('Siphoned %.1f L of fuel.'):format(amount) }
end)

lib.callback.register('ps-fuel:server:vehicleTransfer', function(source, sourceNetId, targetNetId, requested, sourceClass, targetClass)
    local sourceVehicle = NetworkGetEntityFromNetworkId(tonumber(sourceNetId) or 0)
    local targetVehicle = NetworkGetEntityFromNetworkId(tonumber(targetNetId) or 0)
    if sourceVehicle == 0 or targetVehicle == 0 or sourceVehicle == targetVehicle then
        return { success = false, message = 'Invalid vehicles.' }
    end
    if not PSFuelSecurity.PlayerNearEntity(source, sourceVehicle, 7.0) or not PSFuelSecurity.PlayerNearEntity(source, targetVehicle, 7.0) then
        return { success = false, message = 'Move closer to both vehicles.' }
    end
    if #(GetEntityCoords(sourceVehicle) - GetEntityCoords(targetVehicle)) > 8.0 then
        return { success = false, message = 'The vehicles are too far apart.' }
    end
    local sProfile = S.GetTankProfile(GetEntityModel(sourceVehicle), vehicleClass(sourceVehicle, sourceClass), false)
    local tProfile = S.GetTankProfile(GetEntityModel(targetVehicle), vehicleClass(targetVehicle, targetClass), false)
    local sPct = tonumber(Entity(sourceVehicle).state.fuel) or tonumber(GetVehicleFuelLevel(sourceVehicle)) or 0
    local tPct = tonumber(Entity(targetVehicle).state.fuel) or tonumber(GetVehicleFuelLevel(targetVehicle)) or 0
    local sVol = S.PercentToVolume(sPct, sProfile.capacity)
    local tVol = S.PercentToVolume(tPct, tProfile.capacity)
    local amount = math.min(math.max(0.1, tonumber(requested) or 5), sVol, math.max(0, tProfile.capacity - tVol), 50.0)
    if amount <= 0 then return { success = false, message = 'No transferable capacity is available.' } end
    local newSPct = S.VolumeToPercent(sVol - amount, sProfile.capacity)
    local newTPct = S.VolumeToPercent(tVol + amount, tProfile.capacity)
    Entity(sourceVehicle).state:set('fuel', newSPct, true)
    Entity(sourceVehicle).state:set('recoilFuel', newSPct, true)
    Entity(targetVehicle).state:set('fuel', newTPct, true)
    Entity(targetVehicle).state:set('recoilFuel', newTPct, true)
    return { success = true, sourceFuel = newSPct, targetFuel = newTPct, amount = amount, message = ('Transferred %.1f L.'):format(amount) }
end)

RegisterNetEvent('ps-fuel:server:wearLeak', function(netId, tankCondition)
    local source = source
    local vehicle = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle == 0 or GetEntityType(vehicle) ~= 2 or not PSFuelSecurity.PlayerNearEntity(source, vehicle, 8.0) then return end
    tankCondition = tonumber(tankCondition) or 100
    if tankCondition >= 20 then return end
    local plate = S.TrimPlate(GetVehicleNumberPlateText(vehicle))
    if plate == '' then return end
    local energy = MySQL.single.await('SELECT tank_condition FROM ps_fuel_vehicle_energy WHERE plate=?', { plate })
    if not energy or tonumber(energy.tank_condition) >= 20 then return end
    local current = tonumber(MySQL.scalar.await('SELECT leak_level FROM ps_fuel_vehicles WHERE plate=?', { plate })) or 0
    if current > 0 then return end
    MySQL.query.await([[INSERT INTO ps_fuel_vehicles (plate,fuel,leak_level) VALUES (?,100,1)
        ON DUPLICATE KEY UPDATE leak_level=GREATEST(leak_level,1)]], { plate })
    TriggerClientEvent('ps-fuel:client:setWearLeak', source, netId, 1)
    TriggerEvent('ps-fuel:fuelLeakStarted', source, plate, 1, 'tank_wear')
end)

RegisterNetEvent('ps-fuel:server:fuelStarted',function(stationId,netId,fuelType) TriggerEvent('ps-fuel:fuelStarted',source,stationId,netId,fuelType) end)
RegisterNetEvent('ps-fuel:server:fuelStopped',function(stationId,netId,fuelType,purchased,paid) TriggerEvent('ps-fuel:fuelStopped',source,stationId,netId,fuelType,purchased,paid) end)
RegisterNetEvent('ps-fuel:server:roadsideRequest',function(data) TriggerEvent('ps-fuel:roadsideRequested',source,data) end)
RegisterNetEvent('ps-fuel:server:fuelTheftDispatch',function(data) TriggerEvent('ps-fuel:fuelTheft',source,data) end)

exports('GetStationAnalytics',function(stationId) return A.GetStationAdvanced(stationId) end)
function A.RepairFuelSystemPart(plate,part,amount)
    local valid={filter='filter_condition',pump='pump_condition',injectors='injector_condition',tank='tank_condition',charging_port='charging_port_condition',battery='ev_battery_health'}
    local column=valid[tostring(part)]
    if not column then return false end
    amount=S.Clamp(amount or 100,0,100)
    local updated=MySQL.update.await(('UPDATE ps_fuel_vehicle_energy SET `%s`=LEAST(100,`%s`+?) WHERE plate=?'):format(column,column),{amount,S.TrimPlate(plate)})
    return updated and updated>0 or false
end
exports('RepairFuelSystemPart',A.RepairFuelSystemPart)

local function registerPortableItems()
    local containers=cfg('PortableFuel.Containers',{})
    for itemName,def in pairs(containers) do
        PSFuelFramework.RegisterUsableItem(itemName,function(source)
            local item=PSFuelInventory.FindItem(source,itemName)
            local metadata=item and (item.metadata or item.info) or {}
            TriggerClientEvent('ps-fuel:client:usePortableContainer',source,itemName,def,metadata,item and item.slot)
        end)
    end
end

CreateThread(function() Wait(1500) registerPortableItems() end)

lib.callback.register('ps-fuel:server:portableTransfer',function(source,itemName,slot,netId,direction,requested,reportedClass)
    local containers=cfg('PortableFuel.Containers',{})
    local def=containers[itemName]
    if not def then return {success=false,message='Unknown fuel container.'} end
    local vehicle=NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle==0 or GetEntityType(vehicle)~=2 or not PSFuelSecurity.PlayerNearEntity(source,vehicle,6.0) then return {success=false,message='Move closer to the vehicle.'} end
    local item=PSFuelInventory.FindItem(source,itemName)
    if not item then return {success=false,message='Container not found.'} end
    local metadata=item.metadata or item.info or {}
    local capacity=tonumber(metadata.capacity) or tonumber(def.capacity) or 20
    local held=S.Clamp(metadata.fuel or 0,0,capacity)
    local vehiclePct=tonumber(Entity(vehicle).state.fuel) or tonumber(GetVehicleFuelLevel(vehicle)) or 0
    local model=GetEntityModel(vehicle); local class=vehicleClass(vehicle,reportedClass)
    local base=baseFuelFamily(model,class,false)
    local tank=S.GetTankProfile(model,class,false)
    local vehicleVolume=S.PercentToVolume(vehiclePct,tank.capacity)
    local amount=math.max(.1,tonumber(requested) or math.min(5,capacity))
    local newHeld,newVehicleVolume
    if direction=='to_vehicle' then
        amount=math.min(amount,held,math.max(0,tank.capacity-vehicleVolume))
        if amount<=0 then return {success=false,message='Nothing can be transferred.'} end
        newHeld=held-amount; newVehicleVolume=vehicleVolume+amount
    else
        amount=math.min(amount,vehicleVolume,math.max(0,capacity-held))
        if amount<=0 then return {success=false,message='Nothing can be transferred.'} end
        newHeld=held+amount; newVehicleVolume=vehicleVolume-amount
    end
    local _,player=identifier(source)
    local oldMetadata=metadata
    if not PSFuelInventory.RemoveItem(source,player,itemName,1,oldMetadata,item.slot or slot) then return {success=false,message='Could not update the container.'} end
    local newMetadata={fuel=newHeld,capacity=capacity,fuelType=metadata.fuelType or (def.family=='diesel' and 'diesel' or 'petrol')}
    for k,v in pairs(metadata) do if newMetadata[k]==nil then newMetadata[k]=v end end
    if not PSFuelInventory.AddItem(source,player,itemName,1,newMetadata) then
        PSFuelInventory.AddItem(source,player,itemName,1,oldMetadata)
        return {success=false,message='Inventory is full.'}
    end
    local newPct=S.VolumeToPercent(newVehicleVolume,tank.capacity)
    Entity(vehicle).state:set('fuel',newPct,true)
    return {success=true,message=('Transferred %.1f L.'):format(amount),fuel=newPct,containerFuel=newHeld}
end)

lib.callback.register('ps-fuel:server:mobileRefuel',function(source,serviceNetId,targetNetId,requested,targetClass)
    local service=NetworkGetEntityFromNetworkId(tonumber(serviceNetId) or 0)
    local target=NetworkGetEntityFromNetworkId(tonumber(targetNetId) or 0)
    if service==0 or target==0 or GetEntityType(service)~=2 or GetEntityType(target)~=2 then return {success=false,message='Vehicle unavailable.'} end
    if not PSFuelSecurity.PlayerNearEntity(source,service,8.0) or not PSFuelSecurity.PlayerNearEntity(source,target,tonumber(cfg('MobileRefuel.MaxDistance',7.0))) then return {success=false,message='Vehicles are too far apart.'} end
    local model=GetEntityModel(service)
    if not (cfg('MobileRefuel.ServiceVehicles',{})[model]==true) then return {success=false,message='This vehicle is not configured for mobile refuelling.'} end
    local servicePlate=S.TrimPlate(GetVehicleNumberPlateText(service))
    local cargo=MySQL.single.await('SELECT * FROM ps_fuel_tanker_cargo WHERE plate=?',{servicePlate})
    if not cargo or tonumber(cargo.amount)<=0 then return {success=false,message='The service vehicle has no fuel cargo.'} end
    local targetTank=S.GetTankProfile(GetEntityModel(target),vehicleClass(target,targetClass),false)
    local pct=tonumber(Entity(target).state.fuel) or tonumber(GetVehicleFuelLevel(target)) or 0
    local current=S.PercentToVolume(pct,targetTank.capacity)
    local amount=math.min(math.max(.1,tonumber(requested) or 10),tonumber(cargo.amount),math.max(0,targetTank.capacity-current))
    if amount<=0 then return {success=false,message='Target tank is full.'} end
    MySQL.update.await('UPDATE ps_fuel_tanker_cargo SET amount=amount-? WHERE plate=? AND amount>=?',{amount,servicePlate,amount})
    local newPct=S.VolumeToPercent(current+amount,targetTank.capacity)
    Entity(target).state:set('fuel',newPct,true)
    return {success=true,message=('Mobile refuel delivered %.1f L.'):format(amount),fuel=newPct}
end)

local postPayEnabled = {}
local postPaySessions = {}

function A.IsPostPay(source)
    return cfg('DriveOffs.Enabled',true)==true and cfg('DriveOffs.AllowPostPayStations',false)==true and postPayEnabled[source]==true
end

function A.RecordPostPay(source, data)
    if not A.IsPostPay(source) then return end
    local s=postPaySessions[source] or {price=0,ownerCut=0,volume=0,stationId=data.stationId,account=data.account or 'bank',fuelType=data.fuelType}
    s.price=s.price+(tonumber(data.price) or 0)
    s.ownerCut=s.ownerCut+(tonumber(data.ownerCut) or 0)
    s.volume=s.volume+(tonumber(data.volume) or 0)
    s.stationId=data.stationId or s.stationId
    postPaySessions[source]=s
end

function A.SettlePostPay(source, stationId, account)
    local debt=postPaySessions[source]
    postPaySessions[source]=nil
    if not debt or debt.price<=0 then return true end
    local player=PSFuelFramework.GetPlayer(source)
    account=account or debt.account or 'bank'
    local paid=player and PSFuelFramework.GetMoney(player,account)>=(debt.price or 0) and PSFuelFramework.RemoveMoney(player,account,debt.price,'ps-fuel-postpay')==true
    if paid then
        TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description=('Post-pay settled: %s%d.'):format(cfg('Units.CurrencySymbol','£'),debt.price),type='success'})
        return true
    end
    if debt.stationId then
        MySQL.update.await('UPDATE ps_fuel_stations SET balance=GREATEST(0,balance-?), total_sales=GREATEST(0,total_sales-?) WHERE station_id=?',{debt.ownerCut,debt.price,debt.stationId})
        MySQL.insert.await('INSERT IGNORE INTO ps_fuel_station_advanced (station_id) VALUES (?)',{debt.stationId})
        MySQL.update.await('UPDATE ps_fuel_station_advanced SET robbery_losses=robbery_losses+? WHERE station_id=?',{debt.price,debt.stationId})
        MySQL.insert.await([[INSERT INTO ps_fuel_transactions (station_id,citizenid,player_name,amount_paid,fuel_amount,transaction_type) VALUES (?,?,?,?,?,'fuel_driveoff')]],
            {debt.stationId,identifier(source),playerName(player),-debt.price,debt.volume})
    end
    local ped=GetPlayerPed(source)
    local vehicle=ped~=0 and GetVehiclePedIsIn(ped,false) or 0
    local data={stationId=debt.stationId,amount=debt.price,volume=debt.volume,plate=vehicle~=0 and S.TrimPlate(GetVehicleNumberPlateText(vehicle)) or nil,model=vehicle~=0 and GetEntityModel(vehicle) or nil}
    TriggerEvent('ps-fuel:fuelDriveOff',source,data)
    TriggerEvent(cfg('DriveOffs.DispatchEvent','ps-fuel:server:fuelTheftDispatch'),data)
    local cctvEvent=cfg('DriveOffs.CCTVEvent','')
    if cctvEvent and cctvEvent~='' then TriggerEvent(cctvEvent,data) end
    if cfg('Discord.Events.suspicious',true)==true then discord('Fuel drive-off',('Player %s left without paying %s%d.'):format(playerName(player),cfg('Units.CurrencySymbol','£'),debt.price)) end
    TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description='Fuel payment failed. The station reported a drive-off.',type='error'})
    return false
end

RegisterCommand('fuelpostpay',function(source)
    if source==0 or cfg('DriveOffs.AllowPostPayStations',false)~=true then return end
    postPayEnabled[source]=not postPayEnabled[source]
    TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description=postPayEnabled[source] and 'Post-pay fuel enabled for your next nozzle session.' or 'Post-pay fuel disabled.',type='inform'})
end,false)

AddEventHandler('playerDropped',function()
    local source=source
    unlockedFleetCards[source]=nil
    if postPaySessions[source] then
        local debt=postPaySessions[source]
        postPaySessions[source]=nil
        if debt.stationId then
            MySQL.update.await('UPDATE ps_fuel_stations SET balance=GREATEST(0,balance-?),total_sales=GREATEST(0,total_sales-?) WHERE station_id=?',{debt.ownerCut,debt.price,debt.stationId})
            MySQL.insert.await('INSERT IGNORE INTO ps_fuel_station_advanced (station_id) VALUES (?)',{debt.stationId})
            MySQL.update.await('UPDATE ps_fuel_station_advanced SET robbery_losses=robbery_losses+? WHERE station_id=?',{debt.price,debt.stationId})
        end
        TriggerEvent('ps-fuel:fuelDriveOff',source,debt)
    end
    postPayEnabled[source]=nil
end)

function A.CreateSpill(stationId,coords,severity)
    if cfg('PumpDamage.Enabled',true)~=true then return nil end
    local seconds=math.max(15,tonumber(cfg('PumpDamage.SpillSeconds',90)))
    local id=MySQL.insert.await([[INSERT INTO ps_fuel_spills (station_id,coords_json,severity,expires_at) VALUES (?,?,?,DATE_ADD(NOW(),INTERVAL ? SECOND))]],
        {stationId,json.encode(coords),severity or 1,seconds})
    TriggerClientEvent('ps-fuel:client:createSpill',-1,{id=id,stationId=stationId,coords=coords,severity=severity or 1,seconds=seconds})
    return id
end

RegisterNetEvent('ps-fuel:server:pumpDamaged',function(stationId,coords,severity)
    local source=source
    if type(coords)~='table' then return end
    local ped=GetPlayerPed(source); if ped==0 then return end
    local p=GetEntityCoords(ped); local c=vec3(tonumber(coords.x) or 0,tonumber(coords.y) or 0,tonumber(coords.z) or 0)
    if #(p-c)>20 then return end
    severity=S.Clamp(severity or 1,.2,3)
    A.CreateSpill(stationId,{x=c.x,y=c.y,z=c.z},severity)
    local repairCost=math.ceil((tonumber(cfg('PumpDamage.RepairCost',450)) or 450)*severity)
    local player=PSFuelFramework.GetPlayer(source)
    local charged=false
    if player and PSFuelFramework.GetMoney(player,'bank')>=repairCost then
        charged=PSFuelFramework.RemoveMoney(player,'bank',repairCost,'ps-fuel-pump-damage')==true
    end
    if stationId then
        MySQL.insert.await('INSERT IGNORE INTO ps_fuel_station_advanced (station_id) VALUES (?)',{stationId})
        MySQL.update.await('UPDATE ps_fuel_station_advanced SET maintenance=GREATEST(0,maintenance-?) WHERE station_id=?',{math.min(25,8*severity),stationId})
        if not charged then
            MySQL.update.await('UPDATE ps_fuel_stations SET balance=GREATEST(0,balance-?) WHERE station_id=?',{repairCost,stationId})
        end
    end
    TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description=charged and ('Pump damage charge: %s%d.'):format(cfg('Units.CurrencySymbol','£'),repairCost) or 'The damaged station pump was charged to the station.',type='error'})
    A.LogAudit('pump_damage',source,{stationId=stationId,cost=repairCost,severity=severity,chargedPlayer=charged})
end)

lib.callback.register('ps-fuel:server:getPrivatePoints',function(source)
    local id,player=identifier(source)
    local job=player and PSFuelFramework.GetJob(player) or {}
    local rows=MySQL.query.await('SELECT * FROM ps_fuel_private_points WHERE active=1') or {}
    local out={}
    for _,row in ipairs(rows) do
        local auth=decodeList(row.auth_json) or {}
        local allowed=row.owner_identifier==id or not next(auth)
        if not allowed and auth.jobs and job.name then allowed=listAllows(auth.jobs,job.name) end
        if not allowed and auth.ace then allowed=IsPlayerAceAllowed(source,tostring(auth.ace)) end
        if not allowed and auth.fleetAccounts then
            local item=PSFuelInventory.FindItem(source,cfg('Fleet.FuelCardItem','ps_fuel_card'))
            local metadata=item and (item.metadata or item.info) or {}
            local accountId=metadata.accountId or metadata.account_id
            allowed=accountId and listAllows(auth.fleetAccounts,tostring(accountId)) or false
        end
        if allowed then out[#out+1]={id=row.id,stationId=row.station_id,pointType=row.point_type,label=row.label,coords=decodeList(row.coords_json),auth=auth} end
    end
    return out
end)

local partSessions={}
CreateThread(function()
    Wait(1700)
    local pcfg=cfg('FuelSystemParts',{})
    if pcfg.Enabled~=true then return end
    for itemName,def in pairs(pcfg.Items or {}) do
        PSFuelFramework.RegisterUsableItem(itemName,function(source)
            local ped=GetPlayerPed(source); local coords=GetEntityCoords(ped); local vehicle=0
            for _,entity in ipairs(GetAllVehicles()) do if #(GetEntityCoords(entity)-coords)<=4 then vehicle=entity break end end
            if vehicle==0 then return TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description='Move closer to a vehicle.',type='error'}) end
            local _,player=identifier(source)
            if pcfg.RequireMechanicJob==true then
                local job=player and PSFuelFramework.GetJob(player) or {}
                local required=(pcfg.Jobs or {})[job.name]
                local grade=tonumber(job.grade and (job.grade.level or job.grade.grade) or job.grade) or 0
                if required==nil or grade<(tonumber(required) or 0) then return TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description='A mechanic must install this part.',type='error'}) end
            end
            local token=('part:%s:%s:%s'):format(source,GetGameTimer(),math.random(10000,99999))
            partSessions[source]={token=token,item=itemName,def=def,netId=NetworkGetNetworkIdFromEntity(vehicle),plate=S.TrimPlate(GetVehicleNumberPlateText(vehicle)),expires=GetGameTimer()+30000}
            TriggerClientEvent('ps-fuel:client:installFuelPart',source,partSessions[source])
        end)
    end
end)

RegisterNetEvent('ps-fuel:server:finishFuelPart',function(token,success)
    local source=source; local session=partSessions[source]; partSessions[source]=nil
    if not session or session.token~=token or session.expires<GetGameTimer() or success~=true then return end
    local vehicle=NetworkGetEntityFromNetworkId(session.netId)
    if vehicle==0 or not PSFuelSecurity.PlayerNearEntity(source,vehicle,5.0) then return end
    local _,player=identifier(source)
    if not PSFuelInventory.ConsumeOne(source,player,session.item) then return TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description='Replacement part is missing.',type='error'}) end
    if A.RepairFuelSystemPart(session.plate,session.def.part,session.def.repair or 100) then
        TriggerClientEvent('ox_lib:notify',source,{title='PS Fuel',description=('%s installed.'):format(session.def.label or session.item),type='success'})
        TriggerEvent('ps-fuel:fuelSystemPartRepaired',source,session.plate,session.def.part)
    end
end)

local function registerPrivateInstallItems()
    local pcfg=cfg('PrivateEnergy',{})
    local definitions={
        [pcfg.HomeChargerItem or 'home_charger_kit']={pointType='home_charger',label='Home EV Charger'},
        [pcfg.BusinessPumpItem or 'business_pump_kit']={pointType='business_pump',label='Business Fuel Pump'},
    }
    for itemName,def in pairs(definitions) do
        PSFuelFramework.RegisterUsableItem(itemName,function(source)
            TriggerClientEvent('ps-fuel:client:placePrivateEnergyPoint',source,itemName,def)
        end)
    end
end
CreateThread(function() Wait(2200); if cfg('PrivateEnergy.Enabled',true)==true then registerPrivateInstallItems() end end)

lib.callback.register('ps-fuel:server:installPrivateEnergyPoint',function(source,itemName,def,label)
    local pcfg=cfg('PrivateEnergy',{})
    if pcfg.Enabled~=true or type(def)~='table' then return {success=false,message='Private energy points are disabled.'} end
    local expected = def.pointType=='home_charger' and (pcfg.HomeChargerItem or 'home_charger_kit') or (pcfg.BusinessPumpItem or 'business_pump_kit')
    if itemName~=expected or PSFuelInventory.GetCount(source,itemName)<1 then return {success=false,message='Installation item is missing.'} end
    local id,player=identifier(source); if not id or not player then return {success=false,message='Player data unavailable.'} end
    local ped=GetPlayerPed(source); if ped==0 then return {success=false,message='Player entity unavailable.'} end
    local coords=GetEntityCoords(ped)
    local auth={}
    if def.pointType=='business_pump' then
        local job=PSFuelFramework.GetJob(player) or {}
        if not job.name or job.name=='' then return {success=false,message='A business/job is required for this pump.'} end
        auth.jobs={[job.name]=true}; auth.minGrade=0
    end
    local pointId=MySQL.insert.await([[INSERT INTO ps_fuel_private_points (owner_identifier,point_type,label,coords_json,auth_json) VALUES (?,?,?,?,?)]],
        {id,def.pointType,tostring(label or def.label or 'Private Energy Point'):sub(1,100),json.encode({x=coords.x,y=coords.y,z=coords.z}),json.encode(auth)})
    if not pointId then return {success=false,message='Unable to install the energy point.'} end
    if not PSFuelInventory.ConsumeOne(source,player,itemName) then
        MySQL.update.await('DELETE FROM ps_fuel_private_points WHERE id=?',{pointId})
        return {success=false,message='Installation item could not be consumed.'}
    end
    TriggerClientEvent('ps-fuel:client:refreshPrivatePoints',-1)
    return {success=true,message=('%s installed.'):format(def.label or 'Energy point')}
end)

local function privatePointAuthorised(source,row,vehicle)
    local id,player=identifier(source); if row.owner_identifier and row.owner_identifier~='' and row.owner_identifier==id then return true end
    local auth=decodeList(row.auth_json) or {}; if not next(auth) then return true end
    local job=player and PSFuelFramework.GetJob(player) or {}
    if auth.jobs and job.name and listAllows(auth.jobs,job.name) then
        local required=tonumber(auth.minGrade) or 0; local grade=tonumber(job.grade and (job.grade.level or job.grade.grade) or job.grade) or 0
        if grade>=required then return true end
    end
    if auth.ace and IsPlayerAceAllowed(source,tostring(auth.ace)) then return true end
    if auth.plates and vehicle~=0 and listAllows(auth.plates,S.TrimPlate(GetVehicleNumberPlateText(vehicle))) then return true end
    if auth.fleetAccounts then
        local item=PSFuelInventory.FindItem(source,cfg('Fleet.FuelCardItem','ps_fuel_card'))
        local metadata=item and (item.metadata or item.info) or {}
        local accountId=metadata.accountId or metadata.account_id
        if accountId and listAllows(auth.fleetAccounts,tostring(accountId)) then return true end
    end
    return false
end

lib.callback.register('ps-fuel:server:usePrivatePoint',function(source,pointId,netId,amount,fuelType,account,reportedClass)
    local row=MySQL.single.await('SELECT * FROM ps_fuel_private_points WHERE id=? AND active=1',{tonumber(pointId) or 0})
    local vehicle=NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not row or vehicle==0 or GetEntityType(vehicle)~=2 then return {success=false,message='Energy point unavailable.'} end
    local coords=decodeList(row.coords_json) or {}; local c=vec3(tonumber(coords.x) or 0,tonumber(coords.y) or 0,tonumber(coords.z) or 0)
    local ped=GetPlayerPed(source)
    if ped==0 or #(GetEntityCoords(ped)-c)>12 or not PSFuelSecurity.PlayerNearEntity(source,vehicle,8.0) then return {success=false,message='Move closer to the energy point.'} end
    if not privatePointAuthorised(source,row,vehicle) then return {success=false,message='You are not authorised to use this private energy point.'} end
    local electric=row.point_type=='charger' or row.point_type=='home_charger'
    fuelType=electric and 'electric' or tostring(fuelType or 'petrol')
    local family=S.FuelFamily(fuelType)
    if electric and family~='electric' then return {success=false,message='This is an EV charger.'} end
    if not electric and family=='electric' then return {success=false,message='This is a liquid-fuel pump.'} end
    local class=vehicleClass(vehicle,reportedClass)
    local tank=S.GetTankProfile(GetEntityModel(vehicle),class,electric)
    local pct=tonumber(Entity(vehicle).state.fuel) or tonumber(GetVehicleFuelLevel(vehicle)) or 0
    local current=S.PercentToVolume(pct,tank.capacity)
    amount=math.min(math.max(.1,tonumber(amount) or 5),math.max(0,tank.capacity-current))
    if amount<=0 then return {success=false,message=electric and 'Battery is full.' or 'Tank is full.'} end
    local unit=electric and tonumber(PSFuelConfig.Electric.PricePerFuel) or tonumber(PSFuelConfig.PricePerFuel)
    local typeCfg=(PSFuelConfig.FuelTypes or {})[fuelType]; if typeCfg then unit=unit*(tonumber(typeCfg.priceMultiplier) or 1) end
    local price=math.ceil(amount*unit)
    local player=PSFuelFramework.GetPlayer(source); account=tostring(account or 'bank')
    if not player or PSFuelFramework.GetMoney(player,account)<price or not PSFuelFramework.RemoveMoney(player,account,price,'ps-fuel-private-energy') then return {success=false,message='Payment failed.'} end
    local newPct=S.VolumeToPercent(current+amount,tank.capacity); Entity(vehicle).state:set('fuel',newPct,true)
    A.RecordPurchase({source=source,stationId=row.station_id,plate=S.TrimPlate(GetVehicleNumberPlateText(vehicle)),model=GetEntityModel(vehicle),class=class,fuelType=fuelType,volume=amount,percent=newPct-pct,price=price,playerName=playerName(player),baseFuelType=baseFuelFamily(GetEntityModel(vehicle),class,electric)})
    return {success=true,message=('Added %.1f %s for %s%d.'):format(amount,electric and 'kWh' or 'L',cfg('Units.CurrencySymbol','£'),price),fuel=newPct}
end)

lib.callback.register('ps-fuel:server:getFuelHistory',function(source,plate)
    plate=S.TrimPlate(plate)
    if plate=='' then return {} end
    return MySQL.query.await([[SELECT station_id,fuel_type,volume,amount_paid,odometer_km,created_at FROM ps_fuel_vehicle_history WHERE plate=? ORDER BY id DESC LIMIT 30]],{plate}) or {}
end)

function A.LogAudit(action,source,details)
    local enabled=cfg('Discord.Events',{})
    local map={station_withdrawal='withdrawals',robbery_started='robberies',robbery_completed='robberies',delivery_completed='purchases',admin_setfuel='admin',vehicle_profile_changed='admin'}
    local key=map[action]
    if key and enabled[key]~=false then discord(('PS Fuel · %s'):format(action:gsub('_',' ')),('source %s'):format(source or 0),{{name='Details',value='```'..json.encode(details or {})..'```'}}) end
end

lib.callback.register('ps-fuel:server:getPriceBoards',function(source)
    local rows=MySQL.query.await('SELECT station_id,price_multiplier,stock,capacity FROM ps_fuel_stations') or {}
    local market=tonumber(MySQL.scalar.await("SELECT setting_value FROM ps_fuel_settings WHERE setting_key='market_multiplier'")) or 1.0
    local tax=1+(math.max(0,tonumber((PSFuelConfig.Pricing or {}).GlobalTaxPercent) or 0)/100)
    local base=tonumber(PSFuelConfig.PricePerFuel) or 2
    local out={}
    for _,row in ipairs(rows) do
        local stationMult=tonumber(row.price_multiplier) or 1
        local stock=tonumber(row.stock) or 0
        local dynamic=PSFuelConfig.DynamicPricing or {}
        local stockMult=1.0
        if dynamic.Enabled==true then
            if stock<=(tonumber(dynamic.LowStockThreshold) or 2500) then stockMult=1+(tonumber(dynamic.LowStockSurcharge) or .20)
            elseif stock>=(tonumber(dynamic.HighStockThreshold) or 8500) then stockMult=math.max(.05,1-(tonumber(dynamic.HighStockDiscount) or .10)) end
        end
        local common=base*stationMult*market*wholesaleMultiplier*stockMult*tax
        local data={}
        for key,fuel in pairs(PSFuelConfig.FuelTypes or {}) do if type(fuel)=='table' then data[key]=common*(tonumber(fuel.priceMultiplier) or 1) end end
        data.electric=(tonumber((PSFuelConfig.Electric or {}).PricePerFuel) or 1.5)*tax
        out[row.station_id]=data
    end
    return out
end)
