PSFuelFrameworkClient = PSFuelFrameworkClient or {}

local function frameworkName()
    local cfg = PSFuelConfig.Framework or {}
    local value = tostring(cfg.Name or cfg.name or cfg.Mode or 'auto'):lower()
    if value == 'qb' then value = 'qbcore' end
    if value == 'qbx' then value = 'qbox' end
    if value == 'vmenu' then value = 'standalone' end
    if value ~= 'auto' then return value end
    if GetResourceState('qbx_core') == 'started' then return 'qbox' end
    if GetResourceState('qb-core') == 'started' then return 'qbcore' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

PSFuelFrameworkClient.Name = frameworkName

-- These events are intentionally framework-agnostic. The fuel UI only needs
-- to close/reset when a character changes; no framework API is required here.
RegisterNetEvent('ps-fuel:client:frameworkReset', function()
    if PSFuelRuntime and PSFuelRuntime.Reset then
        PSFuelRuntime.Reset()
    end
end)

RegisterNetEvent('qbx_core:client:playerLoggedOut', function()
    TriggerEvent('ps-fuel:client:frameworkReset')
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    TriggerEvent('ps-fuel:client:frameworkReset')
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerEvent('ps-fuel:client:frameworkReset')
end)

RegisterNetEvent('esx:onPlayerLogout', function()
    TriggerEvent('ps-fuel:client:frameworkReset')
end)

RegisterNetEvent('esx:playerLoaded', function()
    TriggerEvent('ps-fuel:client:frameworkReset')
end)
