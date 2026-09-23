local RESOURCE = GetCurrentResourceName()
local CHECK_COMMAND = 'psfuelversion'

local function cleanVersion(value)
    value = tostring(value or ''):match('^%s*(.-)%s*$') or ''
    value = value:gsub('^[vV]', '')
    return value
end

local function versionParts(value)
    local parts = {}
    for part in cleanVersion(value):gmatch('%d+') do
        parts[#parts + 1] = tonumber(part) or 0
        if #parts >= 4 then break end
    end
    return parts
end

local function compareVersions(current, latest)
    local a = versionParts(current)
    local b = versionParts(latest)
    if #a == 0 or #b == 0 then return 0 end

    local count = math.max(#a, #b)
    for i = 1, count do
        local left = a[i] or 0
        local right = b[i] or 0
        if left < right then return -1 end
        if left > right then return 1 end
    end
    return 0
end

local function installedVersion()
    return cleanVersion(GetResourceMetadata(RESOURCE, 'version', 0) or '0.0.0')
end

local function configuredRepository()
    local fromConvar = GetConvar('ps_fuel_github_repo', '')
    if fromConvar and fromConvar ~= '' then
        return fromConvar:gsub('^https?://github%.com/', ''):gsub('/+$', '')
    end

    local cfg = PSFuelConfig.VersionCheck or {}
    local repository = tostring(cfg.Repository or '')
    return repository:gsub('^https?://github%.com/', ''):gsub('/+$', '')
end

local function log(message)
    print(('^5[ps-fuel]^7 %s'):format(message))
end

local function checkVersion(manual)
    local cfg = PSFuelConfig.VersionCheck or {}
    if cfg.Enabled == false and not manual then return end

    local repository = configuredRepository()
    local current = installedVersion()

    if repository == '' or not repository:match('^[%w%._%-]+/[%w%._%-]+$') then
        log(('v%s loaded. GitHub version check is not configured. Set ps_fuel_github_repo to owner/repository.'):format(current))
        return
    end

    local url = ('https://api.github.com/repos/%s/releases/latest'):format(repository)
    PerformHttpRequest(url, function(statusCode, body)
        statusCode = tonumber(statusCode) or 0
        if statusCode ~= 200 or not body or body == '' then
            log(('v%s loaded. Version check failed (GitHub HTTP %s); continuing normally.'):format(current, statusCode))
            return
        end

        local ok, data = pcall(json.decode, body)
        if not ok or type(data) ~= 'table' then
            log(('v%s loaded. Version check returned invalid GitHub data; continuing normally.'):format(current))
            return
        end

        local latest = cleanVersion(data.tag_name or data.name)
        if latest == '' then
            log(('v%s loaded. Latest GitHub release has no readable version tag.'):format(current))
            return
        end

        local comparison = compareVersions(current, latest)
        if comparison < 0 then
            local releaseUrl = tostring(data.html_url or ('https://github.com/%s/releases/latest'):format(repository))
            print('^3============================================================^7')
            log(('UPDATE AVAILABLE: v%s -> v%s'):format(current, latest))
            log(('Download: %s'):format(releaseUrl))
            print('^3============================================================^7')
        elseif comparison > 0 then
            log(('Development build detected: installed v%s, latest release v%s.'):format(current, latest))
        else
            log(('v%s is up to date.'):format(current))
        end
    end, 'GET', '', {
        ['Accept'] = 'application/vnd.github+json',
        ['User-Agent'] = 'ps-fuel-version-checker',
        ['X-GitHub-Api-Version'] = '2022-11-28',
    })
end

RegisterCommand(CHECK_COMMAND, function(source)
    if source ~= 0 then return end
    checkVersion(true)
end, false)

CreateThread(function()
    local cfg = PSFuelConfig.VersionCheck or {}
    if cfg.Enabled == false then
        log(('v%s loaded. Version checker disabled.'):format(installedVersion()))
        return
    end

    if cfg.CheckOnStart ~= false then
        Wait(2500)
        checkVersion(false)
    end

    local hours = tonumber(cfg.CheckIntervalHours) or 6
    if hours <= 0 then return end
    local interval = math.max(1, hours) * 60 * 60 * 1000

    while true do
        Wait(interval)
        checkVersion(false)
    end
end)
