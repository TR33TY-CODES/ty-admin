local Permissions = TYAdmin.Permissions
local Actions = TYAdmin.Actions
local Data = TYAdmin.Data
local Core = exports['ty-core']:GetCoreObject()
local requestTimes = {}
local actionTimes = {}

local function cooldownPassed(storage, source, duration)
    local now = GetGameTimer()
    local previous = storage[source] or 0
    if now - previous < duration then
        return false
    end
    storage[source] = now
    return true
end

local function respond(source, requestId, success, payload, errorMessage)
    TriggerClientEvent('ty-admin:client:response', source, tostring(requestId or ''), success == true, payload, errorMessage)
end

RegisterNetEvent('ty-admin:server:request', function(requestId, requestType)
    local source = tonumber(source)
    if not cooldownPassed(requestTimes, source, ConfigAdmin.RequestCooldown) then
        return
    end

    if requestType == 'open' then
        -- Ohne Berechtigung absichtlich keinerlei Client-Reaktion: F9 tut nichts.
        if not Permissions.Has(source, 'menu.open') then
            if ConfigAdmin.Debug then
                print(('[ty-admin][F9] Source %d hat keine Menüberechtigung.'):format(source))
            end
            return
        end

        local roleName, role = Permissions.GetRole(source)
        respond(source, requestId, true, {
            role = roleName,
            roleLabel = role.label,
            permissions = Permissions.BuildMap(source),
            state = Actions.GetState(source)
        })
        return
    end

    if not Permissions.Has(source, 'menu.open') then
        return
    end

    if requestType == 'players' then
        if not Permissions.Require(source, 'players.view') then
            respond(source, requestId, false, nil, 'Keine Berechtigung für die Spielerliste.')
            return
        end
        respond(source, requestId, true, { players = Data.BuildPlayers() })
    elseif requestType == 'vehicles' then
        if not Permissions.Require(source, 'vehicles.view') then
            respond(source, requestId, false, nil, 'Keine Berechtigung für Fahrzeuge.')
            return
        end
        respond(source, requestId, true, { vehicles = Data.BuildVehicles() })
    elseif requestType == 'items' then
        if not Permissions.Require(source, 'items.view') then
            respond(source, requestId, false, nil, 'Keine Berechtigung für Items.')
            return
        end
        local available, items = TYAdmin.Adapters.GetItems()
        respond(source, requestId, true, { available = available, items = items })
    elseif requestType == 'storedVehicles' then
        if not Permissions.Require(source, 'vehicles.search') then
            respond(source, requestId, false, nil, 'Keine Berechtigung für gespeicherte Fahrzeuge.')
            return
        end
        local available, vehicles = TYAdmin.Adapters.SearchStored('')
        respond(source, requestId, true, { available = available, vehicles = vehicles })
    else
        respond(source, requestId, false, nil, 'Unbekannte Anfrage.')
    end
end)

RegisterNetEvent('ty-admin:server:action', function(action, payload)
    local source = tonumber(source)
    if not cooldownPassed(actionTimes, source, ConfigAdmin.ActionCooldown) then
        return
    end

    local success, message, data = Actions.Execute(source, tostring(action or ''), payload)
    Actions.SendResult(source, success, message, data)
end)

AddEventHandler('playerDropped', function()
    local source = tonumber(source)
    Actions.Clear(source)
    requestTimes[source] = nil
    actionTimes[source] = nil
end)

RegisterCommand('tyunban', function(source, arguments)
    source = tonumber(source)
    if source ~= 0 and not Permissions.Require(source, 'security.unban') then
        TriggerClientEvent('ty-admin:client:actionResult', source, false, 'Keine Berechtigung.', nil)
        return
    end

    local playerId = math.floor(tonumber(arguments[1]) or 0)
    if playerId < 1 then
        local message = 'Verwendung: tyunban FESTE_SPIELER_ID'
        if source == 0 then print(('[ty-admin][UNBAN] %s'):format(message)) else TriggerClientEvent('ty-admin:client:actionResult', source, false, message, nil) end
        return
    end

    local row = MySQL.single.await([[
        SELECT c.id, c.data_json
        FROM ty_characters c
        INNER JOIN ty_accounts a ON a.id = c.account_id
        WHERE a.player_id = ?
        LIMIT 1
    ]], { playerId })

    if not row then
        local message = ('Keine feste Spieler-ID %d gefunden.'):format(playerId)
        if source == 0 then print(('[ty-admin][UNBAN] %s'):format(message)) else TriggerClientEvent('ty-admin:client:actionResult', source, false, message, nil) end
        return
    end

    local success, data = pcall(json.decode, row.data_json or '{}')
    data = success and type(data) == 'table' and data or {}
    data.connectionBlock = nil
    MySQL.update.await('UPDATE ty_characters SET data_json = ?, last_saved_at = CURRENT_TIMESTAMP WHERE id = ?', {
        json.encode(data),
        row.id
    })

    local message = ('Bann für feste Spieler-ID %d entfernt.'):format(playerId)
    print(('[ty-admin][UNBAN] %s'):format(message))
    if source ~= 0 then TriggerClientEvent('ty-admin:client:actionResult', source, true, message, nil) end
end, false)

exports('HasPermission', Permissions.Has)
exports('GetRole', Permissions.GetRole)
exports('IsAdminMode', function(source)
    local state = TYAdmin.States[tonumber(source)]
    return state ~= nil and state.adminMode == true
end)
exports('IsDevelopmentMode', function(source)
    local state = TYAdmin.States[tonumber(source)]
    return state ~= nil and state.developmentMode == true
end)

print('[ty-admin][START] Adminsystem bereit. F9 wird serverseitig über ACE geprüft.')
