TYAdmin.Data = TYAdmin.Data or {}

local Data = TYAdmin.Data
local Core = exports['ty-core']:GetCoreObject()
local vehicleCatalog = {}

local function safeNative(native, fallback, ...)
    if type(native) ~= 'function' then
        return fallback
    end

    local success, value = pcall(native, ...)
    if success and value ~= nil then
        return value
    end

    return fallback
end

local function getPath(root, path)
    local current = root

    for part in tostring(path):gmatch('[^.]+') do
        if type(current) ~= 'table' then
            return nil
        end
        current = current[part]
    end

    return current
end

local function firstPath(root, candidates)
    for index = 1, #candidates do
        local value = getPath(root, candidates[index])
        if value ~= nil then
            if type(value) == 'table' then
                return value.label or value.name or value.id
            end
            return value
        end
    end

    return nil
end

local function normalizedDisplay(value, suffix)
    if value == nil or value == '' then
        return 'Nicht vorhanden'
    end

    if type(value) == 'boolean' then
        return value and 'Ja' or 'Nein'
    end

    return ('%s%s'):format(tostring(value), suffix or '')
end

local function entityPosition(entity)
    local coords = safeNative(GetEntityCoords, nil, entity)
    if not coords then
        return { x = 0.0, y = 0.0, z = 0.0, w = 0.0 }
    end

    return {
        x = tonumber(coords.x) or 0.0,
        y = tonumber(coords.y) or 0.0,
        z = tonumber(coords.z) or 0.0,
        w = tonumber(safeNative(GetEntityHeading, 0.0, entity)) or 0.0
    }
end

for categoryIndex = 1, #ConfigAdmin.VehicleCategories do
    local category = ConfigAdmin.VehicleCategories[categoryIndex]
    for vehicleIndex = 1, #category.vehicles do
        local vehicle = category.vehicles[vehicleIndex]
        vehicleCatalog[GetHashKey(vehicle.model)] = {
            model = vehicle.model,
            label = vehicle.label,
            type = vehicle.type or 'automobile',
            category = category.label
        }
    end
end

function Data.GetCatalogVehicle(model)
    local hash = type(model) == 'number' and model or GetHashKey(tostring(model or ''))
    return vehicleCatalog[hash]
end

function Data.BuildPlayers()
    local result = {}
    local players = Core.Functions.GetPlayers()

    for source, player in pairs(players) do
        if player.loaded then
            Core.CaptureVitals(player)
            local characterData = player.character.data or {}
            local position = player.character.position

            result[#result + 1] = {
                source = tonumber(source),
                playerId = player.playerId,
                accountId = player.accountId,
                characterId = player.character.id,
                name = player.name,
                model = player.character.model,
                health = player.character.health,
                armor = player.character.armor,
                routingBucket = GetPlayerRoutingBucket(source),
                position = {
                    x = position.x,
                    y = position.y,
                    z = position.z,
                    w = position.w
                },
                cash = normalizedDisplay(firstPath(characterData, ConfigAdmin.PlayerDataPaths.cash), ' $'),
                bank = normalizedDisplay(firstPath(characterData, ConfigAdmin.PlayerDataPaths.bank), ' $'),
                job = normalizedDisplay(firstPath(characterData, ConfigAdmin.PlayerDataPaths.job)),
                gang = normalizedDisplay(firstPath(characterData, ConfigAdmin.PlayerDataPaths.gang)),
                hunger = normalizedDisplay(firstPath(characterData, ConfigAdmin.PlayerDataPaths.hunger), '%'),
                thirst = normalizedDisplay(firstPath(characterData, ConfigAdmin.PlayerDataPaths.thirst), '%'),
                frozen = TYAdmin.FrozenTargets and TYAdmin.FrozenTargets[tonumber(source)] == true or false
            }
        end
    end

    table.sort(result, function(left, right)
        return left.playerId < right.playerId
    end)

    return result
end

function Data.BuildVehicles()
    local result = {}
    local vehicles = type(GetAllVehicles) == 'function' and GetAllVehicles() or {}

    for index = 1, #vehicles do
        local entity = vehicles[index]
        if DoesEntityExist(entity) then
            local modelHash = safeNative(GetEntityModel, 0, entity)
            local catalog = vehicleCatalog[modelHash]
            local state = Entity(entity).state
            local rotation = safeNative(GetEntityRotation, nil, entity)

            result[#result + 1] = {
                networkId = safeNative(NetworkGetNetworkIdFromEntity, 0, entity),
                plate = tostring(safeNative(GetVehicleNumberPlateText, 'UNBEKANNT', entity)):gsub('^%s*(.-)%s*$', '%1'),
                modelHash = modelHash,
                model = catalog and catalog.model or tostring(modelHash),
                label = catalog and catalog.label or ('Modell %s'):format(modelHash),
                category = catalog and catalog.category or 'Aktives Fahrzeug',
                position = entityPosition(entity),
                rotation = {
                    x = rotation and tonumber(rotation.x) or 0.0,
                    y = rotation and tonumber(rotation.y) or 0.0,
                    z = rotation and tonumber(rotation.z) or 0.0
                },
                engineHealth = tonumber(safeNative(GetVehicleEngineHealth, 1000.0, entity)) or 1000.0,
                bodyHealth = tonumber(safeNative(GetVehicleBodyHealth, 1000.0, entity)) or 1000.0,
                fuel = tonumber(state.fuel) or tonumber(safeNative(GetVehicleFuelLevel, 0.0, entity)) or 0.0,
                routingBucket = safeNative(GetEntityRoutingBucket, 0, entity),
                godmode = state.tyVehicleGodmode == true
            }
        end
    end

    table.sort(result, function(left, right)
        return left.plate < right.plate
    end)

    return result
end

function Data.GetVehicleEntity(networkId)
    networkId = tonumber(networkId)
    if not networkId or networkId <= 0 then
        return nil
    end

    local entity = safeNative(NetworkGetEntityFromNetworkId, 0, networkId)
    if entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then
        return nil
    end

    return entity
end

function Data.GetPlayerPosition(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        local player = Core.Functions.GetPlayer(source)
        return player and player.character.position or nil
    end

    return entityPosition(ped)
end

function Data.GetEntityPosition(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return nil
    end

    return entityPosition(entity)
end
