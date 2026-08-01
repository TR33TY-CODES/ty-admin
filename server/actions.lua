TYAdmin.States = TYAdmin.States or {}
TYAdmin.FrozenTargets = TYAdmin.FrozenTargets or {}
TYAdmin.Actions = TYAdmin.Actions or {}

local Actions = TYAdmin.Actions
local Permissions = TYAdmin.Permissions
local Data = TYAdmin.Data
local Core = exports['ty-core']:GetCoreObject()

local actionPermissions = {
    developmentMode = 'development.toggle',
    godmode = 'self.godmode',
    invisible = 'self.invisible',
    noclip = 'self.noclip',
    nametags = 'self.nametags',
    thermal = 'self.thermal',
    coordinates = 'self.coordinates',
    vehicledata = 'self.vehicledata',
    healSelf = 'self.heal',
    reviveSelf = 'self.revive',
    teleportWaypoint = 'self.teleport_waypoint',
    healPlayer = 'players.heal',
    revivePlayer = 'players.revive',
    gotoPlayer = 'players.goto',
    bringPlayer = 'players.bring',
    spectatePlayer = 'players.spectate',
    freezePlayer = 'players.freeze',
    kickPlayer = 'players.kick',
    banPlayer = 'players.ban',
    giveItem = 'items.give',
    spawnVehicle = 'vehicles.spawn',
    teleportVehicle = 'vehicles.teleport',
    repairVehicle = 'vehicles.repair',
    washVehicle = 'vehicles.wash',
    flipVehicle = 'vehicles.flip',
    performanceVehicle = 'vehicles.modify',
    deleteVehicle = 'vehicles.delete',
    godmodeVehicle = 'vehicles.godmode',
    parkVehicle = 'vehicles.park',
    reloadVehicle = 'vehicles.reload',
    claimVehicle = 'vehicles.claim',
    createVehicleKey = 'vehicles.key',
    weather = 'world.weather',
    power = 'world.power'
}

local modeKeys = {
    developmentMode = true,
    godmode = true,
    invisible = true,
    noclip = true,
    nametags = true,
    thermal = true,
    coordinates = true,
    vehicledata = true
}

local function defaultState()
    return {
        developmentMode = false,
        godmode = false,
        invisible = false,
        noclip = false,
        nametags = false,
        thermal = false,
        coordinates = false,
        vehicledata = false
    }
end

local function getState(source)
    source = tonumber(source)
    TYAdmin.States[source] = TYAdmin.States[source] or defaultState()
    return TYAdmin.States[source]
end

local function sanitizeReason(value)
    local reason = tostring(value or ''):gsub('[\r\n]', ' '):sub(1, ConfigAdmin.MaxReasonLength)
    reason = reason:gsub('^%s*(.-)%s*$', '%1')
    return reason
end

local function validTarget(source)
    source = tonumber(source)
    local player = source and Core.Functions.GetPlayer(source) or nil
    if not player or not player.loaded or not GetPlayerName(source) then
        return nil
    end
    return player
end

local function sendResult(source, success, message, data)
    TriggerClientEvent('ty-admin:client:actionResult', source, success == true, tostring(message or ''), data)
end

local function applyState(source)
    local state = getState(source)
    local playerState = Player(source)

    if playerState and playerState.state then
        playerState.state:set('tyDevelopmentMode', state.developmentMode, true)
    end

    TriggerClientEvent('ty-admin:client:applyState', source, state)
end

local function setMode(source, action, enabled)
    if not modeKeys[action] then
        return false, 'Unbekannter Modus.'
    end

    local state = getState(source)
    enabled = enabled == true

    state[action] = enabled

    applyState(source)
    return true, enabled and 'Modus aktiviert.' or 'Modus deaktiviert.', getState(source)
end

local function playerEffect(targetSource, effect, payload)
    TriggerClientEvent('ty-admin:client:playerEffect', targetSource, effect, payload or {})
end

local function createVehicle(source, modelName)
    local catalog = Data.GetCatalogVehicle(modelName)
    if not catalog then
        return false, 'Dieses Fahrzeug steht nicht im freigegebenen Fahrzeugkatalog.'
    end

    local position = Data.GetPlayerPosition(source)
    if not position then
        return false, 'Die Position des Administrators konnte nicht gelesen werden.'
    end

    local heading = position.w or 0.0
    local radians = math.rad(heading)
    local x = position.x - math.sin(radians) * 3.5
    local y = position.y + math.cos(radians) * 3.5
    local modelHash = GetHashKey(catalog.model)
    local vehicle = 0

    if type(CreateVehicleServerSetter) == 'function' then
        local success, created = pcall(CreateVehicleServerSetter, modelHash, catalog.type, x, y, position.z, heading)
        if success then vehicle = created or 0 end
    end

    if vehicle == 0 and type(CreateVehicle) == 'function' then
        local success, created = pcall(CreateVehicle, modelHash, x, y, position.z, heading, true, true)
        if success then vehicle = created or 0 end
    end

    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return false, 'Das Fahrzeug konnte serverseitig nicht erstellt werden.'
    end

    if type(SetEntityRoutingBucket) == 'function' then
        SetEntityRoutingBucket(vehicle, GetPlayerRoutingBucket(source))
    end
    if type(SetEntityOrphanMode) == 'function' then
        SetEntityOrphanMode(vehicle, 2)
    end

    local networkId = NetworkGetNetworkIdFromEntity(vehicle)
    TriggerClientEvent('ty-admin:client:enterVehicle', source, networkId)
    return true, ('%s wurde gespawnt.'):format(catalog.label), { networkId = networkId }
end

local function vehicleAction(source, action, payload)
    local adapterOperation = {
        parkVehicle = 'Park',
        reloadVehicle = 'Reload',
        claimVehicle = 'Claim',
        createVehicleKey = 'CreateKey'
    }

    local operation = adapterOperation[action]
    if operation then
        return TYAdmin.Adapters.CallVehicle(operation, source, payload.networkId, payload)
    end

    local entity = Data.GetVehicleEntity(payload.networkId)
    if not entity then
        return false, 'Das Fahrzeug ist nicht mehr aktiv oder nicht synchronisiert.'
    end

    if action == 'teleportVehicle' then
        local position = Data.GetEntityPosition(entity)
        if not position then return false, 'Fahrzeugposition nicht verfügbar.' end
        position.z = position.z + 1.0
        playerEffect(source, 'teleport', position)
        return true, 'Zum Fahrzeug teleportiert.'
    elseif action == 'deleteVehicle' then
        DeleteEntity(entity)
        return true, 'Fahrzeug gelöscht.'
    elseif action == 'godmodeVehicle' then
        local enabled = payload.enabled == true
        Entity(entity).state:set('tyVehicleGodmode', enabled, true)
        TriggerClientEvent('ty-admin:client:vehicleAction', -1, 'godmode', payload.networkId, { enabled = enabled })
        return true, enabled and 'Fahrzeug-Godmode aktiviert.' or 'Fahrzeug-Godmode deaktiviert.'
    elseif action == 'repairVehicle' then
        TriggerClientEvent('ty-admin:client:vehicleAction', source, 'repair', payload.networkId, {})
        return true, 'Reparatur ausgeführt.'
    elseif action == 'washVehicle' then
        TriggerClientEvent('ty-admin:client:vehicleAction', source, 'wash', payload.networkId, {})
        return true, 'Fahrzeug gewaschen.'
    elseif action == 'flipVehicle' then
        TriggerClientEvent('ty-admin:client:vehicleAction', source, 'flip', payload.networkId, {})
        return true, 'Fahrzeug aufgerichtet.'
    elseif action == 'performanceVehicle' then
        TriggerClientEvent('ty-admin:client:vehicleAction', source, 'performance', payload.networkId, {})
        return true, 'Performance-Modifikationen wurden maximiert.'
    end

    return false, 'Unbekannte Fahrzeugaktion.'
end

function Actions.GetState(source)
    return getState(source)
end

function Actions.Execute(source, action, payload)
    source = tonumber(source)
    payload = type(payload) == 'table' and payload or {}

    local permission = actionPermissions[action]
    if not permission or not Permissions.Require(source, permission) then
        return false, 'Für diese Funktion fehlt dir die Berechtigung.'
    end

    if modeKeys[action] then
        return setMode(source, action, payload.enabled)
    end

    if action == 'healSelf' then
        playerEffect(source, 'heal')
        return true, 'Du wurdest geheilt.'
    elseif action == 'reviveSelf' then
        playerEffect(source, 'revive')
        return true, 'Du wurdest wiederbelebt.'
    elseif action == 'teleportWaypoint' then
        playerEffect(source, 'teleportWaypoint')
        return true, 'Wegpunkt-Teleport wird ausgeführt.'
    elseif action == 'weather' or action == 'power' then
        if ConfigAdmin.Debug or ConfigAdmin.PrintPreparedFeatures then
            print(('[ty-admin][VORBEREITET] %s benötigt später eine synchronisierte Welt-Resource.'):format(action))
        end
        return false, 'Diese Funktion ist für eine spätere synchronisierte Welt-Resource vorbereitet.'
    end

    if action == 'spawnVehicle' then
        return createVehicle(source, tostring(payload.model or ''))
    end

    if action:find('Vehicle', 1, true) then
        return vehicleAction(source, action, payload)
    end

    local target = validTarget(payload.target)
    if not target then
        return false, 'Der ausgewählte Spieler ist nicht mehr online.'
    end

    if action == 'healPlayer' then
        playerEffect(target.source, 'heal')
        return true, ('%s wurde geheilt.'):format(target.name)
    elseif action == 'revivePlayer' then
        playerEffect(target.source, 'revive')
        return true, ('%s wurde wiederbelebt.'):format(target.name)
    elseif action == 'gotoPlayer' then
        local position = Data.GetPlayerPosition(target.source)
        if not position then return false, 'Zielposition nicht verfügbar.' end
        playerEffect(source, 'teleport', position)
        return true, ('Zu %s teleportiert.'):format(target.name)
    elseif action == 'bringPlayer' then
        local position = Data.GetPlayerPosition(source)
        if not position then return false, 'Eigene Position nicht verfügbar.' end
        playerEffect(target.source, 'teleport', position)
        return true, ('%s wurde zu dir teleportiert.'):format(target.name)
    elseif action == 'spectatePlayer' then
        if getState(source).noclip then
            return false, 'Deaktiviere Noclip, bevor du Spectate startest.'
        end
        TriggerClientEvent('ty-admin:client:spectate', source, target.source, Data.GetPlayerPosition(target.source))
        return true, ('Spectate für %s umgeschaltet.'):format(target.name)
    elseif action == 'freezePlayer' then
        local enabled = payload.enabled == true
        TYAdmin.FrozenTargets[target.source] = enabled or nil
        playerEffect(target.source, 'freeze', { enabled = enabled })
        return true, enabled and ('%s wurde eingefroren.'):format(target.name) or ('%s wurde freigegeben.'):format(target.name)
    elseif action == 'giveItem' then
        if target.source ~= source and not Permissions.Require(source, 'players.give_item') then
            return false, 'Du darfst anderen Spielern keine Items geben.'
        end

        local itemName = tostring(payload.item or ''):sub(1, 64)
        local amount = math.floor(tonumber(payload.amount) or 0)
        if itemName == '' or amount < 1 or amount > ConfigAdmin.MaxItemAmount then
            return false, 'Item oder Menge ist ungültig.'
        end
        local success, errorMessage = TYAdmin.Adapters.GiveItem(target.source, itemName, amount, payload.metadata)
        return success, success and ('%dx %s an %s gegeben.'):format(amount, itemName, target.name) or errorMessage
    elseif action == 'kickPlayer' then
        if target.source == source then return false, 'Du kannst dich nicht selbst kicken.' end
        local reason = sanitizeReason(payload.reason)
        if #reason < 3 then return false, 'Bitte gib eine Begründung mit mindestens 3 Zeichen ein.' end
        print(('[ty-admin][KICK] %s (ID %d) durch %s | %s'):format(target.name, target.playerId, GetPlayerName(source), reason))
        DropPlayer(target.source, ('Von einem Teammitglied gekickt: %s'):format(reason))
        return true, ('%s wurde gekickt.'):format(target.name)
    elseif action == 'banPlayer' then
        if target.source == source then return false, 'Du kannst dich nicht selbst bannen.' end
        local reason = sanitizeReason(payload.reason)
        if #reason < 3 then return false, 'Bitte gib eine Begründung mit mindestens 3 Zeichen ein.' end

        local duration = math.max(0, math.min(math.floor(tonumber(payload.duration) or 0), 365 * 24 * 60 * 60))
        local block = {
            active = true,
            reason = reason,
            createdAt = os.time(),
            expiresAt = duration == 0 and 0 or os.time() + duration,
            byPlayerId = Core.Functions.GetPlayer(source).playerId,
            byName = GetPlayerName(source)
        }

        local setSuccess, setError = target:SetData('connectionBlock', block)
        if not setSuccess then return false, setError end
        local saveSuccess, saveError = Core.Functions.SavePlayer(target.source, 'Admin-Bann')
        if not saveSuccess then return false, saveError end

        print(('[ty-admin][BANN] %s (ID %d) durch %s | %s | Dauer: %s'):format(
            target.name,
            target.playerId,
            GetPlayerName(source),
            reason,
            duration == 0 and 'Permanent' or duration
        ))
        DropPlayer(target.source, ('Gebannt: %s'):format(reason))
        return true, ('%s wurde gebannt.'):format(target.name)
    end

    return false, 'Unbekannte Adminaktion.'
end

function Actions.SendResult(source, success, message, data)
    sendResult(source, success, message, data)
end

function Actions.Clear(source)
    source = tonumber(source)
    TYAdmin.States[source] = nil
    TYAdmin.FrozenTargets[source] = nil
end
