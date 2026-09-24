PSFuelAdvancedClient = PSFuelAdvancedClient or {}
local A = PSFuelAdvancedClient
local S = PSFuelAdvancedShared
local vehicleState = {}
local currentPlate
local sample = { vehicle=0, coords=nil, fuel=nil, distance=0, idle=0, used=0, lastSend=0 }
local reserveWarned = {}
local priceBoards = {}
local spills = {}

local function notify(message, kind)
    if PSFuelRuntime and PSFuelRuntime.Notify then return PSFuelRuntime.Notify(message, kind) end
    lib.notify({ title='PS Fuel', description=message, type=kind or 'inform' })
end

local function vehicleProfile(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
    local class = GetVehicleClass(vehicle)
    local model = GetEntityModel(vehicle)
    local base = PSFuelRuntime and PSFuelRuntime.GetVehicleProfile and PSFuelRuntime.GetVehicleProfile(vehicle) or {}
    local electric = base and base.fuelType == 'electric'
    local tank = S.GetTankProfile(model, class, electric)
    return { model=model, class=class, electric=electric, tank=tank, base=base }
end

local function plate(vehicle)
    return S.TrimPlate(GetVehicleNumberPlateText(vehicle))
end

local function fuel(vehicle)
    return PSFuelRuntime and PSFuelRuntime.GetFuel and PSFuelRuntime.GetFuel(vehicle) or GetVehicleFuelLevel(vehicle)
end

local function syncedVehicleClass(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return 0 end
    local class = GetVehicleClass(vehicle)
    local state = Entity(vehicle).state
    if state and tonumber(state.psFuelClass) ~= class then
        pcall(function() state:set('psFuelClass', class, true) end)
    end
    return class
end

local function volume(vehicle)
    local profile = vehicleProfile(vehicle)
    if not profile then return 0,0 end
    return S.PercentToVolume(fuel(vehicle), profile.tank.capacity), profile.tank.capacity
end


local function weatherConsumptionMultiplier(profile)
    if not profile then return 1 end
    local hash = GetPrevWeatherTypeHashName and GetPrevWeatherTypeHashName() or 0
    local snow = hash == joaat('XMAS') or hash == joaat('SNOW') or hash == joaat('BLIZZARD') or hash == joaat('SNOWLIGHT')
    local rain = hash == joaat('RAIN') or hash == joaat('THUNDER') or hash == joaat('CLEARING')
    if profile.electric then
        return snow and 1.18 or (rain and 1.04 or 1)
    end
    return snow and 1.08 or (rain and 1.03 or 1)
end

local function economyEstimate(vehicle)
    local profile = vehicleProfile(vehicle)
    if not profile then return 0 end
    if profile.electric then
        local rpm = GetVehicleCurrentRpm(vehicle)
        return 16.0 + rpm * 10.0
    end
    local cfg = ((PSFuelConfig.Advanced or {}).Economy or {})
    local base = tonumber(cfg.BaseL100Km) or 10.5
    local rpm = GetVehicleCurrentRpm(vehicle)
    local speed = GetEntitySpeed(vehicle) * 3.6
    local throttle = GetControlNormal(0, 71)
    local classMult = (PSFuelConfig.ClassMultiplier or {})[profile.class] or 1.0
    local result = base * classMult * (0.65 + rpm*(tonumber(cfg.RPMWeight) or .55) + throttle*(tonumber(cfg.ThrottleWeight) or .35))
    if speed > 130 then result = result * (1 + math.min(.6,(speed-130)/200)) end
    local mod = GetVehicleMod(vehicle, 11)
    if mod and mod >= 0 then result = result * (1 - (mod+1)*(tonumber(cfg.UpgradeEfficiencyPerEngineLevel) or .015)) end
    local state = vehicleState[plate(vehicle)]
    if state then
        local wear = math.min(tonumber(state.filter) or 100, tonumber(state.pump) or 100, tonumber(state.injectors) or 100)
        result = result * (1 + math.max(0,100-wear)/200)
        local fuelType = tostring(state.lastFuelType or '')
        local typeCfg = (PSFuelConfig.FuelTypes or {})[fuelType]
        local octane = typeCfg and tonumber(typeCfg.octane)
        local recommended = tonumber(state.recommendedOctane)
        if octane and recommended and octane < recommended then
            result = result * (1 + (recommended-octane) * tonumber((((PSFuelConfig.Advanced or {}).FuelQuality or {}).LowOctaneEfficiencyPenaltyPerPoint) or .01))
        end
    end
    result = result * weatherConsumptionMultiplier(profile)
    return math.max(1,result)
end

local function weatherRangeMultiplier(profile)
    if not profile or not profile.electric then return 1 end
    local hash = GetPrevWeatherTypeHashName and GetPrevWeatherTypeHashName() or 0
    local cold = hash == joaat('XMAS') or hash == joaat('SNOW') or hash == joaat('BLIZZARD') or hash == joaat('SNOWLIGHT')
    if cold then return 1 - (tonumber((((PSFuelConfig.Advanced or {}).EV or {}).ColdWeatherRangePenalty) or .15)) end
    return 1
end

function A.GetFuelCapacity(vehicle)
    local profile = vehicleProfile(vehicle)
    return profile and profile.tank.capacity or 0
end

function A.GetFuelType(vehicle)
    local profile = vehicleProfile(vehicle)
    if not profile then return 'unknown' end
    local state = vehicleState[plate(vehicle)]
    return state and state.lastFuelType or (profile.base and profile.base.fuelType) or 'petrol'
end

function A.GetFuelEconomy(vehicle)
    local raw = economyEstimate(vehicle)
    local value, unit = S.FormatEconomy(raw)
    return value, unit, raw
end

function A.GetFuelRange(vehicle)
    local current, capacity = volume(vehicle)
    local profile = vehicleProfile(vehicle)
    if not profile then return 0 end
    local state = vehicleState[plate(vehicle)]
    if profile.electric then
        local health = state and (tonumber(state.batteryHealth) or 100) or 100
        local kwh100 = math.max(8,economyEstimate(vehicle))
        return (current * (health/100) / kwh100 * 100) * weatherRangeMultiplier(profile)
    end
    local l100 = economyEstimate(vehicle)
    return current / math.max(.1,l100) * 100
end

function A.GetEVBatteryHealth(vehicle)
    local state = vehicleState[plate(vehicle)]
    return state and tonumber(state.batteryHealth) or 100
end

function A.IsFuelLeaking(vehicle)
    if exports['ps-fuel'].GetLeakLevel then return (exports['ps-fuel']:GetLeakLevel(vehicle) or 0) > 0 end
    return Entity(vehicle).state.recoilFuelLeak and Entity(vehicle).state.recoilFuelLeak > 0 or false
end

function A.GetTankSplit(vehicle)
    local profile = vehicleProfile(vehicle)
    if not profile then return nil end
    local total = S.PercentToVolume(fuel(vehicle),profile.tank.capacity)
    if not profile.tank.dual then return {main=total,secondary=0,capacity=profile.tank.capacity} end
    local main = math.min(profile.tank.main,total)
    return {main=main,secondary=math.max(0,total-main),capacity=profile.tank.capacity}
end

local function refreshVehicleState(vehicle)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    local state = lib.callback.await('ps-fuel:server:getVehicleAdvanced', false, netId, syncedVehicleClass(vehicle))
    if state then vehicleState[plate(vehicle)] = state end
end

CreateThread(function()
    while true do
        local vehicle = cache.vehicle
        if vehicle and vehicle ~= 0 and GetPedInVehicleSeat(vehicle,-1) == cache.ped then
            local p = plate(vehicle)
            if currentPlate ~= p then currentPlate=p refreshVehicleState(vehicle) end
            local coords = GetEntityCoords(vehicle)
            local nowFuel = fuel(vehicle)
            if sample.vehicle ~= vehicle then
                sample={vehicle=vehicle,coords=coords,fuel=nowFuel,distance=0,idle=0,used=0,lastSend=GetGameTimer()}
            else
                if sample.coords then sample.distance = sample.distance + #(coords-sample.coords)/1000 end
                local profile = vehicleProfile(vehicle)
                if sample.fuel and nowFuel < sample.fuel and profile then sample.used = sample.used + S.PercentToVolume(sample.fuel-nowFuel,profile.tank.capacity) end
                if GetIsVehicleEngineRunning(vehicle) and GetEntitySpeed(vehicle)<.25 and profile and not profile.electric then
                    local idleRate = profile.class==20 and (((PSFuelConfig.Advanced or {}).Economy or {}).TruckIdleLitresPerHour or 2.4) or (((PSFuelConfig.Advanced or {}).Economy or {}).IdleLitresPerHour or 1.1)
                    sample.idle = sample.idle + idleRate / 3600 * 2
                end
                sample.coords=coords sample.fuel=nowFuel
            end
            local reserve = tonumber((((PSFuelConfig.Advanced or {}).Economy or {}).ReservePercent) or 10)
            if nowFuel <= reserve then
                local cooldown = tonumber((((PSFuelConfig.Advanced or {}).Economy or {}).ReserveWarningCooldownSeconds) or 90)*1000
                if GetGameTimer()-(reserveWarned[p] or 0)>cooldown then
                    reserveWarned[p]=GetGameTimer()
                    notify(('Low fuel — %.1f%% · Range ~%.0f km'):format(nowFuel,A.GetFuelRange(vehicle)),'warning')
                end
            end
            if GetGameTimer()-sample.lastSend>30000 then
                TriggerServerEvent('ps-fuel:server:telemetry',p,{distanceKm=sample.distance,idleFuel=sample.idle,fuelUsed=sample.used,elapsedMinutes=0.5})
                sample.distance=0 sample.idle=0 sample.used=0 sample.lastSend=GetGameTimer()
                refreshVehicleState(vehicle)
            end
        else
            currentPlate=nil
            if sample.vehicle~=0 and sample.distance>0 then TriggerServerEvent('ps-fuel:server:telemetry',plate(sample.vehicle),{distanceKm=sample.distance,idleFuel=sample.idle,fuelUsed=sample.used,elapsedMinutes=0.5}) end
            sample={vehicle=0,coords=nil,fuel=nil,distance=0,idle=0,used=0,lastSend=GetGameTimer()}
        end
        Wait(2000)
    end
end)

CreateThread(function()
    while true do
        local vehicle=cache.vehicle
        if vehicle and vehicle~=0 and GetPedInVehicleSeat(vehicle,-1)==cache.ped then
            local state=vehicleState[plate(vehicle)]
            if state then
                local contamination=tonumber(state.contamination) or 0
                local powerPenalty=math.min(65,contamination*70)
                local fuelType=tostring(state.lastFuelType or '')
                local fuelCfg=(PSFuelConfig.FuelTypes or {})[fuelType]
                local octane=fuelCfg and tonumber(fuelCfg.octane)
                local recommended=tonumber(state.recommendedOctane) or 87
                if octane and octane<recommended then powerPenalty=powerPenalty+math.min(20,(recommended-octane)*4) end
                SetVehicleEnginePowerMultiplier(vehicle,-powerPenalty)
                SetVehicleEngineTorqueMultiplier(vehicle,math.max(.3,1-powerPenalty/100))
                if contamination>.45 and (((PSFuelConfig.Advanced or {}).FuelQuality or {}).SevereWrongFuelEffects)~=false then
                    local chance=tonumber((((PSFuelConfig.Advanced or {}).FuelQuality or {}).WrongFuelStallChance) or 12)
                    if math.random(1000)<=chance then SetVehicleEngineOn(vehicle,false,true,false) end
                end
                local pump=tonumber(state.pump) or 100
                if pump<30 and math.random(1000)<=math.floor((30-pump)*1.5) then
                    SetVehicleEngineOn(vehicle,false,true,false)
                    notify('Low fuel-pump pressure caused the engine to stall.','warning')
                end
                local tank=tonumber(state.tank) or 100
                if tank<20 and math.random(2500)<=math.floor(20-tank) and not A.IsFuelLeaking(vehicle) then
                    TriggerServerEvent('ps-fuel:server:wearLeak',NetworkGetNetworkIdFromEntity(vehicle),tank)
                end
            end
        end
        Wait(5000)
    end
end)

RegisterCommand('fueltrip',function()
    local vehicle=cache.vehicle or (PSFuelRuntime and PSFuelRuntime.ClosestVehicle and PSFuelRuntime.ClosestVehicle())
    if not vehicle or vehicle==0 then return notify('No vehicle found.','error') end
    refreshVehicleState(vehicle)
    local p=plate(vehicle)
    local state=vehicleState[p] or {}
    local current,capacity=volume(vehicle)
    local ev=A.GetEVBatteryHealth(vehicle)
    local eco,ecoUnit=A.GetFuelEconomy(vehicle)
    lib.registerContext({id='ps_fuel_trip',title=('Trip computer · %s'):format(p),options={
        {title='Fuel / energy',description=('%.1f / %.1f %s · %.1f%%'):format(S.FormatVolume(current),S.FormatVolume(capacity),select(2,S.FormatVolume(current)),fuel(vehicle)),icon='gas-pump'},
        {title='Estimated range',description=('~%.0f km'):format(A.GetFuelRange(vehicle)),icon='road'},
        {title='Current economy',description=('%.1f %s'):format(eco,ecoUnit),icon='gauge-high'},
        {title='Trip distance',description=('%0.1f km'):format(tonumber(state.distanceKm) or 0),icon='route'},
        {title='Trip fuel used',description=(function() local v,u=S.FormatVolume(tonumber(state.fuelUsed) or 0); return ('%0.2f %s'):format(v,u) end)(),icon='droplet'},
        {title='Trip cost',description=('%s%d'):format((((PSFuelConfig.Advanced or {}).Units or {}).CurrencySymbol or '£'),tonumber(state.cost) or 0),icon='coins'},
        {title='Idle fuel',description=(function() local v,u=S.FormatVolume(tonumber(state.idleFuel) or 0); return ('%0.2f %s'):format(v,u) end)(),icon='clock'},
        {title='EV battery health',description=('%0.1f%%'):format(ev),icon='battery-half',disabled=not vehicleProfile(vehicle).electric},
        {title='Reset trip',description='Reset distance, fuel and cost counters.',icon='rotate-left',onSelect=function() TriggerServerEvent('ps-fuel:server:telemetry',p,{distanceKm=sample.distance,idleFuel=sample.idle,fuelUsed=sample.used,elapsedMinutes=0.5}); Wait(200); local r=lib.callback.await('ps-fuel:server:resetTrip',false,p); if r and r.success then notify('Trip computer reset.','success') end end},
    }})
    lib.showContext('ps_fuel_trip')
end,false)

RegisterNetEvent('ps-fuel:client:resetTrip',function() ExecuteCommand('fueltrip') end)

RegisterNetEvent('ps-fuel:client:startLeakRepair',function(session)
    local vehicle=NetworkGetEntityFromNetworkId(session.netId)
    if vehicle==0 then return TriggerServerEvent('ps-fuel:server:finishLeakRepair',session.token,false) end
    local repair=PSFuelConfig.LeakRepair or {}
    local ok=true
    if repair.UseSkillCheck~=false then ok=lib.skillCheck(session.level==2 and (repair.SevereSkill or {'medium','hard','hard'}) or (repair.NormalSkill or {'easy','easy','medium'}),{'w','a','s','d'}) end
    if ok then
        ok=lib.progressCircle({duration=session.level==2 and (repair.SevereDuration or 10000) or (repair.Duration or 6500),label=session.level==2 and 'Repairing ruptured fuel tank...' or 'Repairing fuel leak...',position='bottom',canCancel=true,disable={move=true,car=true,combat=true}})
    end
    TriggerServerEvent('ps-fuel:server:finishLeakRepair',session.token,ok==true)
end)

RegisterNetEvent('ps-fuel:client:setWearLeak', function(netId, level)
    local vehicle=NetworkGetEntityFromNetworkId(netId)
    if vehicle~=0 and exports['ps-fuel'].SetLeakLevel then
        exports['ps-fuel']:SetLeakLevel(vehicle,tonumber(level) or 1)
        notify('Fuel tank wear has caused a leak.','error')
    end
end)

RegisterNetEvent('ps-fuel:client:repairRejected',function(message) notify(message,'error') end)
RegisterNetEvent('ps-fuel:client:leakRepairComplete',function(netId)
    local vehicle=NetworkGetEntityFromNetworkId(netId)
    if vehicle~=0 and exports['ps-fuel'].SetLeakLevel then exports['ps-fuel']:SetLeakLevel(vehicle,0) end
    notify('Fuel leak repaired.','success')
end)

RegisterCommand('roadsidefuel',function()
    local coords=GetEntityCoords(cache.ped)
    TriggerServerEvent((((PSFuelConfig.Advanced or {}).Roadside or {}).DispatchEvent or 'ps-fuel:server:roadsideRequest'),{x=coords.x,y=coords.y,z=coords.z})
    notify('Roadside fuel request sent.','success')
end,false)

RegisterCommand('siphonfuel',function(_,args)
    if (((PSFuelConfig.Advanced or {}).Siphoning or {}).Enabled)~=true then return end
    local vehicle=PSFuelRuntime and PSFuelRuntime.ClosestVehicle and PSFuelRuntime.ClosestVehicle()
    if not vehicle or vehicle==0 then return notify('No vehicle found.','error') end
    local requested=S.ToBaseVolume(tonumber(args[1]) or 5)
    local amount=math.min(requested,tonumber((((PSFuelConfig.Advanced or {}).Siphoning or {}).MaximumLitres) or 20))
    if amount<=0 then return end
    local cap=A.GetFuelCapacity(vehicle)
    local available=S.PercentToVolume(fuel(vehicle),cap)
    amount=math.min(amount,available)
    if amount<=0 then return notify('The tank is empty.','error') end
    if not lib.skillCheck({'easy','medium'},{'w','a','s','d'}) then return notify('Siphoning failed.','error') end
    local response=lib.callback.await('ps-fuel:server:siphonFuel',false,NetworkGetNetworkIdFromEntity(vehicle),amount,A.GetFuelType(vehicle),syncedVehicleClass(vehicle))
    if response and response.success then
        PSFuelRuntime.SetFuel(vehicle,response.fuel)
        notify(response.message,'success')
    else
        notify(response and response.message or 'Siphoning failed.','error')
    end
end,false)

RegisterCommand('fueltransfer',function(_,args)
    local sourceVeh=cache.vehicle
    if not sourceVeh or sourceVeh==0 then return notify('Sit in the source vehicle first.','error') end
    local target=PSFuelRuntime and PSFuelRuntime.ClosestVehicle and PSFuelRuntime.ClosestVehicle()
    if not target or target==0 or target==sourceVeh then return notify('Move near another vehicle.','error') end
    local amount=math.max(.1,S.ToBaseVolume(tonumber(args[1]) or 5))
    local sourceCap=A.GetFuelCapacity(sourceVeh); local targetCap=A.GetFuelCapacity(target)
    amount=math.min(amount,S.PercentToVolume(fuel(sourceVeh),sourceCap),targetCap-S.PercentToVolume(fuel(target),targetCap))
    if amount<=0 then return notify('No transferable capacity is available.','error') end
    local response=lib.callback.await('ps-fuel:server:vehicleTransfer',false,NetworkGetNetworkIdFromEntity(sourceVeh),NetworkGetNetworkIdFromEntity(target),amount,syncedVehicleClass(sourceVeh),syncedVehicleClass(target))
    if response and response.success then
        PSFuelRuntime.SetFuel(sourceVeh,response.sourceFuel)
        PSFuelRuntime.SetFuel(target,response.targetFuel)
        notify(response.message,'success')
    else
        notify(response and response.message or 'Fuel transfer failed.','error')
    end
end,false)

CreateThread(function()
    while true do
        if (((PSFuelConfig.Advanced or {}).PriceBoards or {}).Enabled)==true then
            local data=lib.callback.await('ps-fuel:server:getPriceBoards',false)
            if type(data)=='table' then priceBoards=data end
        end
        Wait(30000)
    end
end)

local function draw3d(coords,text)
    local ok,x,y=World3dToScreen2d(coords.x,coords.y,coords.z)
    if not ok then return end
    SetTextScale(0.0,.32); SetTextFont(4); SetTextCentre(true); SetTextOutline(); SetTextColour(255,255,255,230)
    BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandDisplayText(x,y)
end

CreateThread(function()
    while true do
        if (((PSFuelConfig.Advanced or {}).PriceBoards or {}).Enabled)==true then
            local coords=GetEntityCoords(cache.ped)
            local sleep=1500
            for _,station in ipairs(PSFuelConfig.Stations or {}) do
                local d=#(coords-station.coords)
                if d<tonumber((((PSFuelConfig.Advanced or {}).PriceBoards or {}).DrawDistance) or 35) then
                    sleep=0
                    local live=priceBoards[station.id] or {}
                    local petrol=tonumber(live.petrol) or (PSFuelConfig.PricePerFuel or 2.0)
                    local diesel=tonumber(live.diesel) or petrol*((PSFuelConfig.FuelTypes.diesel or {}).priceMultiplier or 1.12)
                    local premium=tonumber(live.premium) or petrol*((PSFuelConfig.FuelTypes.premium or {}).priceMultiplier or 1.35)
                    local p,unit=S.FormatUnitPrice(petrol); local d=S.FormatUnitPrice(diesel); local pr=S.FormatUnitPrice(premium)
                    draw3d(station.coords+vec3(0,0,tonumber((((PSFuelConfig.Advanced or {}).PriceBoards or {}).Height) or 2)),('~b~%s~s~\nRegular %.2f/%s  Premium %.2f/%s  Diesel %.2f/%s'):format(station.label or 'Fuel',p,unit,pr,unit,d,unit))
                end
            end
            Wait(sleep)
        else Wait(5000) end
    end
end)

exports('GetFuelType',A.GetFuelType)
exports('GetFuelCapacity',A.GetFuelCapacity)
exports('GetFuelRange',A.GetFuelRange)
exports('GetFuelEconomy',A.GetFuelEconomy)
exports('GetEVBatteryHealth',A.GetEVBatteryHealth)
exports('IsFuelLeaking',A.IsFuelLeaking)
exports('GetFuelTankSplit',A.GetTankSplit)
exports('GetFuelCapPosition',function(vehicle)
    if not vehicle or vehicle==0 then return nil end
    local model=GetEntityModel(vehicle)
    local custom=((((PSFuelConfig.Advanced or {}).PhysicalFuelCaps or {}).ModelOffsets) or {})[model]
    if custom then return GetOffsetFromEntityInWorldCoords(vehicle,custom.x or 0,custom.y or 0,custom.z or 0) end
    local bone=GetEntityBoneIndexByName(vehicle,(((PSFuelConfig.Advanced or {}).PhysicalFuelCaps or {}).DefaultBone or 'wheel_lr'))
    if bone~=-1 then return GetWorldPositionOfEntityBone(vehicle,bone) end
    return GetOffsetFromEntityInWorldCoords(vehicle,-.8,-1.2,.3)
end)

RegisterNetEvent('ps-fuel:client:usePortableContainer',function(itemName,def,metadata,slot)
    local vehicle=PSFuelRuntime and PSFuelRuntime.ClosestVehicle and PSFuelRuntime.ClosestVehicle()
    if not vehicle or vehicle==0 then return notify('Move closer to a vehicle.','error') end
    local held=tonumber(metadata and metadata.fuel) or 0
    local capacity=tonumber(metadata and metadata.capacity) or tonumber(def and def.capacity) or 20
    local heldDisplay, heldUnit=S.FormatVolume(held); local capDisplay=S.FormatVolume(capacity)
    local choice=lib.alertDialog({header=def.label or itemName,content=('Container: %.1f / %.1f %s'):format(heldDisplay,capDisplay,heldUnit),centered=true,cancel=true,labels={confirm=held>0 and 'Pour into vehicle' or 'Fill from vehicle',cancel='Cancel'}})
    if choice~='confirm' then return end
    local direction=held>0 and 'to_vehicle' or 'from_vehicle'
    local maxDisplay=S.FormatVolume(capacity)
    local input=lib.inputDialog('Fuel transfer',{{type='number',label=heldUnit,default=math.min(5,maxDisplay),min=0.1,max=maxDisplay,step=0.5,required=true}})
    if not input then return end
    local response=lib.callback.await('ps-fuel:server:portableTransfer',false,itemName,slot,NetworkGetNetworkIdFromEntity(vehicle),direction,S.ToBaseVolume(tonumber(input[1])),syncedVehicleClass(vehicle))
    if response and response.success then
        PSFuelRuntime.SetFuel(vehicle,response.fuel)
        notify(response.message,'success')
    else notify(response and response.message or 'Fuel transfer failed.','error') end
end)

RegisterCommand('mobilefuel',function(_,args)
    local service=cache.vehicle
    if not service or service==0 then return notify('Sit in the mobile refuelling vehicle first.','error') end
    local target=0; local origin=GetEntityCoords(service); local best=999
    for _,veh in ipairs(GetGamePool('CVehicle')) do
        if veh~=service then local d=#(GetEntityCoords(veh)-origin); if d<best and d<=10 then best=d target=veh end end
    end
    if target==0 then return notify('No target vehicle nearby.','error') end
    local response=lib.callback.await('ps-fuel:server:mobileRefuel',false,NetworkGetNetworkIdFromEntity(service),NetworkGetNetworkIdFromEntity(target),S.ToBaseVolume(tonumber(args[1]) or 10),syncedVehicleClass(target))
    if response and response.success then PSFuelRuntime.SetFuel(target,response.fuel) notify(response.message,'success') else notify(response and response.message or 'Mobile refuel failed.','error') end
end,false)


RegisterNetEvent('ps-fuel:client:createSpill',function(data)
    if type(data)~='table' or type(data.coords)~='table' then return end
    spills[data.id or (#spills+1)]={coords=vec3(data.coords.x,data.coords.y,data.coords.z),severity=tonumber(data.severity) or 1,expires=GetGameTimer()+(tonumber(data.seconds) or 90)*1000,fire=false}
end)

CreateThread(function()
    while true do
        local sleep=1000
        local ped=cache.ped or PlayerPedId()
        local pcoords=GetEntityCoords(ped)
        for id,spill in pairs(spills) do
            if spill.expires<GetGameTimer() then
                if spill.fire and spill.fireId then RemoveScriptFire(spill.fireId) end
                spills[id]=nil
            else
                local d=#(pcoords-spill.coords)
                if d<30 then
                    sleep=0
                    DrawMarker(28,spill.coords.x,spill.coords.y,spill.coords.z+.02,0,0,0,0,0,0,1.8*spill.severity,1.8*spill.severity,.08,180,140,30,75,false,false,2,false,nil,nil,false)
                    if d<1.1 and IsPedOnFoot(ped) and IsPedSprinting(ped) and math.random(100)<8 then SetPedToRagdoll(ped,1200,1200,0,false,false,false) end
                    if not spill.fire and math.random(10000)<=math.floor((tonumber((((PSFuelConfig.Advanced or {}).PumpDamage or {}).FireChancePercent) or 4))*2) then
                        spill.fireId=StartScriptFire(spill.coords.x,spill.coords.y,spill.coords.z,1,false)
                        spill.fire=true
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    local triggered=false
    while true do
        if PSFuelNozzle and PSFuelNozzle.GetVehicle and PSFuelNozzle.GetSourceEntity then
            local vehicle=PSFuelNozzle.GetVehicle()
            local source=PSFuelNozzle.GetSourceEntity()
            if vehicle and source and DoesEntityExist(vehicle) and DoesEntityExist(source) then
                local max=tonumber((PSFuelConfig.Nozzles or {}).MaxDistance) or 7.5
                local distance=#(GetEntityCoords(vehicle)-GetEntityCoords(source))
                if (GetEntitySpeed(vehicle)>2.0 or distance>max+1.0) and not triggered then
                    triggered=true
                    local station=PSFuelNozzle.GetStation and PSFuelNozzle.GetStation()
                    local coords=GetEntityCoords(source)
                    TriggerServerEvent('ps-fuel:server:pumpDamaged',station and station.id or nil,{x=coords.x,y=coords.y,z=coords.z},math.min(3,distance/math.max(1,max)))
                    PSFuelNozzle.Return()
                    notify('The nozzle hose was torn from the pump. Fuel spilled.','error')
                end
            else triggered=false end
        end
        Wait(350)
    end
end)

RegisterNetEvent('ps-fuel:client:installFuelPart',function(session)
    local pcfg=((PSFuelConfig.Advanced or {}).FuelSystemParts or {})
    local ok=lib.skillCheck(pcfg.Skill or {'easy','medium','medium'},{'w','a','s','d'})
    if ok then ok=lib.progressCircle({duration=7500,label=('Installing %s...'):format(session.def and session.def.label or 'fuel-system part'),position='bottom',canCancel=true,disable={move=true,car=true,combat=true}}) end
    TriggerServerEvent('ps-fuel:server:finishFuelPart',session.token,ok==true)
end)

RegisterNetEvent('ps-fuel:client:placePrivateEnergyPoint',function(itemName,def)
    local input=lib.inputDialog(def.label or 'Install energy point',{{type='input',label='Display name',default=def.label or 'Private Energy Point',required=true,min=2,max=60}})
    if not input then return end
    local confirmed=lib.alertDialog({header='Install here?',content='The charger/pump interaction point will be installed at your current position.',centered=true,cancel=true})
    if confirmed~='confirm' then return end
    local response=lib.callback.await('ps-fuel:server:installPrivateEnergyPoint',false,itemName,def,input[1])
    notify(response and response.message or 'Installation failed.',response and response.success and 'success' or 'error')
    if response and response.success then Wait(300); TriggerEvent('ps-fuel:client:refreshPrivatePoints') end
end)

local privateTargets={}
local function clearPrivateTargets()
    if not exports.ox_target then return end
    for _,id in ipairs(privateTargets) do pcall(function() exports.ox_target:removeZone(id) end) end
    privateTargets={}
end

local function loadPrivatePoints()
    if (((PSFuelConfig.Advanced or {}).PrivateEnergy or {}).Enabled)~=true then return end
    local points=lib.callback.await('ps-fuel:server:getPrivatePoints',false) or {}
    clearPrivateTargets()
    for _,point in ipairs(points) do
        local c=point.coords
        if c and c.x and c.y and c.z then
            local id=exports.ox_target:addSphereZone({coords=vec3(c.x,c.y,c.z),radius=1.8,debug=false,options={{name=('ps_fuel_private_%s'):format(point.id),icon=point.pointType:find('charger') and 'fa-solid fa-bolt' or 'fa-solid fa-gas-pump',label=point.label,distance=2.5,onSelect=function()
                local vehicle=PSFuelRuntime and PSFuelRuntime.ClosestVehicle and PSFuelRuntime.ClosestVehicle()
                if not vehicle or vehicle==0 then return notify('Move a vehicle next to the energy point.','error') end
                local electric=point.pointType=='charger' or point.pointType=='home_charger'
                local options={}
                if not electric then
                    for key,data in pairs(PSFuelConfig.FuelTypes or {}) do if type(data)=='table' then options[#options+1]={value=key,label=data.label or key} end end
                end
                local volumeUnit=select(2,S.FormatVolume(1))
                local fields={{type='number',label=electric and 'kWh' or volumeUnit,default=10,min=.1,max=100,step=.5,required=true}}
                if not electric then fields[#fields+1]={type='select',label='Fuel type',options=options,default='petrol',required=true} end
                local input=lib.inputDialog(point.label,fields); if not input then return end
                local response=lib.callback.await('ps-fuel:server:usePrivatePoint',false,point.id,NetworkGetNetworkIdFromEntity(vehicle),electric and tonumber(input[1]) or S.ToBaseVolume(tonumber(input[1])),electric and 'electric' or input[2],'bank',syncedVehicleClass(vehicle))
                if response and response.success then PSFuelRuntime.SetFuel(vehicle,response.fuel) notify(response.message,'success') else notify(response and response.message or 'Energy point failed.','error') end
            end}}})
            privateTargets[#privateTargets+1]=id
        end
    end
end

CreateThread(function() Wait(4000); loadPrivatePoints(); while true do Wait(120000); loadPrivatePoints() end end)
RegisterNetEvent('ps-fuel:client:refreshPrivatePoints',loadPrivatePoints)

RegisterCommand('fuelhistory',function()
    local vehicle=cache.vehicle or (PSFuelRuntime and PSFuelRuntime.ClosestVehicle and PSFuelRuntime.ClosestVehicle())
    if not vehicle or vehicle==0 then return notify('No vehicle found.','error') end
    local p=plate(vehicle)
    local rows=lib.callback.await('ps-fuel:server:getFuelHistory',false,p) or {}
    local options={}
    for _,row in ipairs(rows) do
        options[#options+1]={title=('%s · %.1f units'):format(row.fuel_type or 'fuel',tonumber(row.volume) or 0),description=('%s%d · %s · odometer %0.1f km'):format((((PSFuelConfig.Advanced or {}).Units or {}).CurrencySymbol or '£'),tonumber(row.amount_paid) or 0,row.station_id or 'private',tonumber(row.odometer_km) or 0),icon='receipt'}
    end
    if #options==0 then options[1]={title='No fuel history',description='This vehicle has no recorded refuelling history.',disabled=true} end
    lib.registerContext({id='ps_fuel_history',title=('Fuel history · %s'):format(p),options=options})
    lib.showContext('ps_fuel_history')
end,false)
