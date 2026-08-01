TYAdminClient = TYAdminClient or {}

local defaultState = {
    developmentMode = false,
    godmode = false,
    invisible = false,
    noclip = false,
    nametags = false,
    thermal = false,
    coordinates = false,
    vehicledata = false
}

TYAdminClient.State = TYAdminClient.State or {}
for key, value in pairs(defaultState) do
    if TYAdminClient.State[key] == nil then
        TYAdminClient.State[key] = value
    end
end

local spectate = {
    active = false,
    targetSource = nil,
    targetPed = 0,
    returnPosition = nil,
    returnHeading = nil,
    generation = 0
}

local noclipEntity = 0
local lastPlayerPed = 0

local function notify(message)
    exports['ty-menu']:Notify(message)
end

local function debugPrint(message)
    if ConfigAdmin.Debug then
        print(('[ty-admin][EFFECTS] %s'):format(message))
    end
end

local function normalizeState(state)
    local normalized = {}
    state = type(state) == 'table' and state or {}

    for key, defaultValue in pairs(defaultState) do
        normalized[key] = state[key] == nil and defaultValue or state[key] == true
    end

    return normalized
end

local function rotationToDirection(rotation)
    local pitch = math.rad(rotation.x)
    local yaw = math.rad(rotation.z)
    local cosine = math.abs(math.cos(pitch))

    return vector3(
        -math.sin(yaw) * cosine,
        math.cos(yaw) * cosine,
        math.sin(pitch)
    )
end

local function drawText2D(x, y, value, scale)
    SetTextFont(0)
    SetTextScale(scale or 0.30, scale or 0.30)
    SetTextColour(255, 255, 255, 220)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(tostring(value))
    DrawText(x, y)
end

local function drawText3D(coords, value)
    local visible, x, y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if not visible then return end

    SetTextScale(0.0, 0.28)
    SetTextFont(0)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 220)
    SetTextCentre(true)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(tostring(value))
    DrawText(x, y)
end

local function requestControl(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then
        return false
    end

    if not NetworkGetEntityIsNetworked(entity) or NetworkHasControlOfEntity(entity) then
        return true
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

local function vehicleGodmodeEnabled(entity)
    if entity == 0 or not DoesEntityExist(entity) or not IsEntityAVehicle(entity) then
        return false
    end

    local success, enabled = pcall(function()
        return Entity(entity).state.tyVehicleGodmode == true
    end)
    return success and enabled == true
end

local function setNetworkInvisible(entity, enabled)
    if type(NetworkSetEntityInvisibleToNetwork) == 'function' then
        NetworkSetEntityInvisibleToNetwork(entity, enabled == true)
    end
end

local function shouldProtectPed()
    local state = TYAdminClient.State
    return state.godmode == true or state.noclip == true or spectate.active == true
end

local function applyPedPresentation()
    local ped = PlayerPedId()
    if ped == 0 or not DoesEntityExist(ped) then return end

    local state = TYAdminClient.State
    local protected = shouldProtectPed()
    local hidden = state.invisible == true or spectate.active == true

    SetEntityInvincible(ped, protected)
    SetPlayerInvincible(PlayerId(), protected)
    SetEntityCanBeDamaged(ped, not protected)

    if hidden then
        setNetworkInvisible(ped, true)
        SetEntityVisible(ped, false, false)
        SetEntityAlpha(ped, 0, false)
    else
        setNetworkInvisible(ped, false)
        SetEntityVisible(ped, true, false)
        if state.noclip and noclipEntity == ped then
            SetEntityAlpha(ped, 190, false)
        else
            ResetEntityAlpha(ped)
        end
    end
end

local function cleanupNoclipEntity(entity)
    entity = tonumber(entity) or 0
    if entity == 0 or not DoesEntityExist(entity) then return end

    FreezeEntityPosition(entity, false)
    SetEntityCollision(entity, true, true)
    SetEntityVelocity(entity, 0.0, 0.0, 0.0)
    ResetEntityAlpha(entity)

    if IsEntityAVehicle(entity) then
        SetEntityVisible(entity, true, false)
        local enabled = vehicleGodmodeEnabled(entity)
        SetEntityInvincible(entity, enabled)
        SetEntityCanBeDamaged(entity, not enabled)
    end
end

local function stopNoclip()
    if noclipEntity ~= 0 then
        cleanupNoclipEntity(noclipEntity)
        noclipEntity = 0
    end

    SetEveryoneIgnorePlayer(PlayerId(), false)
    SetPoliceIgnorePlayer(PlayerId(), false)
    applyPedPresentation()
end

local function teleport(position)
    if type(position) ~= 'table' then return false end

    local x = tonumber(position.x)
    local y = tonumber(position.y)
    local z = tonumber(position.z)
    if not x or not y or not z then return false end

    local ped = PlayerPedId()
    local entity = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped

    DoScreenFadeOut(150)
    local timeout = GetGameTimer() + 1500
    while not IsScreenFadedOut() and GetGameTimer() < timeout do Wait(0) end

    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(entity, x, y, z, false, false, false)
    if tonumber(position.w) then
        SetEntityHeading(entity, tonumber(position.w))
    end

    Wait(150)
    DoScreenFadeIn(250)
    return true
end

local function teleportToWaypoint()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then
        notify('Es wurde kein Wegpunkt gesetzt.')
        return
    end

    local coords = GetBlipInfoIdCoord(blip)
    local groundZ = coords.z
    local foundGround = false

    for height = 50, 1000, 50 do
        RequestCollisionAtCoord(coords.x, coords.y, height + 0.0)
        local found, value = GetGroundZFor_3dCoord(coords.x, coords.y, height + 0.0, false)
        if found then
            groundZ = value + 1.0
            foundGround = true
            break
        end
        Wait(10)
    end

    if not foundGround then
        groundZ = coords.z + 1.0
    end

    teleport({ x = coords.x, y = coords.y, z = groundZ, w = GetEntityHeading(PlayerPedId()) })
end

local function stopSpectate(restorePosition, showMessage)
    if not spectate.active then return end

    spectate.generation = spectate.generation + 1
    local targetPed = spectate.targetPed
    if targetPed == 0 or not DoesEntityExist(targetPed) then
        targetPed = PlayerPedId()
    end
    NetworkSetInSpectatorMode(false, targetPed)
    ClearFocus()

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)

    if restorePosition and spectate.returnPosition then
        local position = spectate.returnPosition
        RequestCollisionAtCoord(position.x, position.y, position.z)
        SetEntityCoordsNoOffset(ped, position.x, position.y, position.z, false, false, false)
        SetEntityHeading(ped, spectate.returnHeading or GetEntityHeading(ped))
    end

    spectate.active = false
    spectate.targetSource = nil
    spectate.targetPed = 0
    spectate.returnPosition = nil
    spectate.returnHeading = nil
    applyPedPresentation()

    if showMessage then
        notify('Spectate beendet.')
    end
end

local function startSpectate(targetSource, targetPosition)
    targetSource = tonumber(targetSource)
    if not targetSource then return end

    if TYAdminClient.State.noclip then
        notify('Deaktiviere Noclip, bevor du Spectate startest.')
        return
    end

    if spectate.active and spectate.targetSource == targetSource then
        stopSpectate(true, true)
        return
    end

    if not spectate.active then
        local coords = GetEntityCoords(PlayerPedId())
        spectate.returnPosition = { x = coords.x, y = coords.y, z = coords.z }
        spectate.returnHeading = GetEntityHeading(PlayerPedId())
    else
        local previousTarget = spectate.targetPed
        if previousTarget == 0 or not DoesEntityExist(previousTarget) then
            previousTarget = PlayerPedId()
        end
        NetworkSetInSpectatorMode(false, previousTarget)
    end

    spectate.generation = spectate.generation + 1
    local generation = spectate.generation
    spectate.active = true
    spectate.targetSource = targetSource
    spectate.targetPed = 0

    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    SetEntityCollision(ped, false, false)
    applyPedPresentation()

    if type(targetPosition) == 'table' then
        local x = tonumber(targetPosition.x)
        local y = tonumber(targetPosition.y)
        local z = tonumber(targetPosition.z)
        if x and y and z then
            RequestCollisionAtCoord(x, y, z)
            SetEntityCoordsNoOffset(ped, x, y, z + 10.0, false, false, false)
        end
    end

    CreateThread(function()
        local expiresAt = GetGameTimer() + 5000
        local targetPed = 0

        while spectate.active and spectate.generation == generation and GetGameTimer() < expiresAt do
            local player = GetPlayerFromServerId(targetSource)
            if player ~= -1 then
                targetPed = GetPlayerPed(player)
                if targetPed ~= 0 and DoesEntityExist(targetPed) then break end
            end
            Wait(100)
        end

        if not spectate.active or spectate.generation ~= generation then return end
        if targetPed == 0 or not DoesEntityExist(targetPed) then
            notify('Der Spieler konnte für Spectate nicht geladen werden.')
            stopSpectate(true, false)
            return
        end

        spectate.targetPed = targetPed
        NetworkSetInSpectatorMode(true, targetPed)
        notify(('Spectate gestartet: Server-ID %d. Erneut auswählen zum Beenden.'):format(targetSource))
    end)
end

function TYAdminClient.GetNearestVehicleNetworkId(maximumDistance)
    local ped = PlayerPedId()
    local vehicle = 0

    if IsPedInAnyVehicle(ped, false) then
        vehicle = GetVehiclePedIsIn(ped, false)
    else
        local coords = GetEntityCoords(ped)
        vehicle = GetClosestVehicle(coords.x, coords.y, coords.z, maximumDistance or 8.0, 0, 71)
    end

    if vehicle == 0 or not DoesEntityExist(vehicle) then
        return nil
    end

    local networkId = NetworkGetNetworkIdFromEntity(vehicle)
    return networkId ~= 0 and networkId or nil
end

function TYAdminClient.IsVehicleGodmode(networkId)
    local vehicle = vehicleFromNetworkId(networkId)
    return vehicle ~= 0 and vehicleGodmodeEnabled(vehicle)
end

RegisterNetEvent('ty-admin:client:applyState', function(state)
    local previous = TYAdminClient.State
    local normalized = normalizeState(state)

    if previous.noclip and not normalized.noclip then
        stopNoclip()
    end

    TYAdminClient.State = normalized
    SetSeethrough(normalized.thermal == true)

    if normalized.noclip and spectate.active then
        stopSpectate(true, false)
    end

    applyPedPresentation()
    debugPrint(('Status aktualisiert: Godmode=%s Unsichtbar=%s Noclip=%s'):format(
        tostring(normalized.godmode),
        tostring(normalized.invisible),
        tostring(normalized.noclip)
    ))
end)

RegisterNetEvent('ty-admin:client:playerEffect', function(effect, payload)
    payload = type(payload) == 'table' and payload or {}
    local ped = PlayerPedId()

    if effect == 'heal' then
        local maximumHealth = math.max(200, GetEntityMaxHealth(ped))
        SetEntityMaxHealth(ped, maximumHealth)
        SetEntityHealth(ped, maximumHealth)
        ClearPedBloodDamage(ped)
        ResetPedVisibleDamage(ped)
        ClearPedLastWeaponDamage(ped)
    elseif effect == 'revive' then
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, heading, 0, false)
        SetEntityMaxHealth(ped, math.max(200, GetEntityMaxHealth(ped)))
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
        ClearPedBloodDamage(ped)
        ResetPedVisibleDamage(ped)
        ClearPedLastWeaponDamage(ped)
        ClearPedTasksImmediately(ped)
        applyPedPresentation()
    elseif effect == 'teleport' then
        teleport(payload)
    elseif effect == 'teleportWaypoint' then
        teleportToWaypoint()
    elseif effect == 'freeze' then
        FreezeEntityPosition(ped, payload.enabled == true)
    end
end)

RegisterNetEvent('ty-admin:client:spectate', function(targetSource, targetPosition)
    startSpectate(targetSource, targetPosition)
end)

RegisterNetEvent('ty-admin:client:vehicleAction', function(actionName, networkId, payload)
    local vehicle = vehicleFromNetworkId(networkId)
    if vehicle == 0 then
        notify('Das Fahrzeug ist nicht mehr verfügbar.')
        return
    end

    payload = type(payload) == 'table' and payload or {}
    if not requestControl(vehicle) then
        notify('Keine Netzwerkkontrolle über das Fahrzeug erhalten.')
        return
    end

    if actionName == 'repair' then
        SetVehicleFixed(vehicle)
        SetVehicleDeformationFixed(vehicle)
        SetVehicleEngineHealth(vehicle, 1000.0)
        SetVehicleBodyHealth(vehicle, 1000.0)
        SetVehiclePetrolTankHealth(vehicle, 1000.0)
        SetVehicleEngineOn(vehicle, true, true, false)
    elseif actionName == 'wash' then
        SetVehicleDirtLevel(vehicle, 0.0)
        WashDecalsFromVehicle(vehicle, 1.0)
    elseif actionName == 'flip' then
        local rotation = GetEntityRotation(vehicle, 2)
        SetEntityRotation(vehicle, 0.0, 0.0, rotation.z, 2, true)
        SetVehicleOnGroundProperly(vehicle)
    elseif actionName == 'performance' then
        SetVehicleModKit(vehicle, 0)
        for _, modType in ipairs({ 11, 12, 13, 15, 16 }) do
            local maximum = GetNumVehicleMods(vehicle, modType) - 1
            if maximum >= 0 then
                SetVehicleMod(vehicle, modType, maximum, false)
            end
        end
        ToggleVehicleMod(vehicle, 18, true)
        SetVehicleFixed(vehicle)
    elseif actionName == 'godmode' then
        local enabled = payload.enabled == true
        SetEntityInvincible(vehicle, enabled)
        SetEntityCanBeDamaged(vehicle, not enabled)
        SetVehicleCanBeVisiblyDamaged(vehicle, not enabled)
        SetVehicleTyresCanBurst(vehicle, not enabled)
    end
end)

RegisterNetEvent('ty-admin:client:enterVehicle', function(networkId)
    CreateThread(function()
        local expiresAt = GetGameTimer() + 5000
        local vehicle = 0

        while vehicle == 0 and GetGameTimer() < expiresAt do
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
            local enabled = value == true
            SetEntityInvincible(entity, enabled)
            SetEntityCanBeDamaged(entity, not enabled)
            SetVehicleCanBeVisiblyDamaged(entity, not enabled)
            SetVehicleTyresCanBurst(entity, not enabled)
        end
    end)
end

CreateThread(function()
    while true do
        local state = TYAdminClient.State

        if state.noclip and not spectate.active then
            Wait(0)

            local ped = PlayerPedId()
            local entity = ped
            if IsPedInAnyVehicle(ped, false) then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if GetPedInVehicleSeat(vehicle, -1) == ped then
                    entity = vehicle
                end
            end

            if noclipEntity ~= entity then
                cleanupNoclipEntity(noclipEntity)
                noclipEntity = entity
            end

            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 37, true)

            local cameraRotation = GetGameplayCamRot(2)
            local direction = rotationToDirection(cameraRotation)
            local right = vector3(direction.y, -direction.x, 0.0)
            local speed = ConfigAdmin.Noclip.NormalSpeed

            if IsControlPressed(0, 21) then
                speed = ConfigAdmin.Noclip.FastSpeed
            elseif IsControlPressed(0, 36) then
                speed = ConfigAdmin.Noclip.SlowSpeed
            end

            local frameFactor = math.max(0.5, math.min((GetFrameTime() or 0.016) * 60.0, 2.0))
            local step = speed * 0.25 * frameFactor
            local coords = GetEntityCoords(entity)

            if IsControlPressed(0, 32) then coords = coords + direction * step end
            if IsControlPressed(0, 33) then coords = coords - direction * step end
            if IsControlPressed(0, 34) then coords = coords - right * step end
            if IsControlPressed(0, 35) then coords = coords + right * step end
            if IsControlPressed(0, 44) then coords = coords + vector3(0.0, 0.0, step) end
            if IsControlPressed(0, 38) then coords = coords - vector3(0.0, 0.0, step) end

            RequestCollisionAtCoord(coords.x, coords.y, coords.z)
            FreezeEntityPosition(entity, true)
            SetEntityCollision(entity, false, false)
            SetEntityInvincible(entity, true)
            SetEntityCanBeDamaged(entity, false)
            SetEntityVelocity(entity, 0.0, 0.0, 0.0)
            SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, true, true, true)
            SetEntityHeading(entity, cameraRotation.z)

            if IsEntityAVehicle(entity) then
                SetEntityVisible(entity, true, false)
                SetEntityAlpha(entity, 190, false)
            end

            SetEveryoneIgnorePlayer(PlayerId(), true)
            SetPoliceIgnorePlayer(PlayerId(), true)
            applyPedPresentation()
        else
            if noclipEntity ~= 0 then stopNoclip() end
            Wait(150)
        end
    end
end)

CreateThread(function()
    while true do
        local state = TYAdminClient.State
        local ped = PlayerPedId()
        local active = state.godmode or state.invisible or state.noclip or spectate.active

        if ped ~= lastPlayerPed then
            lastPlayerPed = ped
            applyPedPresentation()
        end

        if active then
            applyPedPresentation()

            if spectate.active then
                local player = GetPlayerFromServerId(spectate.targetSource or -1)
                local targetPed = player ~= -1 and GetPlayerPed(player) or 0
                if player == -1 or targetPed == 0 or not DoesEntityExist(targetPed) then
                    notify('Spectate wurde beendet, weil der Spieler nicht mehr verfügbar ist.')
                    stopSpectate(true, false)
                else
                    spectate.targetPed = targetPed
                end
            end

            Wait(state.godmode and 0 or 50)
        else
            Wait(250)
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
                drawText2D(0.012, 0.74, ('X %.2f  Y %.2f  Z %.2f  H %.2f'):format(
                    coords.x,
                    coords.y,
                    coords.z,
                    GetEntityHeading(PlayerPedId())
                ), 0.31)
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
                        if targetPed ~= 0 and DoesEntityExist(targetPed) then
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
    end
end)

function TYAdminClient.ResetEffects()
    stopSpectate(true, false)
    stopNoclip()
    TYAdminClient.State = normalizeState({})

    local ped = PlayerPedId()
    setNetworkInvisible(ped, false)
    SetEntityVisible(ped, true, false)
    ResetEntityAlpha(ped)
    SetEntityCollision(ped, true, true)
    FreezeEntityPosition(ped, false)
    SetEntityInvincible(ped, false)
    SetEntityCanBeDamaged(ped, true)
    SetPlayerInvincible(PlayerId(), false)
    SetEveryoneIgnorePlayer(PlayerId(), false)
    SetPoliceIgnorePlayer(PlayerId(), false)
    SetSeethrough(false)
end

exports('IsDevelopmentMode', function()
    return TYAdminClient.State.developmentMode == true
end)

exports('IsNoclip', function()
    return TYAdminClient.State.noclip == true
end)

exports('IsSpectating', function()
    return spectate.active == true, spectate.targetSource
end)

exports('GetAdminState', function()
    local copy = {}
    for key, value in pairs(TYAdminClient.State) do copy[key] = value end
    copy.spectating = spectate.active == true
    copy.spectateTarget = spectate.targetSource
    return copy
end)
