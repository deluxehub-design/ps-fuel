local resourceName = GetCurrentResourceName()
local repository = GetConvar('ps_fuel_github_repo', 'deluxehub-evolvenetwork/ps-fuel')
local installed = GetResourceMetadata(resourceName, 'version', 0) or '0.0.0'

local function parts(value)
    value = tostring(value or ''):gsub('^v','')
    local a,b,c = value:match('^(%d+)%.(%d+)%.(%d+)')
    return tonumber(a) or 0, tonumber(b) or 0, tonumber(c) or 0
end

local function newer(remote, localVersion)
    local ra,rb,rc=parts(remote); local la,lb,lc=parts(localVersion)
    if ra~=la then return ra>la end
    if rb~=lb then return rb>lb end
    return rc>lc
end

local function checkVersion(manual)
    PerformHttpRequest(('https://api.github.com/repos/%s/releases/latest'):format(repository), function(status, body)
        if status ~= 200 or not body then
            if manual then print(('[ps-fuel] Version check unavailable (HTTP %s).'):format(status)) end
            return
        end
        local ok,data=pcall(json.decode,body)
        if not ok or type(data)~='table' then return end
        local latest=tostring(data.tag_name or data.name or ''):gsub('^v','')
        if latest=='' then return end
        if newer(latest,installed) then
            print(('^3[ps-fuel]^7 Update available: ^2%s^7 -> ^2%s^7'):format(installed,latest))
            print(('^3[ps-fuel]^7 https://github.com/%s/releases/latest'):format(repository))
        elseif manual then
            print(('^2[ps-fuel]^7 v%s is current.'):format(installed))
        end
    end,'GET','',{['User-Agent']='ps-fuel-version-checker'})
end

CreateThread(function()
    Wait(5000)
    checkVersion(false)
    while true do Wait(21600000) checkVersion(false) end
end)

RegisterCommand('psfuelversion',function(source)
    if source~=0 then return end
    checkVersion(true)
end,true)
