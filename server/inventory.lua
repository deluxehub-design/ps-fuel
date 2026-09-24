PSFuelInventory = PSFuelInventory or {}

local function tgiannInventoryAvailable()
    return GetResourceState('tgiann-inventory') == 'started'
end

local function oxInventoryAvailable()
    return GetResourceState('ox_inventory') == 'started'
end

local function tgiannCall(name, ...)
    if not tgiannInventoryAvailable() then return false, nil end
    local args = { ... }
    local ok, result = pcall(function()
        return exports['tgiann-inventory'][name](exports['tgiann-inventory'], table.unpack(args))
    end)
    if not ok then
        ok, result = pcall(function()
            return exports['tgiann-inventory'][name](table.unpack(args))
        end)
    end
    return ok, result
end

local function frameworkPlayer(source, player)
    if player then return player end
    return PSFuelFramework and PSFuelFramework.GetPlayer and PSFuelFramework.GetPlayer(source)
end

function PSFuelInventory.AddItem(source, player, item, count, metadata)
    if tgiannInventoryAvailable() then
        local canOk, canCarry = tgiannCall('CanCarryItem', source, item, count, metadata)
        if canOk and canCarry == false then return false, 'inventory_full' end
        local ok, result = tgiannCall('AddItem', source, item, count, false, metadata)
        if not ok then ok, result = tgiannCall('AddItem', source, item, count, nil, metadata) end
        if ok then return result ~= false, result == false and 'inventory_full' or nil end
    end

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
    if tgiannInventoryAvailable() then
        local ok, slots = tgiannCall('Search', source, 'slots', item)
        if not ok then ok, slots = tgiannCall('GetItemByName', source, item) end
        local selected
        if type(slots) == 'table' then
            if slots.name or slots.item then selected = slots else
                for _, slot in pairs(slots) do
                    if type(slot) == 'table' and (not selected or (tonumber(slot.slot) or 9999) < (tonumber(selected.slot) or 9999)) then selected = slot end
                end
            end
        end
        if not selected then return false, nil, 'item_missing' end
        local metadata = selected.metadata or selected.info or {}
        local slot = selected.slot
        local removedOk, removed = tgiannCall('RemoveItem', source, item, 1, slot, metadata)
        if not removedOk then removedOk, removed = tgiannCall('RemoveItem', source, item, 1, metadata, slot) end
        return removedOk and removed ~= false, metadata, removedOk and nil or 'remove_failed'
    end

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


function PSFuelInventory.GetCount(source, item)
    if tgiannInventoryAvailable() then
        local ok, count = tgiannCall('GetItemCount', source, item)
        if not ok then ok, count = tgiannCall('Search', source, 'count', item) end
        if ok then return tonumber(count) or 0 end
    end
    if oxInventoryAvailable() then
        return tonumber(exports.ox_inventory:Search(source, 'count', item)) or 0
    end
    local player = frameworkPlayer(source)
    if player and player.Functions and player.Functions.GetItemByName then
        local found = player.Functions.GetItemByName(item)
        return found and tonumber(found.amount or found.count) or 0
    end
    local raw = player and player.raw
    if raw and raw.getInventoryItem then
        local found = raw.getInventoryItem(item)
        return found and tonumber(found.count) or 0
    end
    return 0
end

function PSFuelInventory.FindItem(source, item)
    if tgiannInventoryAvailable() then
        local ok, slots = tgiannCall('Search', source, 'slots', item)
        if ok and type(slots) == 'table' then
            if slots.name or slots.item then return slots end
            for _, slot in pairs(slots) do if type(slot) == 'table' then return slot end end
        end
    end
    if oxInventoryAvailable() then
        local slots = exports.ox_inventory:Search(source, 'slots', item)
        if type(slots) == 'table' then for _, slot in pairs(slots) do return slot end end
    end
    local player = frameworkPlayer(source)
    if player and player.Functions and player.Functions.GetItemByName then return player.Functions.GetItemByName(item) end
    return nil
end

function PSFuelInventory.RemoveItem(source, player, item, count, metadata, slot)
    count = math.max(1, math.floor(tonumber(count) or 1))
    if tgiannInventoryAvailable() then
        local ok, result = tgiannCall('RemoveItem', source, item, count, slot, metadata)
        if not ok then ok, result = tgiannCall('RemoveItem', source, item, count, metadata, slot) end
        if ok then return result ~= false end
    end
    if oxInventoryAvailable() then return exports.ox_inventory:RemoveItem(source, item, count, metadata, slot) == true end
    player = frameworkPlayer(source, player)
    if player and player.Functions and player.Functions.RemoveItem then return player.Functions.RemoveItem(item, count, slot) ~= false end
    local raw = player and player.raw
    if raw and raw.removeInventoryItem then raw.removeInventoryItem(item, count) return true end
    return false
end
