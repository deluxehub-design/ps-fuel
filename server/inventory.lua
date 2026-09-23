PSFuelInventory = PSFuelInventory or {}

local function oxInventoryAvailable()
    return GetResourceState('ox_inventory') == 'started'
end

local function frameworkPlayer(source, player)
    if player then return player end
    return PSFuelFramework and PSFuelFramework.GetPlayer and PSFuelFramework.GetPlayer(source)
end

function PSFuelInventory.AddItem(source, player, item, count, metadata)
    if oxInventoryAvailable() then
        if not exports.ox_inventory:CanCarryItem(source, item, count, metadata) then
            return false, 'inventory_full'
        end
        return exports.ox_inventory:AddItem(source, item, count, metadata)
    end

    player = frameworkPlayer(source, player)
    local raw = player and player.raw

    -- Qbox/QBCore compatible inventory API.
    if player and player.Functions and player.Functions.AddItem then
        local result = player.Functions.AddItem(item, count, false, metadata)
        return result ~= false, result == false and 'inventory_full' or nil
    end

    -- ESX inventory API.
    if raw and raw.addInventoryItem then
        raw.addInventoryItem(item, count)
        return true
    end

    return false, 'inventory_unavailable'
end

function PSFuelInventory.ConsumeOne(source, player, item)
    if oxInventoryAvailable() then
        local slots = exports.ox_inventory:Search(source, 'slots', item)
        local selected
        for _, slot in pairs(type(slots) == 'table' and slots or {}) do
            if not selected or tonumber(slot.slot) < tonumber(selected.slot) then selected = slot end
        end
        if not selected then return false, nil, 'item_missing' end

        local removed, reason = exports.ox_inventory:RemoveItem(
            source,
            item,
            1,
            selected.metadata,
            selected.slot,
            false,
            true
        )
        return removed == true, selected.metadata or {}, reason
    end

    player = frameworkPlayer(source, player)
    local raw = player and player.raw

    if player and player.Functions and player.Functions.GetItemByName then
        local found = player.Functions.GetItemByName(item)
            or player.Functions.GetItemByName(item:upper())
        if not found then return false, nil, 'item_missing' end

        local removed = player.Functions.RemoveItem(found.name, 1, found.slot)
        return removed ~= false, found.info or found.metadata or {}, removed == false and 'remove_failed' or nil
    end

    if raw and raw.getInventoryItem and raw.removeInventoryItem then
        local found = raw.getInventoryItem(item)
        if not found or tonumber(found.count) <= 0 then return false, nil, 'item_missing' end
        raw.removeInventoryItem(item, 1)
        return true, found.metadata or found.info or {}, nil
    end

    return false, nil, 'inventory_unavailable'
end
