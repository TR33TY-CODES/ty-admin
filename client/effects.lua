TYAdminClient = TYAdminClient or {}
TYAdminClient.State = TYAdminClient.State or {
    adminMode = false,
    developmentMode = false,
    godmode = false,
    invisible = false,
    noclip = false,
    nametags = false,
    thermal = false,
    coordinates = false,
    vehicledata = false
}

local spectating = false
local spectateTarget = nil
local noclipEntity = nil

local function notify(message)
    exports['ty-menu']:Notify(message)
end

local function rotationToDirection(rotation)
    local adjusted = {
        x = math.rad(rotation.x),
        y = math.rad(rotation.y),
        z = math.rad(rotation.z)
    }
    local cosine = math.abs(math.cos(adjusted.x))

    return vector3(
        -math.sin(adjusted.z) * cosine,
        math.cos(adjusted.z) * cosine,
        math.sin(adjusted.x)
    )
end

local function drawText2D(x, y, text, scale)
    SetTextFont(0)
    SetTextScale(scale or 0.30, scale or 0.30)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

local function drawText3D(coords, text)
    local visible, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not visible then return end

    SetTextScale(0.0, 0.28)
    SetTextFont(0)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 220)
    SetTextCentre(true)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(x, y)
end

local function requestControl(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end

    local startedAt = GetGameTimer()
    NetworkRequestControlOfEntity(entity)

    while not NetworkHasControlOfEntity(entity) and GetGameTimer() - startedAt < 2000 do
        Wait(0)
        NetworkRequestControlOfEntity(entity)
    end

    return NetworkHasControlOfEntity(entity)
end

local function vehicleFromNetworkId(networkId)
    networkId = tonumber(networkId)
    if not networkId or not NetworkDoesNetworkIdExist(networkId) then
        return 0
    end

    local entity = NetworkGetEntityFromNetworkId(networkId)
    if entity == 0 or not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then
        return 0
    end

    return entity
end

local function teleport(position)
    if type(position) ~= 'table' then return end

    local ped = PlayerPedId()
    local entity = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped
    local x = tonumber(position.x)
    local y = tonumber(position.y)
    local z = tonumber(position.z)
    if not x or not y or not z then return end

    DoScreenFadeOut(150)
    while not IsScreenFadedOut() do Wait(0) end
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(entity, x, y, z, false, false, false)
    if tonumber(position.w) then SetEntityHeading(entity, tonumber(position.w)) end
    Wait(150)
    DoScreenFadeIn(250)
end

local function teleportToWaypoint()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then
        notify('Es wurde kein Wegpunkt gesetzt.')
        return
    end

    local coords = GetBlipInfoIdCoord(blip)
    local groundZ = coords.z

    for height = 50, 1000, 50 do
        SetEntityCoordsNoOffset(PlayerPedId(), coords.x, coords.y, height + 0.0, false, false, false)
        RequestCollisionAtCoord(coords.x, coords.y, height + 0.0)
        Wait(25)
        local found, value = GetGroundZFor_3dCoord(coords.x, coords.y, height + 0.0, false)
        if found then
            groundZ = value + 1.0
            break
        end
    end

    teleport({ x = coords.x, y = coords.y, z = groundZ, w = GetEntityHeading(PlayerPedId()) })
end

function TYAdminClient.GetNearestVehicleNetworkId(maximumDistance)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, maximumDistance or 8.0, 0, 71)

    if vehicle == 0 and IsPedInAnyVehicle(ped, false) then
        vehicle = GetVehiclePedIsIn(ped, false)
    end

    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    return NetworkGetNetworkIdFromEntity(vehicle)
end

RegisterNetEvent('ty-admin:client:applyState', function(state)
    if type(state) ~= 'table' then return end
    TYAdminClient.State = state

    local ped = PlayerPedId()
    SetEntityInvincible(ped, state.godmode == true)
    SetPlayerInvincible(PlayerId(), state.godmode == true)
    SetEntityVisible(ped, state.invisible ~= true, false)
    SetSeethrough(state.thermal == true)

    if not state.noclip and noclipEntity and DoesEntityExist(noclipEntity) then
        FreezeEntityPosition(noclipEntity, false)
        SetEntityCollision(noclipEntity, true, true)
        SetEntityAlpha(noclipEntity, 255, false)
        noclipEntity = nil
    end
end)

RegisterNetEvent('ty-admin:client:playerEffect', function(effect, payload)
    payload = type(payload) == 'table' and payload or {}
    local ped = PlayerPedId()

    if effect == 'heal' then
        SetEntityMaxHealth(ped, 200)
        SetEntityHealth(ped, 200)
        ClearPedBloodDamage(ped)
    elseif effect == 'revive' then
        local coords = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), 0, false)
        SetEntityMaxHealth(ped, 200)
        SetEntityHealth(ped, 200)
        ClearPedBloodDamage(ped)
        ClearPedTasksImmediately(ped)
    elseif effect == 'teleport' then
        teleport(payload)
    elseif effect == 'teleportWaypoint' then
        teleportToWaypoint()
    elseif effect == 'freeze' then
        FreezeEntityPosition(ped, payload.enabled == true)
    end
end)

RegisterNetEvent('ty-admin:client:spectate', function(targetSource)
    targetSource = tonumber(targetSource)

    if spectating and spectateTarget == targetSource then
        NetworkSetInSpectatorMode(false, PlayerPedId())
        spectating = false
        spectateTarget = nil
        notify('Spectate beendet.')
        return
    end

    local player = GetPlayerFromServerId(targetSource)
    if player == -1 then
        notify('Der Spieler ist derzeit nicht gestreamt.')
        return
    end

    local targetPed = GetPlayerPed(player)
    if targetPed == 0 or not DoesEntityExist(targetPed) then
        notify('Der Spieler-Ped ist derzeit nicht verfügbar.')
        return
    end

    NetworkSetInSpectatorMode(true, targetPed)
    spectating = true
    spectateTarget = targetSource
end)

RegisterNetEvent('ty-admin:client:vehicleAction', function(action, networkId, payload)
    local vehicle = vehicleFromNetworkId(networkId)
    if vehicle == 0 then return end

    payload = type(payload) == 'table' and payload or {}
    requestControl(vehicle)

    if action == 'repair' then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        SetVehicleEngineOn(vehicle, true, true, false)
    elseif action == 'wash' then
        SetVehicleDirtLevel(vehicle, 0.0)
        WashDecalsFromVehicle(vehicle, 1.0)
    elseif action == 'flip' then
        local rotation = GetEntityRotation(vehicle, 2)
        SetEntityRotation(vehicle, 0.0, 0.0, rotation.z, 2, true)
        SetVehicleOnGroundProperly(vehicle)
    elseif action == 'godmode' then
        SetEntityInvincible(vehicle, payload.enabled == true)
        SetVehicleCanBeVisiblyDamaged(vehicle, payload.enabled ~= true)
        SetVehicleTyresCanBurst(vehicle, payload.enabled ~= true)
    end
end)

RegisterNetEvent('ty-admin:client:enterVehicle', function(networkId)
    CreateThread(function()
        local startedAt = GetGameTimer()
        local vehicle = 0

        while vehicle == 0 and GetGameTimer() - startedAt < 5000 do
            vehicle = vehicleFromNetworkId(networkId)
            Wait(50)
        end

        if vehicle ~= 0 then
            SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
        end
    end)
end)

if type(AddStateBagChangeHandler) == 'function' and type(GetEntityFromStateBagName) == 'function' then
    AddStateBagChangeHandler('tyVehicleGodmode', nil, function(bagName, _, value)
        local entity = GetEntityFromStateBagName(bagName)
        if entity and entity ~= 0 and DoesEntityExist(entity) and IsEntityAVehicle(entity) then
            SetEntityInvincible(entity, value == true)
            SetVehicleCanBeVisiblyDamaged(entity, value ~= true)
            SetVehicleTyresCanBurst(entity, value ~= true)
        end
    end)
end

CreateThread(function()
    while true do
        local state = TYAdminClient.State
        if not state.godmode and not state.invisible and not state.noclip then
            Wait(250)
        else
            Wait(0)
            local ped = PlayerPedId()

            if state.godmode then
                SetEntityInvincible(ped, true)
                SetPlayerInvincible(PlayerId(), true)
            end

            if state.invisible then
                SetEntityVisible(ped, false, false)
            end

            if state.noclip then
                local entity = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped
                noclipEntity = entity
                FreezeEntityPosition(entity, true)
                SetEntityCollision(entity, false, false)
                SetEntityAlpha(entity, 190, false)

                local coords = GetEntityCoords(entity)
                local cameraRotation = GetGameplayCamRot(2)
                local direction = rotationToDirection(cameraRotation)
                local right = vector3(direction.y, -direction.x, 0.0)
                local speed = ConfigAdmin.Noclip.NormalSpeed

                if IsControlPressed(0, 21) then speed = ConfigAdmin.Noclip.FastSpeed end
                if IsControlPressed(0, 19) then speed = ConfigAdmin.Noclip.SlowSpeed end

                if IsControlPressed(0, 32) then coords = coords + direction * speed end
                if IsControlPressed(0, 33) then coords = coords - direction * speed end
                if IsControlPressed(0, 34) then coords = coords - right * speed end
                if IsControlPressed(0, 35) then coords = coords + right * speed end
                if IsControlPressed(0, 44) then coords = coords + vector3(0.0, 0.0, speed) end
                if IsControlPressed(0, 38) then coords = coords - vector3(0.0, 0.0, speed) end

                SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, true, true, true)
                SetEntityHeading(entity, cameraRotation.z)
            end
        end
    end
end)

CreateThread(function()
    while true do
        local state = TYAdminClient.State
        if not state.nametags and not state.coordinates and not state.vehicledata then
            Wait(250)
        else
            Wait(0)

            if state.coordinates then
                local coords = GetEntityCoords(PlayerPedId())
                drawText2D(0.012, 0.74, ('X %.2f  Y %.2f  Z %.2f  H %.2f'):format(coords.x, coords.y, coords.z, GetEntityHeading(PlayerPedId())), 0.31)
            end

            if state.vehicledata then
                local ped = PlayerPedId()
                local vehicle = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or 0
                if vehicle ~= 0 then
                    drawText2D(0.012, 0.77, ('PLATE %s  ENGINE %.0f  BODY %.0f  FUEL %.1f'):format(
                        GetVehicleNumberPlateText(vehicle),
                        GetVehicleEngineHealth(vehicle),
                        GetVehicleBodyHealth(vehicle),
                        GetVehicleFuelLevel(vehicle)
                    ), 0.29)
                end
            end

            if state.nametags then
                local ownCoords = GetEntityCoords(PlayerPedId())
                for _, player in ipairs(GetActivePlayers()) do
                    if player ~= PlayerId() then
                        local targetPed = GetPlayerPed(player)
                        local targetCoords = GetEntityCoords(targetPed)
                        if #(ownCoords - targetCoords) <= 150.0 then
                            drawText3D(targetCoords + vector3(0.0, 0.0, 1.05), ('[%d] %s | HP %d'):format(
                                GetPlayerServerId(player),
                                GetPlayerName(player),
                                GetEntityHealth(targetPed)
                            ))
                        end
                    end
                end
            end
        end
    end
end)

exports('IsAdminMode', function()
    return TYAdminClient.State.adminMode == true
end)

exports('IsDevelopmentMode', function()
    return TYAdminClient.State.developmentMode == true
end)

exports('GetAdminState', function()
    local copy = {}
    for key, value in pairs(TYAdminClient.State) do copy[key] = value end
    return copy
end)
