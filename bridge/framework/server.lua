PSFuelFramework = PSFuelFramework or {}

local frameworkName = nil
local qbCore = nil
local esx = nil
local customAdapter = nil

local function configuredFramework()
    local cfg = PSFuelConfig.Framework or {}
    local value = tostring(cfg.Name or cfg.name or cfg.Mode or 'auto'):lower()
    if value == 'qb' then value = 'qbcore' end
    if value == 'qbx' then value = 'qbox' end
    if value == 'vmenu' then value = 'standalone' end
    return value
end

local function resourceStarted(name)
    return type(name) == 'string' and name ~= '' and GetResourceState(name) == 'started'
end

local function detectFramework()
    local configured = configuredFramework()
    if configured ~= 'auto' then return configured end

    if resourceStarted('qbx_core') then return 'qbox' end
    if resourceStarted('qb-core') then return 'qbcore' end
    if resourceStarted('es_extended') then return 'esx' end
    return 'standalone'
end

local function getESX()
    if esx then return esx end
    if resourceStarted('es_extended') then
        local ok, object = pcall(function()
            return exports['es_extended']:getSharedObject()
        end)
        if ok and object then esx = object return esx end
    end
    return nil
end

local function getQB()
    if qbCore then return qbCore end
    if resourceStarted('qb-core') then
        local ok, object = pcall(function()
            return exports['qb-core']:GetCoreObject()
        end)
        if ok and object then qbCore = object return qbCore end
    end
    return nil
end

local function identifierForSource(src)
    local preferred = (PSFuelConfig.Framework or {}).IdentifierType or 'license'
    local identifier = GetPlayerIdentifierByType(src, preferred)
    if identifier and identifier ~= '' then return identifier end

    local identifiers = GetPlayerIdentifiers(src)
    return identifiers and identifiers[1] or ('source:%s'):format(src)
end

local function normalisedJob(job)
    job = type(job) == 'table' and job or {}
    local grade = job.grade
    local gradeLevel = 0
    if type(grade) == 'table' then
        gradeLevel = tonumber(grade.level or grade.grade) or 0
    else
        gradeLevel = tonumber(grade) or 0
    end
    return {
        name = tostring(job.name or ''),
        label = tostring(job.label or job.name or ''),
        onduty = job.onduty == true or job.onDuty == true,
        grade = { level = gradeLevel, name = tostring(type(grade) == 'table' and (grade.name or '') or '') },
    }
end

local function normalisedName(data, fallback)
    data = type(data) == 'table' and data or {}
    local charinfo = data.charinfo or {}
    local first = tostring(charinfo.firstname or data.firstname or '')
    local last = tostring(charinfo.lastname or data.lastname or '')
    local full = (first .. ' ' .. last):gsub('^%s*(.-)%s*$', '%1')
    return full ~= '' and full or tostring(data.name or fallback or 'Unknown')
end

local function wrapPlayer(src, raw, kind)
    if not raw then return nil end

    local pd = raw.PlayerData or {}
    local citizenid = pd.citizenid or pd.cid or raw.identifier
    local job = pd.job
    local name = normalisedName(pd, raw.name or raw.getName and raw:getName())

    if kind == 'esx' then
        citizenid = raw.identifier or citizenid
        local esxJob = raw.job or {}
        job = {
            name = esxJob.name,
            label = esxJob.label,
            onduty = esxJob.onDuty ~= false,
            grade = { level = tonumber(esxJob.grade) or 0, name = esxJob.grade_name or '' },
        }
        name = raw.getName and raw:getName() or name
    end

    return {
        source = src,
        framework = kind,
        raw = raw,
        Functions = raw.Functions,
        PlayerData = {
            source = src,
            citizenid = citizenid,
            name = name,
            charinfo = pd.charinfo or {},
            job = normalisedJob(job),
            money = pd.money or {},
        },
    }
end

local function standalonePlayer(src)
    local identifier = identifierForSource(src)
    local balance = PSFuelDatabase and PSFuelDatabase.GetWalletBalances and PSFuelDatabase.GetWalletBalances(identifier) or {}
    local starting = (PSFuelConfig.Framework or {}).Standalone or {}
    local cash = tonumber(balance.cash)
    local bank = tonumber(balance.bank)
    if cash == nil then cash = tonumber(starting.StartingCash) or 50000 end
    if bank == nil then bank = tonumber(starting.StartingBank) or 100000 end

    return {
        source = src,
        framework = 'standalone',
        raw = nil,
        PlayerData = {
            source = src,
            citizenid = identifier,
            name = GetPlayerName(src) or ('Player %s'):format(src),
            charinfo = {},
            job = { name = '', label = '', onduty = false, grade = { level = 0, name = '' } },
            money = { cash = cash, bank = bank },
        },
    }
end

function PSFuelFramework.Detect()
    if frameworkName then return frameworkName end
    frameworkName = detectFramework()

    if frameworkName == 'qbox' and not resourceStarted('qbx_core') then
        frameworkName = 'standalone'
    elseif frameworkName == 'qbcore' and not resourceStarted('qb-core') then
        frameworkName = 'standalone'
    elseif frameworkName == 'esx' and not resourceStarted('es_extended') then
        frameworkName = 'standalone'
    end

    print(('[ps-fuel] Framework adapter: %s'):format(frameworkName))
    return frameworkName
end

function PSFuelFramework.SetCustomAdapter(adapter)
    if type(adapter) ~= 'table' then return false end
    customAdapter = adapter
    frameworkName = 'custom'
    return true
end

exports('SetFrameworkAdapter', function(adapter)
    return PSFuelFramework.SetCustomAdapter(adapter)
end)

exports('GetFramework', function()
    return PSFuelFramework.GetName()
end)

function PSFuelFramework.GetName()
    return PSFuelFramework.Detect()
end

function PSFuelFramework.GetPlayer(src)
    local kind = PSFuelFramework.Detect()
    if kind == 'qbox' then
        local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        return ok and wrapPlayer(src, player, 'qbox') or nil
    elseif kind == 'qbcore' then
        local core = getQB()
        local player = core and core.Functions and core.Functions.GetPlayer(src)
        return wrapPlayer(src, player, 'qbcore')
    elseif kind == 'esx' then
        local core = getESX()
        local player = core and core.GetPlayerFromId(src)
        return wrapPlayer(src, player, 'esx')
    elseif kind == 'custom' and customAdapter and customAdapter.GetPlayer then
        local player = customAdapter.GetPlayer(src)
        return wrapPlayer(src, player, 'custom')
    end
    return standalonePlayer(src)
end

function PSFuelFramework.GetIdentifier(playerOrSource)
    local player = type(playerOrSource) == 'table' and playerOrSource or PSFuelFramework.GetPlayer(playerOrSource)
    return player and player.PlayerData and player.PlayerData.citizenid or nil
end

function PSFuelFramework.GetJob(player)
    return player and player.PlayerData and player.PlayerData.job or { name = '', label = '', onduty = false, grade = { level = 0 } }
end

function PSFuelFramework.GetNameForPlayer(player)
    return player and player.PlayerData and player.PlayerData.name or 'Unknown'
end

function PSFuelFramework.GetMoney(player, account)
    if not player then return 0 end
    account = tostring(account or 'bank'):lower()
    local kind = player.framework or PSFuelFramework.Detect()

    if kind == 'qbox' then
        local identifier = PSFuelFramework.GetIdentifier(player)
        local ok, value = pcall(function() return exports.qbx_core:GetMoney(identifier, account) end)
        if ok and value ~= false then return tonumber(value) or 0 end
        return tonumber(player.PlayerData.money and player.PlayerData.money[account]) or 0
    elseif kind == 'qbcore' then
        local raw = player.raw
        if raw and raw.Functions and raw.Functions.GetMoney then
            return tonumber(raw.Functions.GetMoney(account)) or 0
        end
    elseif kind == 'esx' then
        local raw = player.raw
        if raw then
            if account == 'cash' and raw.getMoney then return tonumber(raw.getMoney()) or 0 end
            if raw.getAccount then
                local accountData = raw.getAccount(account)
                return tonumber(accountData and accountData.money) or 0
            end
        end
    elseif kind == 'custom' and customAdapter and customAdapter.GetMoney then
        return tonumber(customAdapter.GetMoney(player.raw, account)) or 0
    elseif kind == 'standalone' then
        local id = PSFuelFramework.GetIdentifier(player)
        if PSFuelDatabase and PSFuelDatabase.GetWalletBalance then
            return tonumber(PSFuelDatabase.GetWalletBalance(id, account)) or 0
        end
    end

    return tonumber(player.PlayerData.money and player.PlayerData.money[account]) or 0
end

function PSFuelFramework.RemoveMoney(player, account, amount, reason)
    if not player then return false end
    account = tostring(account or 'bank'):lower()
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return true end
    if PSFuelFramework.GetMoney(player, account) < amount then return false end
    local kind = player.framework or PSFuelFramework.Detect()

    if kind == 'qbox' then
        local identifier = PSFuelFramework.GetIdentifier(player)
        local ok, result = pcall(function() return exports.qbx_core:RemoveMoney(identifier, account, amount, reason) end)
        return ok and (result == true or result == nil)
    elseif kind == 'qbcore' then
        local raw = player.raw
        if raw and raw.Functions and raw.Functions.RemoveMoney then
            return raw.Functions.RemoveMoney(account, amount, reason) ~= false
        end
    elseif kind == 'esx' then
        local raw = player.raw
        if raw then
            if account == 'cash' and raw.removeMoney then raw.removeMoney(amount, reason) return true end
            if raw.removeAccountMoney then raw.removeAccountMoney(account, amount, reason) return true end
        end
    elseif kind == 'custom' and customAdapter and customAdapter.RemoveMoney then
        return customAdapter.RemoveMoney(player.raw, account, amount, reason) ~= false
    elseif kind == 'standalone' then
        return PSFuelDatabase and PSFuelDatabase.RemoveWalletMoney and PSFuelDatabase.RemoveWalletMoney(PSFuelFramework.GetIdentifier(player), account, amount) == true
    end
    return false
end

function PSFuelFramework.AddMoney(player, account, amount, reason)
    if not player then return false end
    account = tostring(account or 'bank'):lower()
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount <= 0 then return true end
    local kind = player.framework or PSFuelFramework.Detect()

    if kind == 'qbox' then
        local identifier = PSFuelFramework.GetIdentifier(player)
        local ok, result = pcall(function() return exports.qbx_core:AddMoney(identifier, account, amount, reason) end)
        return ok and (result == true or result == nil)
    elseif kind == 'qbcore' then
        local raw = player.raw
        if raw and raw.Functions and raw.Functions.AddMoney then
            return raw.Functions.AddMoney(account, amount, reason) ~= false
        end
    elseif kind == 'esx' then
        local raw = player.raw
        if raw then
            if account == 'cash' and raw.addMoney then raw.addMoney(amount, reason) return true end
            if raw.addAccountMoney then raw.addAccountMoney(account, amount, reason) return true end
        end
    elseif kind == 'custom' and customAdapter and customAdapter.AddMoney then
        return customAdapter.AddMoney(player.raw, account, amount, reason) ~= false
    elseif kind == 'standalone' then
        return PSFuelDatabase and PSFuelDatabase.AddWalletMoney and PSFuelDatabase.AddWalletMoney(PSFuelFramework.GetIdentifier(player), account, amount) == true
    end
    return false
end

function PSFuelFramework.GetDutyCount(jobType)
    jobType = tostring(jobType or 'leo'):lower()
    local kind = PSFuelFramework.Detect()

    if kind == 'qbox' then
        local ok, count = pcall(function() return exports.qbx_core:GetDutyCountType(jobType) end)
        if ok then return tonumber(count) or 0 end
    end

    local configured = (PSFuelConfig.Framework or {}).DutyJobs or {}
    local names = configured[jobType]
    if type(names) ~= 'table' or #names == 0 then names = { jobType } end
    local allowed = {}
    for _, name in ipairs(names) do allowed[tostring(name):lower()] = true end

    if kind == 'qbcore' then
        local core = getQB()
        if core and core.Functions and core.Functions.GetPlayers then
            local count = 0
            for _, id in pairs(core.Functions.GetPlayers()) do
                local player = core.Functions.GetPlayer(id)
                local job = player and player.PlayerData and player.PlayerData.job or {}
                if allowed[tostring(job.name or ''):lower()] and job.onduty ~= false then
                    count = count + 1
                end
            end
            return count
        end
    elseif kind == 'esx' then
        local core = getESX()
        if core and core.GetExtendedPlayers then
            local count = 0
            for _, player in pairs(core.GetExtendedPlayers()) do
                local job = player.getJob and player.getJob() or player.job or {}
                if allowed[tostring(job.name or ''):lower()] then count = count + 1 end
            end
            return count
        end
    elseif kind == 'custom' and customAdapter and customAdapter.GetDutyCount then
        return tonumber(customAdapter.GetDutyCount(jobType)) or 0
    end
    return 0
end

function PSFuelFramework.RegisterUsableItem(item, handler)
    if type(item) ~= 'string' or item == '' or type(handler) ~= 'function' then return false end
    local kind = PSFuelFramework.Detect()
    if kind == 'qbox' then
        local ok = pcall(function()
            exports.qbx_core:CreateUseableItem(item, handler)
        end)
        return ok
    elseif kind == 'qbcore' then
        local core = getQB()
        if core and core.Functions and core.Functions.CreateUseableItem then
            core.Functions.CreateUseableItem(item, handler)
            return true
        end
    elseif kind == 'esx' then
        local core = getESX()
        if core and core.RegisterUsableItem then
            core.RegisterUsableItem(item, handler)
            return true
        end
    elseif kind == 'custom' and customAdapter and customAdapter.RegisterUsableItem then
        return customAdapter.RegisterUsableItem(item, handler) ~= false
    end
    return false
end

function PSFuelFramework.IsStandalone()
    local kind = PSFuelFramework.Detect()
    return kind == 'standalone'
end

CreateThread(function()
    Wait(0)
    PSFuelFramework.Detect()
end)
