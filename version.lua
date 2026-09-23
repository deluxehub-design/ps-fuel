local resourceName = GetCurrentResourceName()
local currentVersion = GetResourceMetadata(resourceName, 'version', 0) or '0.0.0'
local function normalizeRepository(value)
    value = tostring(value or ''):match('^%s*(.-)%s*$') or ''
    value = value:gsub('^https?://github%.com/', '')
    value = value:gsub('%.git$', '')
    value = value:gsub('/$', '')
    return value
end

local defaultRepository = 'deluxehub-evolvenetwork/ps-fuel'
local repository = normalizeRepository(GetConvar('ps_fuel_github_repo', defaultRepository))
local checkInterval = math.max(1, tonumber(GetConvar('ps_fuel_version_check_hours', '6')) or 6)

local function cleanVersion(value)
    value = tostring(value or '')
    local major, minor, patch = value:match('(%d+)%.(%d+)%.(%d+)')
    if major then
        return ('%s.%s.%s'):format(major, minor, patch)
    end
    return '0.0.0'
end

local function versionParts(value)
    local parts = {}
    for part in cleanVersion(value):gmatch('%d+') do
        parts[#parts + 1] = tonumber(part) or 0
    end
    return parts
end

local function isNewerVersion(remoteVersion, localVersion)
    local remote = versionParts(remoteVersion)
    local installed = versionParts(localVersion)
    local count = math.max(#remote, #installed)

    for index = 1, count do
        local remotePart = remote[index] or 0
        local installedPart = installed[index] or 0
        if remotePart ~= installedPart then
            return remotePart > installedPart
        end
    end

    return false
end

local function checkVersion(manual)
    if repository == '' then
        if manual then
            print(('[ps-fuel] Version %s installed. No GitHub repository is configured for update checks.'):format(currentVersion))
        end
        return
    end

    local url = ('https://api.github.com/repos/%s/releases/latest'):format(repository)
    PerformHttpRequest(url, function(statusCode, body)
        if statusCode ~= 200 or not body or body == '' then
            if manual then
                print(('[ps-fuel] Version check failed with HTTP %s.'):format(statusCode or 0))
            end
            return
        end

        local ok, release = pcall(json.decode, body)
        if not ok or type(release) ~= 'table' then
            if manual then
                print('[ps-fuel] Version check failed because GitHub returned invalid data.')
            end
            return
        end

        local latestVersion = cleanVersion(release.tag_name or release.name)
        if latestVersion == '' or latestVersion == '0.0.0' then
            if manual then
                print('[ps-fuel] Version check completed but no valid release version was returned.')
            end
            return
        end

        if isNewerVersion(latestVersion, currentVersion) then
            print(('[ps-fuel] Update available: v%s -> v%s'):format(cleanVersion(currentVersion), latestVersion))
            if release.html_url then
                print(('[ps-fuel] %s'):format(release.html_url))
            end
        elseif manual then
            print(('[ps-fuel] v%s is up to date.'):format(cleanVersion(currentVersion)))
        end
    end, 'GET', '', {
        ['Accept'] = 'application/vnd.github+json',
        ['User-Agent'] = 'ps-fuel-version-checker'
    })
end

RegisterCommand('psfuelversion', function(source)
    if source ~= 0 then return end
    checkVersion(true)
end, true)

CreateThread(function()
    Wait(2500)
    checkVersion(false)

    while repository ~= '' do
        Wait(checkInterval * 60 * 60 * 1000)
        checkVersion(false)
    end
end)
