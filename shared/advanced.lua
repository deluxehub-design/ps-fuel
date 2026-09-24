PSFuelAdvancedShared = PSFuelAdvancedShared or {}

local A = PSFuelAdvancedShared

function A.Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

function A.TrimPlate(plate)
    return tostring(plate or ''):gsub('^%s*(.-)%s*$', '%1'):upper()
end

function A.FuelFamily(fuelType)
    fuelType = tostring(fuelType or ''):lower()
    if fuelType == 'electric' or fuelType == 'electric_fast' then return 'electric' end
    local cfg = PSFuelConfig.FuelTypes and PSFuelConfig.FuelTypes[fuelType]
    return cfg and cfg.family or fuelType
end

function A.GetTankProfile(model, vehicleClass, electric)
    local cfg = ((PSFuelConfig.Advanced or {}).Tanks or {})
    local modelCap = cfg.ModelCapacity and cfg.ModelCapacity[tonumber(model)]
    local dual = cfg.DualTankModels and cfg.DualTankModels[tonumber(model)]
    local capacity

    if electric then
        capacity = tonumber(modelCap) or tonumber(cfg.DefaultEVKWh) or 75.0
    else
        capacity = tonumber(modelCap)
            or (cfg.ClassCapacityLitres and tonumber(cfg.ClassCapacityLitres[tonumber(vehicleClass)]))
            or tonumber(cfg.DefaultLitres)
            or 60.0
    end

    if dual then
        local main = tonumber(dual.main) or capacity * 0.55
        local secondary = tonumber(dual.secondary) or math.max(0, capacity - main)
        capacity = main + secondary
        return { capacity = capacity, main = main, secondary = secondary, dual = true }
    end

    return { capacity = capacity, main = capacity, secondary = 0, dual = false }
end

function A.PercentToVolume(percent, capacity)
    return math.max(0.0, (tonumber(percent) or 0.0) * (tonumber(capacity) or 0.0) / 100.0)
end

function A.VolumeToPercent(volume, capacity)
    capacity = math.max(0.001, tonumber(capacity) or 0.001)
    return A.Clamp((tonumber(volume) or 0.0) / capacity * 100.0, 0.0, 100.0)
end

function A.RecommendedOctane(model, vehicleClass)
    local quality = ((PSFuelConfig.Advanced or {}).FuelQuality or {})
    local profile = (PSFuelConfig.VehicleOctaneProfiles or {})[tonumber(model)]
    if profile then return tonumber(profile) or 87 end
    local byClass = quality.PerformanceClasses and quality.PerformanceClasses[tonumber(vehicleClass)]
    return tonumber(byClass) or tonumber(quality.DefaultRecommendedOctane) or 87
end

function A.IsFlexFuel(model)
    local quality = ((PSFuelConfig.Advanced or {}).FuelQuality or {})
    return quality.FlexFuelModels and quality.FlexFuelModels[tonumber(model)] == true
end

function A.FormatVolume(value)
    local units = (((PSFuelConfig.Advanced or {}).Units or {}).Volume or 'litres'):lower()
    value = tonumber(value) or 0
    if units == 'gallons' then
        return value * 0.264172, 'gal'
    end
    return value, 'L'
end


function A.ToBaseVolume(value)
    local units = (((PSFuelConfig.Advanced or {}).Units or {}).Volume or 'litres'):lower()
    value = tonumber(value) or 0
    if units == 'gallons' then return value / 0.264172 end
    return value
end

function A.FormatUnitPrice(price)
    local units = (((PSFuelConfig.Advanced or {}).Units or {}).Volume or 'litres'):lower()
    price = tonumber(price) or 0
    if units == 'gallons' then return price * 3.785411784, 'gal' end
    return price, 'L'
end

function A.FormatEconomy(l100)
    l100 = math.max(0.01, tonumber(l100) or 0.01)
    local mode = (((PSFuelConfig.Advanced or {}).Units or {}).Economy or 'l100km'):lower()
    if mode == 'mpg_us' then return 235.214583 / l100, 'MPG US' end
    if mode == 'mpg_uk' then return 282.480936 / l100, 'MPG UK' end
    return l100, 'L/100km'
end

function A.ChargeCurveMultiplier(percent, fast)
    local cfg = ((PSFuelConfig.Advanced or {}).EV or {})
    if cfg.ChargingCurveEnabled == false then return 1.0 end
    percent = A.Clamp(percent, 0, 100)
    local start = tonumber(cfg.SlowdownStartPercent) or 80
    if percent <= start then return 1.0 end
    local minRate = A.Clamp(cfg.MinimumChargeRateMultiplier or 0.25, 0.05, 1.0)
    local progress = (percent - start) / math.max(1, 100 - start)
    local mult = 1.0 - progress * (1.0 - minRate)
    if fast then mult = mult * 0.92 end
    return A.Clamp(mult, minRate, 1.0)
end
