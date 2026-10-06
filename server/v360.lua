-- PS Fuel 3.6.0 - runtime station builder, secure fuel recovery and network sync.
PSFuel360 = PSFuel360 or {}

local siphonSessions = {}

local function rateLimited(src, key, windowMs, burst)
    return PSFuelSecurity and PSFuelSecurity.RateLimit(src, key, windowMs or 1500, burst or 2)
end

local function adminAllowed(src)
    return src > 0 and IsPlayerAceAllowed(src, PSFuelConfig.AdminAce or 'ps-fuel.admin')
end

local function playerIdentifier(src)
    local p = PSFuelFramework and PSFuelFramework.GetPlayer and PSFuelFramework.GetPlayer(src)
    return p and PSFuelFramework.GetIdentifier(p) or nil
end

local function cleanLabel(value, fallback)
    value = tostring(value or ''):gsub('[\r\n\t]', ' '):gsub('%s+', ' '):gsub('^%s*(.-)%s*$', '%1')
    if value == '' then value = fallback or 'Custom Fuel Station' end
    return value:sub(1, 100)
end

local function nearSubmittedCoords(src, coords, maxDistance)
    if type(coords) ~= 'table' then return false end
    local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
    if not x or not y or not z then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 then return false end
    return #(GetEntityCoords(ped) - vec3(x,y,z)) <= math.max(1.0, tonumber(maxDistance) or 6.0)
end

lib.callback.register('ps-fuel:server:getRuntimeNetwork', function(src)
    if rateLimited(src, 'runtimeNetwork', 2000, 3) then return {stations={},chargers={}} end
    local stations = MySQL.query.await([[SELECT station_id,label,x,y,z,heading,pump_model,purchase_price,capacity
        FROM ps_fuel_custom_stations WHERE active=1 ORDER BY created_at]]) or {}
    local chargers = MySQL.query.await([[SELECT charger_id,station_id,label,x,y,z,heading,fast_charge
        FROM ps_fuel_custom_chargers WHERE active=1 ORDER BY created_at]]) or {}
    return {stations=stations,chargers=chargers}
end)

lib.callback.register('ps-fuel:server:adminCreateStation', function(src, data)
    if not adminAllowed(src) then return {success=false,message='Administrator permission required.'} end
    if rateLimited(src, 'adminCreateStation', 3000, 1) then return {success=false,message='Please wait before creating another station.'} end
    data = type(data)=='table' and data or {}
    local builder = PSFuelConfig.AdminBuilder or {}
    if not nearSubmittedCoords(src, data.coords, builder.MaxCreateDistance or 6.0) then
        return {success=false,message='The station location must be your current position.'}
    end
    local capacity = math.max(100.0, math.min(tonumber(builder.MaxStationCapacity) or 100000.0,
        tonumber(data.capacity) or tonumber(builder.DefaultStationCapacity) or 15000.0))
    local price = math.max(1, math.min(math.floor(tonumber(builder.MaxPurchasePrice) or 25000000),
        math.floor(tonumber(data.purchasePrice) or tonumber(builder.DefaultPurchasePrice) or 200000)))
    local id = ('custom_%d_%d_%04d'):format(os.time(), src, math.random(0,9999))
    local label = cleanLabel(data.label, 'Custom Fuel Station')
    local coords = data.coords
    local creator = playerIdentifier(src)
    local heading=tonumber(data.heading) or 0.0
    local pumpModel=tostring(builder.DefaultPumpModel or 'prop_gas_pump_1a'):gsub('[^%w_%-]',''):sub(1,80)
    if pumpModel=='' then pumpModel='prop_gas_pump_1a' end
    local inserted = MySQL.insert.await([[INSERT INTO ps_fuel_custom_stations
        (station_id,label,x,y,z,heading,pump_model,purchase_price,capacity,created_by,active) VALUES (?,?,?,?,?,?,?,?,?,?,1)]],
        {id,label,tonumber(coords.x),tonumber(coords.y),tonumber(coords.z),heading,pumpModel,price,capacity,creator})
    if not inserted then return {success=false,message='The custom station could not be saved.'} end
    local cfg = {
        id=id,label=label,coords=vec3(tonumber(coords.x),tonumber(coords.y),tonumber(coords.z)),
        priceMultiplier=1.0,purchasePrice=price,capacity=capacity,ownershipEnabled=true,
        interactionDistance=34.0,deliveryEnabled=true,custom=true,heading=heading,pumpModel=pumpModel,
        delivery={coords=vec3(tonumber(coords.x),tonumber(coords.y),tonumber(coords.z)),heading=heading,length=26.0,width=9.0,requireDirection=false}
    }
    if not PSFuelServerRuntime or not PSFuelServerRuntime.AddStation or not PSFuelServerRuntime.AddStation(cfg) then
        return {success=false,message='Saved to the database, but runtime registration failed. Restart ps-fuel.'}
    end
    TriggerClientEvent('ps-fuel:client:runtimeStationAdded', -1, {
        id=id,label=label,x=tonumber(coords.x),y=tonumber(coords.y),z=tonumber(coords.z),heading=heading,pumpModel=pumpModel,
        purchasePrice=price,capacity=capacity
    })
    return {success=true,message=('Created %s (%s). It is immediately purchasable.'):format(label,id),stationId=id}
end)

lib.callback.register('ps-fuel:server:adminCreateCharger', function(src, data)
    if not adminAllowed(src) then return {success=false,message='Administrator permission required.'} end
    if rateLimited(src, 'adminCreateCharger', 3000, 1) then return {success=false,message='Please wait before creating another charger.'} end
    data = type(data)=='table' and data or {}
    local builder = PSFuelConfig.AdminBuilder or {}
    if not nearSubmittedCoords(src, data.coords, builder.MaxCreateDistance or 6.0) then
        return {success=false,message='The charger location must be your current position.'}
    end
    local stationId=tostring(data.stationId or ''):sub(1,64)
    local station,cfg = PSFuelServerRuntime and PSFuelServerRuntime.GetStation and PSFuelServerRuntime.GetStation(stationId)
    if not station or not cfg then return {success=false,message='Enter a valid station ID to link this charger to.'} end
    local coords=data.coords
    local id=('charger_%d_%d_%04d'):format(os.time(),src,math.random(0,9999))
    local label=cleanLabel(data.label,'Private EV Charger')
    local heading=tonumber(data.heading) or 0.0
    local fast=data.fastCharge ~= false
    local inserted=MySQL.insert.await([[INSERT INTO ps_fuel_custom_chargers
        (charger_id,station_id,label,x,y,z,heading,fast_charge,created_by,active) VALUES (?,?,?,?,?,?,?,?,?,1)]],
        {id,stationId,label,tonumber(coords.x),tonumber(coords.y),tonumber(coords.z),heading,fast and 1 or 0,playerIdentifier(src)})
    if not inserted then return {success=false,message='The custom charger could not be saved.'} end
    local charger={id=id,stationId=stationId,label=label,coords=vec4(tonumber(coords.x),tonumber(coords.y),tonumber(coords.z),heading),fastCharge=fast,custom=true}
    if PSFuelServerRuntime and PSFuelServerRuntime.AddCharger then PSFuelServerRuntime.AddCharger(charger) end
    TriggerClientEvent('ps-fuel:client:runtimeChargerAdded',-1,{
        id=id,stationId=stationId,label=label,x=tonumber(coords.x),y=tonumber(coords.y),z=tonumber(coords.z),heading=heading,fastCharge=fast
    })
    return {success=true,message=('Created %s and linked it to %s.'):format(label,stationId),chargerId=id}
end)

lib.callback.register('ps-fuel:server:beginSiphon', function(src, netId)
    local cfg=PSFuelConfig.FuelRecovery or {}
    if cfg.Enabled ~= true then return {success=false,message='Fuel recovery is disabled.'} end
    if rateLimited(src,'beginSiphon',tonumber(cfg.CooldownMs) or 5000,1) then return {success=false,message='Please wait before trying again.'} end
    local vehicle=PSFuelSecurity and PSFuelSecurity.VehicleFromNetId(netId) or 0
    if vehicle==0 or not PSFuelSecurity.PlayerNearEntity(src,vehicle,tonumber(cfg.TargetDistance) or 3.0) then
        return {success=false,message='Move closer to the vehicle.'}
    end
    if cfg.RequireEngineOff ~= false then
        local ok,running=pcall(GetIsVehicleEngineRunning,vehicle)
        if ok and running then return {success=false,message='Turn the engine off before draining the tank.'} end
    end
    local plate=''
    local ok,value=pcall(GetVehicleNumberPlateText,vehicle)
    if ok then plate=tostring(value or ''):gsub('^%s*(.-)%s*$','%1') end
    if plate=='' then return {success=false,message='Unable to read this vehicle plate.'} end
    local row=MySQL.single.await('SELECT fuel FROM ps_fuel_vehicles WHERE plate=?',{plate}) or {}
    local fuel=math.max(0,math.min(100,tonumber(row.fuel) or 0))
    if fuel<=0.05 then return {success=false,message='There is no stored fuel to drain from this vehicle.'} end
    local energy=MySQL.single.await('SELECT contamination,last_fuel_type,fuel_family FROM ps_fuel_vehicle_energy WHERE plate=?',{plate}) or {}
    local token=PSFuelSecurity.Token(src,'siphon')
    siphonSessions[src]={token=token,netId=tonumber(netId),plate=plate,fuel=fuel,expires=GetGameTimer()+30000,completing=false}
    return {success=true,token=token,fuel=fuel,contamination=tonumber(energy.contamination) or 0,lastFuelType=energy.last_fuel_type,fuelFamily=energy.fuel_family}
end)

lib.callback.register('ps-fuel:server:completeSiphon', function(src, token)
    local session=siphonSessions[src]
    if not session or session.completing or tostring(token or '')~=session.token or session.expires<GetGameTimer() then
        siphonSessions[src]=nil
        return {success=false,message='The fuel recovery session expired or is invalid.'}
    end
    local vehicle=PSFuelSecurity and PSFuelSecurity.VehicleFromNetId(session.netId) or 0
    if vehicle==0 or not PSFuelSecurity.PlayerNearEntity(src,vehicle,3.5) then
        siphonSessions[src]=nil
        return {success=false,message='Stay beside the vehicle until the fuel has been drained.'}
    end
    local actual=''
    local ok,value=pcall(GetVehicleNumberPlateText,vehicle)
    if ok then actual=tostring(value or ''):gsub('^%s*(.-)%s*$','%1') end
    if actual~=session.plate then siphonSessions[src]=nil return {success=false,message='Vehicle validation failed.'} end
    session.completing=true
    siphonSessions[src]=nil -- consume before yielding: replay-safe
    local affected=MySQL.update.await('UPDATE ps_fuel_vehicles SET fuel=0,updated_at=NOW() WHERE plate=?',{session.plate})
    if not affected or affected<1 then return {success=false,message='The stored fuel level could not be updated.'} end
    if (PSFuelConfig.FuelRecovery or {}).ClearWrongFuelContamination ~= false then
        MySQL.update.await([[UPDATE ps_fuel_vehicle_energy SET mixture_json='{}',contamination=0,last_fuel_type=NULL WHERE plate=?]],{session.plate})
    end
    TriggerClientEvent('ps-fuel:client:authoritativeFuelSet',-1,session.netId,0.0)
    return {success=true,drained=session.fuel,message=('Drained %.1f%% of the tank. Wrong/old fuel data was cleared.'):format(session.fuel)}
end)

AddEventHandler('playerDropped',function() siphonSessions[source]=nil end)
