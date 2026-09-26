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


function A.NormaliseVehicleFuelFamily(value)
    value = tostring(value or ''):lower()
    if value == 'electric' then return 'electric' end
    local families = PSFuelConfig.FuelFamilies or {}
    if type(families[value]) == 'table' then return value end
    return nil
end

function A.FuelFamilyLabel(value)
    value = A.NormaliseVehicleFuelFamily(value) or tostring(value or 'petrol')
    local cfg = (PSFuelConfig.FuelFamilies or {})[value]
    return cfg and cfg.label or value
end

function A.DetectVehicleFuelFamily(model, vehicleClass)
    model = tonumber(model) or 0
    vehicleClass = tonumber(vehicleClass)

    local electric = PSFuelConfig.Electric or {}
    if electric.Enabled ~= false and electric.Models and electric.Models[model] == true then return 'electric' end

    local modelFamilies = PSFuelConfig.VehicleFuelFamilyModels or {}
    local explicit = A.NormaliseVehicleFuelFamily(modelFamilies[model])
    if explicit then return explicit end

    -- GTA classes 15 and 16 are helicopters and planes. Piston-aircraft models
    -- can be overridden to avgas above; the remaining aircraft default to turbine fuel.
    if vehicleClass == 15 or vehicleClass == 16 then return 'jet' end

    local diesel = PSFuelConfig.FuelTypes and PSFuelConfig.FuelTypes.diesel or {}
    if diesel.Models and diesel.Models[model] == true then return 'diesel' end
    if vehicleClass ~= nil and diesel.AllowedClasses and diesel.AllowedClasses[vehicleClass] == true then return 'diesel' end
    return 'petrol'
end

function A.CanCrossContaminate(baseFamily, selectedFamily)
    baseFamily = A.NormaliseVehicleFuelFamily(baseFamily) or tostring(baseFamily or ''):lower()
    selectedFamily = A.NormaliseVehicleFuelFamily(selectedFamily) or tostring(selectedFamily or ''):lower()
    if baseFamily == selectedFamily then return true end
    local quality = ((PSFuelConfig.Advanced or {}).FuelQuality or {})
    for _, group in ipairs(quality.CrossContaminationGroups or {}) do
        if group[baseFamily] == true and group[selectedFamily] == true then return true end
    end
    return false
end

function A.FuelFamily(fuelType)
    fuelType = tostring(fuelType or ''):lower()
    if fuelType == 'electric' or fuelType == 'electric_fast' then return 'electric' end
    local cfg = PSFuelConfig.FuelTypes and PSFuelConfig.FuelTypes[fuelType]
    return cfg and cfg.family or fuelType
end

function A.FuelCategory(fuelType)
    fuelType = tostring(fuelType or ''):lower()
    if fuelType == 'electric' or fuelType == 'electric_fast' then return 'electric' end
    local cfg = PSFuelConfig.FuelTypes and PSFuelConfig.FuelTypes[fuelType]
    if not cfg then return nil end
    if cfg.category then return tostring(cfg.category):lower() end

    -- Backwards-compatible fallback for custom fuel definitions that have not
    -- yet been given a category explicitly.
    local family = tostring(cfg.family or fuelType):lower()
    if family == 'petrol' then return 'road_petrol' end
    if family == 'diesel' then return 'road_diesel' end
    if family == 'avgas' then return 'aviation_piston' end
    if family == 'jet' then return 'aviation_turbine' end
    if family == 'electric' then return 'electric' end
    if family == 'methanol' or family == 'nitro' or family == 'rocket' then return 'racing_drag' end
    return family
end

function A.FuelCategoryLabel(category)
    category = tostring(category or ''):lower()
    local cfg = (PSFuelConfig.FuelCategories or {})[category]
    return cfg and cfg.label or category
end

function A.DetectVehicleFuelCategories(model, vehicleClass, baseFamily)
    model = tonumber(model) or 0
    vehicleClass = tonumber(vehicleClass)
    baseFamily = A.NormaliseVehicleFuelFamily(baseFamily) or A.DetectVehicleFuelFamily(model, vehicleClass)

    local categories = {}
    if baseFamily == 'electric' then
        categories.electric = true
        return categories
    elseif baseFamily == 'diesel' then
        categories.road_diesel = true
        return categories
    elseif baseFamily == 'avgas' then
        categories.aviation_piston = true
        return categories
    elseif baseFamily == 'jet' then
        categories.aviation_turbine = true
        return categories
    elseif baseFamily == 'methanol' or baseFamily == 'nitro' or baseFamily == 'rocket' then
        categories.racing_drag = true
        return categories
    end

    -- Petrol vehicles always receive normal road petrol. Performance/drag
    -- vehicles additionally receive the racing category rather than replacing
    -- normal road fuel entirely.
    categories.road_petrol = true

    if A.IsFlexFuel(model) then categories.flex_fuel = true end

    local detection = PSFuelConfig.VehicleCategoryDetection or {}
    if (detection.RacingModels and detection.RacingModels[model] == true)
        or (vehicleClass ~= nil and detection.RacingClasses and detection.RacingClasses[vehicleClass] == true)
    then
        categories.racing_drag = true
    end

    return categories
end

function A.VehicleSupportsFuelType(model, vehicleClass, baseFamily, fuelType)
    model = tonumber(model) or 0
    vehicleClass = tonumber(vehicleClass)
    baseFamily = A.NormaliseVehicleFuelFamily(baseFamily) or A.DetectVehicleFuelFamily(model, vehicleClass)
    fuelType = tostring(fuelType or ''):lower()

    if fuelType == 'electric' or fuelType == 'electric_fast' then
        return baseFamily == 'electric'
    end
    if baseFamily == 'electric' then return false end

    local typeCfg = PSFuelConfig.FuelTypes and PSFuelConfig.FuelTypes[fuelType]
    if type(typeCfg) ~= 'table' then return false end
    local category = A.FuelCategory(fuelType)
    local categories = A.DetectVehicleFuelCategories(model, vehicleClass, baseFamily)
    if category and categories[category] == true then
        if typeCfg.requiresFlexFuel == true and not A.IsFlexFuel(model) then return false end
        return true
    end

    -- Optional backwards-compatible wrong-fuel mode. It is disabled by default
    -- so the pump only exposes/accepts the vehicle's detected categories.
    if ((PSFuelConfig.VehicleCategoryDetection or {}).AllowWrongCategoryFuel) == true then
        local selectedFamily = tostring(typeCfg.family or fuelType):lower()
        if selectedFamily == baseFamily then
            return typeCfg.requiresFlexFuel ~= true or A.IsFlexFuel(model)
        end
        return (((PSFuelConfig.Advanced or {}).FuelQuality or {}).ContaminationEnabled) == true
            and A.CanCrossContaminate(baseFamily, selectedFamily)
    end

    return false
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
