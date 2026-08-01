TYAdmin = TYAdmin or {}
TYAdmin.Permissions = TYAdmin.Permissions or {}

local Permissions = TYAdmin.Permissions

local function permissionMatches(granted, requested)
    if granted == '*' or granted == requested then
        return true
    end

    if granted:sub(-2) == '.*' then
        local prefix = granted:sub(1, -2)
        return requested:sub(1, #prefix + 1) == prefix .. '.'
    end

    return false
end

function Permissions.GetRole(source)
    source = tonumber(source)

    if source == 0 then
        return 'console', {
            label = 'Serverkonsole',
            permissions = { '*' }
        }
    end

    for index = 1, #ConfigPermissions.RoleOrder do
        local roleName = ConfigPermissions.RoleOrder[index]
        local role = ConfigPermissions.Roles[roleName]

        if role and IsPlayerAceAllowed(source, role.ace) then
            return roleName, role
        end
    end

    return nil, nil
end

function Permissions.Has(source, requested)
    if type(requested) ~= 'string' then
        return false
    end

    local _, role = Permissions.GetRole(source)
    if not role then
        return false
    end

    for index = 1, #role.permissions do
        if permissionMatches(role.permissions[index], requested) then
            return true
        end
    end

    return false
end

function Permissions.BuildMap(source)
    local result = {}

    for index = 1, #ConfigPermissions.KnownPermissions do
        local permission = ConfigPermissions.KnownPermissions[index]
        result[permission] = Permissions.Has(source, permission)
    end

    return result
end

function Permissions.Require(source, requested)
    if Permissions.Has(source, requested) then
        return true
    end

    if ConfigAdmin.Debug then
        print(('[ty-admin][BERECHTIGUNG] Source %s wurde fuer %s blockiert.'):format(source, requested))
    end

    return false
end
