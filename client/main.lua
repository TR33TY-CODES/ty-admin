TYAdminClient.Authorization = TYAdminClient.Authorization or {
    role = nil,
    roleLabel = nil,
    permissions = {}
}
TYAdminClient.MenuOpen = false

local requests = {}
local requestCounter = 0

function TYAdminClient.HasPermission(permission)
    return TYAdminClient.Authorization.permissions[permission] == true
end

function TYAdminClient.Request(requestType, callback)
    requestCounter = requestCounter + 1
    local requestId = ('%d:%d'):format(GetGameTimer(), requestCounter)

    requests[requestId] = {
        callback = callback,
        expiresAt = GetGameTimer() + 10000
    }

    TriggerServerEvent('ty-admin:server:request', requestId, requestType)
end

function TYAdminClient.Action(actionName, payload)
    TriggerServerEvent('ty-admin:server:action', actionName, payload or {})
end

RegisterNetEvent('ty-admin:client:response', function(requestId, success, payload, errorMessage)
    local request = requests[tostring(requestId)]
    if not request then return end

    requests[tostring(requestId)] = nil
    local callbackSucceeded, callbackError = pcall(request.callback, success == true, payload or {}, errorMessage)
    if not callbackSucceeded then
        print(('[ty-admin][CLIENT-CALLBACK-FEHLER] %s'):format(callbackError))
    end
end)

RegisterNetEvent('ty-admin:client:actionResult', function(success, message, data)
    if type(data) == 'table' and data.developmentMode ~= nil then
        TriggerEvent('ty-admin:client:applyState', data)
    end

    if message and message ~= '' then
        exports['ty-menu']:Notify(success and ('~g~%s'):format(message) or ('~r~%s'):format(message))
    end
end)

RegisterCommand(ConfigAdmin.OpenCommand, function()
    if TYAdminClient.MenuOpen or exports['ty-menu']:IsOpen() then
        exports['ty-menu']:CloseMenu()
        TYAdminClient.MenuOpen = false
        return
    end

    TYAdminClient.Request('open', function(success, payload)
        if not success then return end

        TYAdminClient.Authorization = {
            role = payload.role,
            roleLabel = payload.roleLabel,
            permissions = payload.permissions or {}
        }
        if type(payload.state) == 'table' then
            TriggerEvent('ty-admin:client:applyState', payload.state)
        end
        TYAdminClient.Menus.OpenRoot()
    end)
end, false)

RegisterKeyMapping(ConfigAdmin.OpenCommand, 'TY Adminmenü öffnen', 'keyboard', ConfigAdmin.DefaultKey)

CreateThread(function()
    while true do
        Wait(1000)
        local now = GetGameTimer()

        for requestId, request in pairs(requests) do
            if now >= request.expiresAt then
                requests[requestId] = nil
            end
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    if exports['ty-menu']:IsOpen() then
        exports['ty-menu']:CloseMenu(true)
    end

    if TYAdminClient.ResetEffects then
        TYAdminClient.ResetEffects()
    end
end)

exports('HasPermission', TYAdminClient.HasPermission)

print('[ty-admin][CLIENT] Geladen. Das Menü bleibt bis zu einer berechtigten F9-Anfrage unsichtbar.')
