-- PS Fuel 3.6.0 - runtime stations/chargers, fuel recovery and GTA AI delivery visuals.
local runtimePumpObjects = {}
local function notify(message,kind)
    if PSFuelRuntime and PSFuelRuntime.Notify then return PSFuelRuntime.Notify(message,kind) end
    lib.notify({title='PS Fuel',description=message,type=kind or 'inform'})
end

local function hasStation(id)
    for _,s in ipairs(PSFuelConfig.Stations or {}) do if s.id==id then return true end end
    return false
end

local function addRuntimeStation(row)
    local id=tostring(row.id or row.station_id or '')
    if id=='' or hasStation(id) then return end
    local x,y,z=tonumber(row.x),tonumber(row.y),tonumber(row.z)
    if not x or not y or not z then return end
    local heading=tonumber(row.heading) or 0.0
    local pumpModel=tostring(row.pumpModel or row.pump_model or 'prop_gas_pump_1a')
    PSFuelConfig.Stations[#PSFuelConfig.Stations+1]={
        id=id,label=tostring(row.label or 'Custom Fuel Station'),coords=vec3(x,y,z),
        priceMultiplier=1.0,purchasePrice=tonumber(row.purchasePrice or row.purchase_price) or 200000,
        capacity=tonumber(row.capacity) or 15000.0,ownershipEnabled=true,interactionDistance=34.0,
        deliveryEnabled=true,custom=true,heading=heading,pumpModel=pumpModel,
        delivery={coords=vec3(x,y,z),heading=heading,length=26.0,width=9.0,requireDirection=false}
    }
    local hash=joaat(pumpModel)
    RequestModel(hash)
    local deadline=GetGameTimer()+8000
    while not HasModelLoaded(hash) and GetGameTimer()<deadline do Wait(20) end
    if HasModelLoaded(hash) then
        local object=CreateObjectNoOffset(hash,x,y,z,false,false,false)
        if object and object~=0 then
            SetEntityHeading(object,heading)
            FreezeEntityPosition(object,true)
            SetEntityInvincible(object,true)
            SetEntityAsMissionEntity(object,true,true)
            runtimePumpObjects[#runtimePumpObjects+1]=object
        end
        SetModelAsNoLongerNeeded(hash)
    end
end

local function addRuntimeCharger(row)
    local id=tostring(row.id or row.charger_id or '')
    if id=='' then return end
    local x,y,z=tonumber(row.x),tonumber(row.y),tonumber(row.z)
    if not x or not y or not z then return end
    local charger={id=id,stationId=tostring(row.stationId or row.station_id or ''),label=tostring(row.label or 'Private EV Charger'),coords=vec4(x,y,z,tonumber(row.heading) or 0.0),fastCharge=row.fastCharge==true or tonumber(row.fast_charge)==1,custom=true}
    if PSFuelNozzle and PSFuelNozzle.AddRuntimeCharger then PSFuelNozzle.AddRuntimeCharger(charger) end
end

CreateThread(function()
    Wait(1200)
    local network=lib.callback.await('ps-fuel:server:getRuntimeNetwork',false)
    if type(network)=='table' then
        for _,row in ipairs(network.stations or {}) do addRuntimeStation(row) end
        for _,row in ipairs(network.chargers or {}) do addRuntimeCharger(row) end
    end
end)

RegisterNetEvent('ps-fuel:client:runtimeStationAdded',function(row) addRuntimeStation(row) end)
RegisterNetEvent('ps-fuel:client:runtimeChargerAdded',function(row) addRuntimeCharger(row) end)

RegisterNUICallback('adminCreateStation',function(data,cb)
    local ped=cache.ped or PlayerPedId(); local c=GetEntityCoords(ped)
    local response=lib.callback.await('ps-fuel:server:adminCreateStation',false,{
        label=data.label,purchasePrice=tonumber(data.purchasePrice),capacity=tonumber(data.capacity),
        heading=GetEntityHeading(ped),coords={x=c.x,y=c.y,z=c.z}
    })
    cb(response or {success=false,message='Station creation failed.'})
end)

RegisterNUICallback('adminCreateCharger',function(data,cb)
    local ped=cache.ped or PlayerPedId(); local c=GetEntityCoords(ped)
    local response=lib.callback.await('ps-fuel:server:adminCreateCharger',false,{
        stationId=data.stationId,label=data.label,fastCharge=data.fastCharge~=false,
        heading=GetEntityHeading(ped),coords={x=c.x,y=c.y,z=c.z}
    })
    cb(response or {success=false,message='Charger creation failed.'})
end)

RegisterNetEvent('ps-fuel:client:authoritativeFuelSet',function(netId,value)
    local vehicle=NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if vehicle~=0 and DoesEntityExist(vehicle) and PSFuelRuntime and PSFuelRuntime.SetFuel then
        PSFuelRuntime.SetFuel(vehicle,tonumber(value) or 0.0)
    end
end)

CreateThread(function()
    Wait(900)
    local cfg=PSFuelConfig.FuelRecovery or {}
    if cfg.Enabled~=true or cfg.UseOxTarget==false then return end
    exports.ox_target:addGlobalVehicle({
        {
            name='ps-fuel:siphon-vehicle',icon='fa-solid fa-oil-can',label='Drain / siphon fuel',
            distance=tonumber(cfg.TargetDistance) or 2.5,
            canInteract=function(entity)
                return DoesEntityExist(entity) and not IsPedInAnyVehicle(cache.ped or PlayerPedId(),false)
            end,
            onSelect=function(data)
                local entity=data.entity
                local netId=NetworkGetNetworkIdFromEntity(entity)
                if netId==0 then NetworkRegisterEntityAsNetworked(entity); netId=NetworkGetNetworkIdFromEntity(entity) end
                local begin=lib.callback.await('ps-fuel:server:beginSiphon',false,netId)
                if not begin or not begin.success then return notify(begin and begin.message or 'Unable to begin fuel recovery.','error') end
                local note=(tonumber(begin.contamination) or 0)>0 and ' Wrong-fuel contamination detected.' or ''
                notify(('Fuel recovery started. %.1f%% is in the tank.%s'):format(tonumber(begin.fuel) or 0,note),'inform')
                local completed=lib.progressCircle({duration=tonumber(cfg.ProgressMs) or 8500,label='Draining fuel tank...',position='bottom',canCancel=true,disable={move=true,car=true,combat=true},anim={dict='timetable@gardener@filling_can',clip='gar_ig_5_filling_can'}})
                if not completed then return notify('Fuel recovery cancelled.','warning') end
                local finish=lib.callback.await('ps-fuel:server:completeSiphon',false,begin.token)
                notify(finish and finish.message or 'Fuel recovery failed.',finish and finish.success and 'success' or 'error')
            end
        }
    })
end)

local function loadModel(model)
    local hash=type(model)=='number' and model or joaat(model)
    RequestModel(hash); local untilTime=GetGameTimer()+10000
    while not HasModelLoaded(hash) and GetGameTimer()<untilTime do Wait(20) end
    return HasModelLoaded(hash) and hash or nil
end

RegisterNetEvent('ps-fuel:client:npcDeliveryVisual',function(data)
    local cfg=PSFuelConfig.NpcStationDeliveries or {}
    if cfg.Enabled~=true or type(data)~='table' or type(data.coords)~='table' then return end
    CreateThread(function()
        local target=vec3(tonumber(data.coords.x) or 0,tonumber(data.coords.y) or 0,tonumber(data.coords.z) or 0)
        local angle=math.rad(math.random(0,359)); local dist=tonumber(cfg.VisualSpawnDistance) or 150.0
        local spawn=target+vec3(math.cos(angle)*dist,math.sin(angle)*dist,5.0)
        local truckHash=loadModel(data.truckModel or 'phantom'); local trailerHash=loadModel(data.trailerModel or 'tanker'); local pedHash=loadModel(data.driverModel or 's_m_m_trucker_01')
        if not truckHash or not trailerHash or not pedHash then return end
        local ok,z=GetGroundZFor_3dCoord(spawn.x,spawn.y,spawn.z+100.0,false); if ok then spawn=vec3(spawn.x,spawn.y,z+0.5) end
        local heading=GetHeadingFromVector_2d(target.x-spawn.x,target.y-spawn.y)
        local truck=CreateVehicle(truckHash,spawn.x,spawn.y,spawn.z,heading,true,false)
        local trailer=CreateVehicle(trailerHash,spawn.x-5.0,spawn.y-5.0,spawn.z,heading,true,false)
        local driver=CreatePedInsideVehicle(truck,26,pedHash,-1,true,false)
        if truck==0 or driver==0 then return end
        SetEntityAsMissionEntity(truck,true,true); SetEntityAsMissionEntity(trailer,true,true); SetEntityAsMissionEntity(driver,true,true)
        SetBlockingOfNonTemporaryEvents(driver,true); SetPedKeepTask(driver,true)
        AttachVehicleToTrailer(truck,trailer,10.0)
        TaskVehicleDriveToCoordLongrange(driver,truck,target.x,target.y,target.z,18.0,786603,8.0)
        local arrivalDeadline=GetGameTimer()+90000
        while GetGameTimer()<arrivalDeadline and DoesEntityExist(truck) and #(GetEntityCoords(truck)-target)>18.0 do Wait(500) end
        if DoesEntityExist(truck) then
            TaskVehicleTempAction(driver,truck,27,math.max(8000,(tonumber(data.unloadSeconds) or 50)*1000))
            Wait(math.max(8000,(tonumber(data.unloadSeconds) or 50)*1000))
            local away=target+vec3(math.cos(angle+3.14)*300.0,math.sin(angle+3.14)*300.0,0.0)
            TaskVehicleDriveToCoordLongrange(driver,truck,away.x,away.y,away.z,22.0,786603,10.0)
            local leaveDeadline=GetGameTimer()+90000
            while GetGameTimer()<leaveDeadline and DoesEntityExist(truck) and #(GetEntityCoords(truck)-target)<(tonumber(cfg.VisualDespawnDistance) or 220.0) do Wait(1000) end
        end
        if DoesEntityExist(driver) then DeleteEntity(driver) end
        if DoesEntityExist(trailer) then DeleteEntity(trailer) end
        if DoesEntityExist(truck) then DeleteEntity(truck) end
        SetModelAsNoLongerNeeded(truckHash);SetModelAsNoLongerNeeded(trailerHash);SetModelAsNoLongerNeeded(pedHash)
    end)
end)


AddEventHandler('onResourceStop',function(resource)
    if resource~=GetCurrentResourceName() then return end
    for _,entity in ipairs(runtimePumpObjects) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
end)
