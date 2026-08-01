TYAdminClient.Menus = TYAdminClient.Menus or {}

local Menus = TYAdminClient.Menus
local CALLBACK_EVENT = 'ty-admin:client:menuCallback'
local callbackRegistry = {}
local callbackCounter = 0
local prepareMenu
local push

local function notify(message)
    exports['ty-menu']:Notify(message)
end

local function has(permission)
    return TYAdminClient.HasPermission and TYAdminClient.HasPermission(permission) or false
end

local function secured(permission, item)
    if not has(permission) then
        item.locked = true
        item.disabled = true
        item.lockReason = ('Gesperrt: %s'):format(permission)
    end
    return item
end

local function clearCallbacks()
    callbackRegistry = {}
end

local function registerCallback(callback)
    if type(callback) ~= 'function' then
        return nil
    end

    callbackCounter = callbackCounter + 1
    local callbackId = ('%d:%d'):format(GetGameTimer(), callbackCounter)
    callbackRegistry[callbackId] = callback
    return callbackId
end

local function attachClientEvent(target, callback)
    local callbackId = registerCallback(callback)
    if not callbackId then
        return false
    end

    target.clientEvent = CALLBACK_EVENT
    target.payload = { callbackId = callbackId }
    return true
end

prepareMenu = function(menu, seen)
    if type(menu) ~= 'table' then
        return menu
    end

    seen = seen or {}
    if seen[menu] then
        return menu
    end
    seen[menu] = true

    if type(menu.onClose) == 'function' then
        local onClose = menu.onClose
        menu.onClose = nil
        local callbackId = registerCallback(function()
            onClose()
        end)
        menu.closeEvent = CALLBACK_EVENT
        menu.closePayload = { callbackId = callbackId }
    end

    if type(menu.onSearch) == 'function' then
        local onSearch = menu.onSearch
        menu.onSearch = nil
        local callbackId = registerCallback(function(context)
            onSearch(tostring(context.value or ''), menu)
        end)
        menu.searchEvent = CALLBACK_EVENT
        menu.searchPayload = { callbackId = callbackId }
    end

    if type(menu.onSelect) == 'function' then
        local onSelect = menu.onSelect
        menu.onSelect = nil
        attachClientEvent(menu, function(context)
            onSelect(nil, tonumber(context.originalIndex) or 0, menu)
        end)
    end

    for index = 1, #(menu.items or {}) do
        local originalIndex = index
        local item = menu.items[index]
        if type(item) == 'table' then
            if type(item.submenu) == 'table' then
                prepareMenu(item.submenu, seen)
            elseif type(item.submenu) == 'function' then
                local submenuFactory = item.submenu
                item.submenu = nil
                item.onSelect = function()
                    local submenu = submenuFactory(item)
                    if type(submenu) == 'table' then
                        push(submenu)
                    end
                end
            end

            if type(item.onToggle) == 'function' then
                local onToggle = item.onToggle
                item.onToggle = nil
                attachClientEvent(item, function(context)
                    onToggle(context.value == true, item)
                end)
            elseif type(item.onSelect) == 'function' then
                local onSelect = item.onSelect
                item.onSelect = nil
                attachClientEvent(item, function(context)
                    onSelect(item, tonumber(context.originalIndex) or originalIndex, menu)
                end)
            end
        end
    end

    return menu
end

push = function(menu)
    return exports['ty-menu']:PushMenu(prepareMenu(menu))
end

local function replace(menu)
    return exports['ty-menu']:ReplaceCurrent(prepareMenu(menu))
end

local function open(menu)
    return exports['ty-menu']:OpenMenu(prepareMenu(menu))
end

local function prompt(options, callback)
    options = type(options) == 'table' and options or {}
    local callbackId = registerCallback(function(context)
        callback(tostring(context.value or ''))
    end)
    options.submitEvent = CALLBACK_EVENT
    options.submitPayload = { callbackId = callbackId }
    return exports['ty-menu']:Prompt(options)
end

AddEventHandler(CALLBACK_EVENT, function(payload, context)
    local callbackId = type(payload) == 'table' and tostring(payload.callbackId or '') or ''
    local callback = callbackRegistry[callbackId]
    if type(callback) ~= 'function' then
        print(('[ty-admin][MENÜ-FEHLER] Unbekannte oder abgelaufene Callback-ID: %s'):format(callbackId))
        notify('Die Adminmenü-Aktion ist nicht mehr gültig. Öffne das Menü bitte erneut.')
        return
    end

    local success, errorMessage = pcall(callback, type(context) == 'table' and context or {})
    if not success then
        print(('[ty-admin][MENÜ-CALLBACK-FEHLER] %s'):format(errorMessage))
        notify('Die Adminmenü-Aktion ist fehlgeschlagen. Weitere Details stehen in der F8-Konsole.')
    end
end)

AddEventHandler('ty-menu:client:closed', function(owner)
    if owner ~= GetCurrentResourceName() then
        return
    end

    TYAdminClient.MenuOpen = false
    clearCallbacks()
end)

local function action(actionName, payload)
    TYAdminClient.Action(actionName, payload or {})
end

local function round(value, decimals)
    local factor = 10 ^ (decimals or 0)
    return math.floor((tonumber(value) or 0) * factor + 0.5) / factor
end

local function formatPosition(position)
    position = type(position) == 'table' and position or {}
    return ('%.2f, %.2f, %.2f / %.2f°'):format(
        tonumber(position.x) or 0.0,
        tonumber(position.y) or 0.0,
        tonumber(position.z) or 0.0,
        tonumber(position.w) or 0.0
    )
end

local function askReason(title, callback)
    prompt({
        title = title,
        label = 'Begründung',
        placeholder = 'Begründung eingeben',
        maxLength = ConfigAdmin.MaxReasonLength,
        hint = 'Enter bestätigen · ESC abbrechen'
    }, function(reason)
        reason = tostring(reason or '')
        if #reason < 3 then
            notify('Die Begründung muss mindestens 3 Zeichen enthalten.')
            return
        end
        callback(reason)
    end)
end

local function toggleItem(id, label, icon, permission, stateKey, actionName, description)
    return secured(permission, {
        id = id,
        label = label,
        icon = icon,
        type = 'toggle',
        value = TYAdminClient.State[stateKey] == true,
        description = description,
        onToggle = function(enabled)
            action(actionName or stateKey, { enabled = enabled })
        end
    })
end

local function openDevelopmentMenu()
    push({
        id = 'ty_admin_development',
        title = ConfigAdmin.MenuTitle,
        breadcrumb = 'ADMIN FUNKTIONEN > DEVELOPMENT MODE',
        footer = 'Andere Resources prüfen exports["ty-admin"]:IsDevelopmentMode()',
        items = {
            toggleItem('development', 'Development Mode', 'code', 'development.toggle', 'developmentMode', 'developmentMode', 'Globaler Bypass-Status für zukünftige TY-Resources'),
            toggleItem('coordinates', 'Koordinaten anzeigen', 'pin', 'self.coordinates', 'coordinates', 'coordinates'),
            toggleItem('vehicledata', 'Fahrzeugdaten anzeigen', 'car', 'self.vehicledata', 'vehicledata', 'vehicledata'),
            secured('world.weather', {
                id = 'entities',
                label = 'Entities anzeigen',
                icon = 'eye',
                description = 'Adapter für spätere Entity-Debug-Resource',
                onSelect = function() notify('Entity-Debug ist vorbereitet und folgt mit einer späteren Development-Resource.') end
            })
        }
    })
end

local function openAdminFunctions()
    push({
        id = 'ty_admin_functions',
        title = ConfigAdmin.MenuTitle,
        breadcrumb = 'ADMIN FUNKTIONEN',
        items = {
            toggleItem('adminmode', 'Admin Mode', 'shield', 'admin.mode', 'adminMode', 'adminMode', 'Status für HUD und andere Resources'),
            secured('self.heal', {
                id = 'heal_self', label = 'Selbst heilen', icon = 'heart',
                onSelect = function() action('healSelf') end
            }),
            secured('self.revive', {
                id = 'revive_self', label = 'Selbst wiederbeleben', icon = 'activity',
                onSelect = function() action('reviveSelf') end
            }),
            toggleItem('nametags', 'Nametags', 'users', 'self.nametags', 'nametags', 'nametags'),
            toggleItem('invisible', 'Unsichtbar', 'eyeoff', 'self.invisible', 'invisible', 'invisible'),
            toggleItem('godmode', 'Godmode', 'shield', 'self.godmode', 'godmode', 'godmode'),
            toggleItem('noclip', 'Flugmodus / Noclip', 'fly', 'self.noclip', 'noclip', 'noclip'),
            toggleItem('thermal', 'Thermalsicht', 'eye', 'self.thermal', 'thermal', 'thermal'),
            secured('self.teleport_waypoint', {
                id = 'waypoint', label = 'Zum Wegpunkt teleportieren', icon = 'map',
                onSelect = function() action('teleportWaypoint') end
            }),
            secured('world.weather', {
                id = 'weather', label = 'Wetter & Tageszeit', icon = 'sun',
                description = 'Für spätere synchronisierte Welt-Resource vorbereitet',
                onSelect = function() action('weather') end
            }),
            secured('world.power', {
                id = 'power', label = 'Stromnetz', icon = 'activity',
                description = 'Für spätere Stromnetz-Resource vorbereitet',
                onSelect = function() action('power') end
            }),
            secured('development.toggle', {
                id = 'development_menu', label = 'Development Mode', icon = 'code',
                description = 'Bypass-Status, Koordinaten und Debugdaten',
                onSelect = openDevelopmentMenu
            })
        }
    })
end

local function informationMenu(player)
    local rows = {
        { label = 'Name', value = player.name, icon = 'user' },
        { label = 'Feste ID', value = player.playerId, icon = 'shield' },
        { label = 'Server-ID', value = player.source, icon = 'info' },
        { label = 'Account-ID', value = player.accountId, icon = 'info' },
        { label = 'Charakter-ID', value = player.characterId, icon = 'info' },
        { label = 'Position', value = formatPosition(player.position), icon = 'pin' },
        { label = 'Routing Bucket', value = player.routingBucket, icon = 'layers' },
        { label = 'Leben', value = player.health, icon = 'heart' },
        { label = 'Rüstung', value = player.armor, icon = 'shield' },
        { label = 'Bargeld', value = player.cash, icon = 'money' },
        { label = 'Bank', value = player.bank, icon = 'bank' },
        { label = 'Job', value = player.job, icon = 'briefcase' },
        { label = 'Gang', value = player.gang, icon = 'gang' },
        { label = 'Essen', value = player.hunger, icon = 'food' },
        { label = 'Trinken', value = player.thirst, icon = 'droplet' }
    }
    local items = {}

    for index = 1, #rows do
        items[#items + 1] = {
            id = ('info_%d'):format(index),
            label = ('%s: %s'):format(rows[index].label, rows[index].value),
            icon = rows[index].icon,
            type = 'info'
        }
    end

    return {
        id = ('ty_admin_player_info_%d'):format(player.source),
        title = player.name,
        breadcrumb = 'SPIELER > INFORMATIONEN',
        items = items
    }
end

local function openBanDurations(player)
    local items = {}

    for index = 1, #ConfigAdmin.BanDurations do
        local duration = ConfigAdmin.BanDurations[index]
        items[#items + 1] = {
            id = ('ban_%d'):format(index),
            label = duration.label,
            icon = 'ban',
            onSelect = function()
                askReason(('Bann: %s'):format(player.name), function(reason)
                    action('banPlayer', {
                        target = player.source,
                        duration = duration.seconds,
                        reason = reason
                    })
                end)
            end
        }
    end

    items[#items + 1] = {
        id = 'ban_custom',
        label = 'Eigene Dauer in Stunden',
        icon = 'sun',
        onSelect = function()
            prompt({
                title = 'Eigene Banndauer',
                label = 'Stunden',
                placeholder = 'z. B. 12',
                inputType = 'number',
                maxLength = 5
            }, function(hours)
                hours = math.floor(tonumber(hours) or 0)
                if hours < 1 or hours > 8760 then
                    notify('Erlaubt sind 1 bis 8760 Stunden.')
                    return
                end
                askReason(('Bann: %s'):format(player.name), function(reason)
                    action('banPlayer', { target = player.source, duration = hours * 3600, reason = reason })
                end)
            end)
        end
    }

    push({
        id = ('ty_admin_ban_%d'):format(player.source),
        title = player.name,
        breadcrumb = 'SPIELER > SICHERHEIT > BANNEN',
        items = items
    })
end

local function openSecurityMenu(player)
    push({
        id = ('ty_admin_security_%d'):format(player.source),
        title = player.name,
        breadcrumb = 'SPIELER > SICHERHEIT',
        items = {
            secured('players.kick', {
                id = 'kick', label = 'Spieler kicken', icon = 'kick',
                onSelect = function()
                    askReason(('Kick: %s'):format(player.name), function(reason)
                        action('kickPlayer', { target = player.source, reason = reason })
                    end)
                end
            }),
            secured('players.ban', {
                id = 'ban', label = 'Spieler bannen', icon = 'ban',
                description = 'Dauer und Begründung auswählen',
                onSelect = function() openBanDurations(player) end
            })
        }
    })
end

local openItemsMenu

local function openPlayerMenu(player)
    push({
        id = ('ty_admin_player_%d'):format(player.source),
        title = player.name,
        subtitle = ('Feste ID %d · Source %d'):format(player.playerId, player.source),
        breadcrumb = 'SPIELER > AKTIONEN',
        items = {
            secured('players.details', {
                id = 'information', label = 'Informationen', icon = 'info',
                submenu = informationMenu(player)
            }),
            secured('players.heal', {
                id = 'heal', label = 'Heilen', icon = 'heart',
                onSelect = function() action('healPlayer', { target = player.source }) end
            }),
            secured('players.revive', {
                id = 'revive', label = 'Wiederbeleben', icon = 'activity',
                onSelect = function() action('revivePlayer', { target = player.source }) end
            }),
            secured('players.goto', {
                id = 'goto', label = 'Zum Spieler teleportieren', icon = 'teleport',
                onSelect = function() action('gotoPlayer', { target = player.source }) end
            }),
            secured('players.bring', {
                id = 'bring', label = 'Spieler zu mir teleportieren', icon = 'pin',
                onSelect = function() action('bringPlayer', { target = player.source }) end
            }),
            secured('players.spectate', {
                id = 'spectate', label = 'Beobachten / Spectate', icon = 'eye',
                onSelect = function() action('spectatePlayer', { target = player.source }) end
            }),
            secured('players.freeze', {
                id = 'freeze', label = 'Einfrieren', icon = 'snowflake', type = 'toggle',
                value = player.frozen == true,
                onToggle = function(enabled) action('freezePlayer', { target = player.source, enabled = enabled }) end
            }),
            secured('players.give_item', {
                id = 'give_item', label = 'Item geben', icon = 'box',
                locked = not has('items.give'),
                disabled = not has('items.give'),
                lockReason = 'Items geben ist für diese Rolle gesperrt.',
                onSelect = function() openItemsMenu(player.source, player.name) end
            }),
            {
                id = 'security', label = 'Sicherheit', icon = 'shield',
                locked = not has('players.kick') and not has('players.ban'),
                disabled = not has('players.kick') and not has('players.ban'),
                onSelect = function() openSecurityMenu(player) end
            }
        }
    })
end

local function buildPlayerList(players)
    local items = {
        {
            id = 'refresh_players',
            label = 'Spielerliste aktualisieren',
            icon = 'refresh',
            onSelect = function() Menus.OpenPlayers(true) end
        }
    }

    for index = 1, #players do
        local player = players[index]
        items[#items + 1] = {
            id = ('player_%d'):format(player.source),
            label = ('[%d] %s'):format(player.playerId, player.name),
            description = ('Source %d · Bucket %d'):format(player.source, player.routingBucket),
            icon = 'user',
            tags = { player.name, tostring(player.playerId), tostring(player.source) },
            tooltip = {
                title = player.name,
                description = 'Aktiver Spieler auf dem Server',
                rows = {
                    { icon = 'heart', label = 'Leben', value = player.health },
                    { icon = 'shield', label = 'Rüstung', value = player.armor },
                    { icon = 'briefcase', label = 'Job', value = player.job },
                    { icon = 'gang', label = 'Gang', value = player.gang },
                    { icon = 'money', label = 'Bargeld', value = player.cash },
                    { icon = 'bank', label = 'Bank', value = player.bank },
                    { icon = 'food', label = 'Essen', value = player.hunger },
                    { icon = 'droplet', label = 'Trinken', value = player.thirst },
                    { icon = 'layers', label = 'Dimension', value = player.routingBucket },
                    { icon = 'pin', label = 'Position', value = formatPosition(player.position) }
                }
            },
            onSelect = function() openPlayerMenu(player) end
        }
    end

    return {
        id = 'ty_admin_players',
        title = ConfigAdmin.MenuTitle,
        subtitle = ('%d aktive Spieler'):format(#players),
        breadcrumb = 'SPIELER',
        search = {
            label = 'Spieler suchen',
            placeholder = 'Name, feste ID oder Source'
        },
        items = items
    }
end

function Menus.OpenPlayers(replace)
    TYAdminClient.Request('players', function(success, payload, errorMessage)
        if not success then notify(errorMessage or 'Spielerliste konnte nicht geladen werden.') return end
        local menu = buildPlayerList(payload.players or {})
        if replace then replace(menu) else push(menu) end
    end)
end

local function itemTooltip(item)
    local rows = {
        { icon = 'box', label = 'Interner Name', value = item.name },
        { icon = 'layers', label = 'Kategorie', value = item.category },
        { icon = 'info', label = 'Typ', value = item.itemType },
        { icon = 'wrench', label = 'Benutzbar', value = item.usable and 'Ja' or 'Nein' }
    }

    local count = 0
    for key, value in pairs(item.metadata or {}) do
        count = count + 1
        if count > 5 then break end
        rows[#rows + 1] = { icon = 'info', label = tostring(key), value = tostring(value) }
    end

    return {
        title = item.label,
        description = item.description ~= '' and item.description or 'Keine Beschreibung hinterlegt.',
        rows = rows
    }
end

openItemsMenu = function(targetSource, targetName)
    TYAdminClient.Request('items', function(success, payload, errorMessage)
        if not success then notify(errorMessage or 'Items konnten nicht geladen werden.') return end

        local items = {}
        if not payload.available then
            items[1] = {
                id = 'no_adapter',
                label = 'Kein Itemsystem verbunden',
                description = 'Eine Inventar-Resource muss RegisterItemAdapter verwenden.',
                icon = 'lock',
                disabled = true,
                tooltip = {
                    title = 'Vorbereitete Schnittstelle',
                    description = 'Sobald ty-inventory oder eine andere Resource den Adapter registriert, erscheinen hier alle Items dynamisch.',
                    rows = {}
                }
            }
        else
            for index = 1, #(payload.items or {}) do
                local item = payload.items[index]
                items[#items + 1] = {
                    id = ('item_%s'):format(item.name),
                    label = item.label,
                    description = item.name,
                    icon = 'box',
                    tags = { item.name, item.category, item.itemType },
                    tooltip = itemTooltip(item),
                    disabled = not has('items.give'),
                    locked = not has('items.give'),
                    onSelect = function()
                        prompt({
                            title = ('%s geben'):format(item.label),
                            label = 'Menge',
                            placeholder = '1',
                            value = '1',
                            inputType = 'number',
                            maxLength = 4
                        }, function(value)
                            local amount = math.floor(tonumber(value) or 0)
                            if amount < 1 or amount > ConfigAdmin.MaxItemAmount then
                                notify(('Menge muss zwischen 1 und %d liegen.'):format(ConfigAdmin.MaxItemAmount))
                                return
                            end
                            action('giveItem', {
                                target = targetSource or GetPlayerServerId(PlayerId()),
                                item = item.name,
                                amount = amount
                            })
                        end)
                    end
                }
            end
        end

        push({
            id = 'ty_admin_items',
            title = ConfigAdmin.MenuTitle,
            subtitle = targetName and ('Empfänger: %s'):format(targetName) or 'Empfänger: Du selbst',
            breadcrumb = 'ITEMS',
            search = {
                label = 'Item suchen',
                placeholder = 'Name, Kategorie oder Typ'
            },
            items = items
        })
    end)
end

Menus.OpenItems = openItemsMenu

local function vehicleTooltip(vehicle)
    return {
        title = ('%s · %s'):format(vehicle.label, vehicle.plate),
        description = vehicle.category,
        rows = {
            { icon = 'car', label = 'Modell', value = vehicle.model },
            { icon = 'pin', label = 'Position', value = formatPosition(vehicle.position) },
            { icon = 'rotate', label = 'Rotation', value = ('%.1f, %.1f, %.1f'):format(vehicle.rotation.x, vehicle.rotation.y, vehicle.rotation.z) },
            { icon = 'fuel', label = 'Tank', value = ('%.1f'):format(vehicle.fuel) },
            { icon = 'activity', label = 'Motor', value = ('%.0f'):format(vehicle.engineHealth) },
            { icon = 'shield', label = 'Karosserie', value = ('%.0f'):format(vehicle.bodyHealth) },
            { icon = 'layers', label = 'Dimension', value = vehicle.routingBucket },
            { icon = 'info', label = 'Netzwerk-ID', value = vehicle.networkId }
        }
    }
end

local function openVehicleDetails(vehicle)
    push({
        id = ('ty_admin_vehicle_%d'):format(vehicle.networkId),
        title = vehicle.plate,
        subtitle = vehicle.label,
        breadcrumb = 'FAHRZEUGE > AKTIVES FAHRZEUG',
        items = {
            {
                id = 'vehicle_info', label = 'Fahrzeuginformationen', icon = 'info', type = 'info',
                tooltip = vehicleTooltip(vehicle)
            },
            secured('vehicles.teleport', {
                id = 'teleport', label = 'Zum Fahrzeug teleportieren', icon = 'teleport',
                onSelect = function() action('teleportVehicle', { networkId = vehicle.networkId }) end
            }),
            secured('vehicles.repair', {
                id = 'repair', label = 'Reparieren', icon = 'wrench',
                onSelect = function() action('repairVehicle', { networkId = vehicle.networkId }) end
            }),
            secured('vehicles.wash', {
                id = 'wash', label = 'Waschen', icon = 'droplet',
                onSelect = function() action('washVehicle', { networkId = vehicle.networkId }) end
            }),
            secured('vehicles.flip', {
                id = 'flip', label = 'Aufrichten / Flippen', icon = 'rotate',
                onSelect = function() action('flipVehicle', { networkId = vehicle.networkId }) end
            }),
            secured('vehicles.godmode', {
                id = 'vehicle_godmode', label = 'Fahrzeug-Godmode', icon = 'shield', type = 'toggle', value = vehicle.godmode,
                onToggle = function(enabled) action('godmodeVehicle', { networkId = vehicle.networkId, enabled = enabled }) end
            }),
            secured('vehicles.park', {
                id = 'park', label = 'Einparken', icon = 'garage',
                description = 'Benötigt später ty-garage',
                onSelect = function() action('parkVehicle', { networkId = vehicle.networkId }) end
            }),
            secured('vehicles.reload', {
                id = 'reload', label = 'Neu laden', icon = 'refresh',
                description = 'Benötigt später ty-garage',
                onSelect = function() action('reloadVehicle', { networkId = vehicle.networkId }) end
            }),
            secured('vehicles.claim', {
                id = 'claim', label = 'Fahrzeug beanspruchen', icon = 'copy',
                description = 'Benötigt später Fahrzeugbesitz',
                onSelect = function() action('claimVehicle', { networkId = vehicle.networkId }) end
            }),
            secured('vehicles.key', {
                id = 'key', label = 'Schlüssel erstellen', icon = 'key',
                description = 'Benötigt später ty-vehiclekeys und Inventar',
                onSelect = function() action('createVehicleKey', { networkId = vehicle.networkId }) end
            }),
            secured('vehicles.delete', {
                id = 'delete', label = 'Fahrzeug löschen', icon = 'trash',
                onSelect = function() action('deleteVehicle', { networkId = vehicle.networkId }) end
            })
        }
    })
end

local function buildActiveVehicles(vehicles)
    local items = {
        {
            id = 'refresh_vehicles', label = 'Aktive Fahrzeuge aktualisieren', icon = 'refresh',
            onSelect = function() Menus.OpenActiveVehicles(true) end
        }
    }

    for index = 1, #vehicles do
        local vehicle = vehicles[index]
        items[#items + 1] = {
            id = ('vehicle_%d'):format(vehicle.networkId),
            label = ('%s · %s'):format(vehicle.plate, vehicle.label),
            description = ('Net %d · Bucket %d'):format(vehicle.networkId, vehicle.routingBucket),
            icon = 'car',
            tags = { vehicle.plate, vehicle.model, vehicle.label, tostring(vehicle.networkId) },
            tooltip = vehicleTooltip(vehicle),
            onSelect = function() openVehicleDetails(vehicle) end
        }
    end

    return {
        id = 'ty_admin_active_vehicles',
        title = ConfigAdmin.MenuTitle,
        subtitle = ('%d aktive Fahrzeuge'):format(#vehicles),
        breadcrumb = 'FAHRZEUGE > AKTIV',
        search = {
            label = 'Fahrzeug suchen',
            placeholder = 'Kennzeichen, Modell oder Netzwerk-ID'
        },
        items = items
    }
end

function Menus.OpenActiveVehicles(replace)
    TYAdminClient.Request('vehicles', function(success, payload, errorMessage)
        if not success then notify(errorMessage or 'Fahrzeuge konnten nicht geladen werden.') return end
        local menu = buildActiveVehicles(payload.vehicles or {})
        if replace then replace(menu) else push(menu) end
    end)
end

local function vehicleModelItem(vehicle)
    return {
        id = ('spawn_%s'):format(vehicle.model),
        label = vehicle.label,
        description = vehicle.model,
        icon = 'car',
        tags = { vehicle.model, vehicle.label },
        tooltip = {
            title = vehicle.label,
            description = 'Fahrzeug aus dem serverseitig freigegebenen Katalog',
            rows = {
                { icon = 'car', label = 'Spawnname', value = vehicle.model },
                { icon = 'layers', label = 'Entity-Typ', value = vehicle.type or 'automobile' }
            }
        },
        onSelect = function() action('spawnVehicle', { model = vehicle.model }) end
    }
end

local function openVehicleCategory(category)
    local items = {}
    for index = 1, #category.vehicles do
        items[#items + 1] = vehicleModelItem(category.vehicles[index])
    end

    push({
        id = ('ty_admin_spawn_%s'):format(category.id),
        title = category.label,
        breadcrumb = 'FAHRZEUGE > SPAWNEN',
        search = { label = 'Fahrzeug suchen', placeholder = 'Name oder Spawnname' },
        items = items
    })
end

local function openAllVehicleModels()
    local items = {}
    for categoryIndex = 1, #ConfigAdmin.VehicleCategories do
        local category = ConfigAdmin.VehicleCategories[categoryIndex]
        for vehicleIndex = 1, #category.vehicles do
            local item = vehicleModelItem(category.vehicles[vehicleIndex])
            item.description = ('%s · %s'):format(category.label, item.description)
            item.tags[#item.tags + 1] = category.label
            items[#items + 1] = item
        end
    end

    push({
        id = 'ty_admin_spawn_all',
        title = 'FAHRZEUG SPAWNEN',
        breadcrumb = 'FAHRZEUGE > ALLE MODELLE',
        search = { label = 'Fahrzeug suchen', placeholder = 'Klasse, Name oder Spawnname' },
        items = items
    })
end

local function openVehicleSpawner()
    local items = {
        {
            id = 'all_models', label = 'Alle Fahrzeuge durchsuchen', icon = 'search',
            onSelect = openAllVehicleModels
        }
    }

    for index = 1, #ConfigAdmin.VehicleCategories do
        local category = ConfigAdmin.VehicleCategories[index]
        local names = {}
        for vehicleIndex = 1, #category.vehicles do names[#names + 1] = category.vehicles[vehicleIndex].model end
        items[#items + 1] = {
            id = category.id,
            label = category.label,
            description = ('%d Fahrzeuge'):format(#category.vehicles),
            searchText = table.concat(names, ' '),
            icon = 'car',
            onSelect = function() openVehicleCategory(category) end
        }
    end

    push({
        id = 'ty_admin_vehicle_spawner',
        title = 'FAHRZEUG SPAWNEN',
        breadcrumb = 'FAHRZEUGE > KLASSEN',
        search = { label = 'Klasse suchen', placeholder = 'Klasse oder Fahrzeugmodell' },
        items = items
    })
end

local function nearestVehicleAction(actionName)
    local networkId = TYAdminClient.GetNearestVehicleNetworkId(10.0)
    if not networkId then
        notify('Kein aktives Fahrzeug in der Nähe gefunden.')
        return
    end
    action(actionName, { networkId = networkId })
end

local function openVehicleMenu()
    push({
        id = 'ty_admin_vehicles',
        title = ConfigAdmin.MenuTitle,
        breadcrumb = 'FAHRZEUGE',
        items = {
            secured('vehicles.view', {
                id = 'active', label = 'Aktive Fahrzeuge suchen', icon = 'search',
                description = 'Suche auch direkt über Kennzeichen',
                onSelect = function() Menus.OpenActiveVehicles(false) end
            }),
            secured('vehicles.search', {
                id = 'stored', label = 'Gespeicherte Fahrzeuge', icon = 'garage',
                description = 'Adapter für ty-garage vorbereitet',
                onSelect = function() Menus.OpenStoredVehicles() end
            }),
            secured('vehicles.spawn', {
                id = 'spawn', label = 'Fahrzeug spawnen', icon = 'plus',
                onSelect = openVehicleSpawner
            }),
            secured('vehicles.repair', {
                id = 'nearest_repair', label = 'Nächstes Fahrzeug reparieren', icon = 'wrench',
                onSelect = function() nearestVehicleAction('repairVehicle') end
            }),
            secured('vehicles.wash', {
                id = 'nearest_wash', label = 'Nächstes Fahrzeug waschen', icon = 'droplet',
                onSelect = function() nearestVehicleAction('washVehicle') end
            }),
            secured('vehicles.flip', {
                id = 'nearest_flip', label = 'Nächstes Fahrzeug aufrichten', icon = 'rotate',
                onSelect = function() nearestVehicleAction('flipVehicle') end
            }),
            secured('vehicles.park', {
                id = 'nearest_park', label = 'Nächstes Fahrzeug einparken', icon = 'garage',
                description = 'Adapter für ty-garage vorbereitet',
                onSelect = function() nearestVehicleAction('parkVehicle') end
            })
        }
    })
end

function Menus.OpenStoredVehicles()
    TYAdminClient.Request('storedVehicles', function(success, payload, errorMessage)
        if not success then notify(errorMessage or 'Garagenfahrzeuge konnten nicht geladen werden.') return end

        local items = {}
        if not payload.available then
            items[1] = {
                id = 'no_garage_adapter',
                label = 'Keine Garage verbunden',
                description = 'ty-garage kann später RegisterVehicleAdapter verwenden.',
                icon = 'lock',
                disabled = true
            }
        else
            for index = 1, #(payload.vehicles or {}) do
                local vehicle = payload.vehicles[index]
                items[#items + 1] = {
                    id = ('stored_%s'):format(vehicle.id),
                    label = ('%s · %s'):format(vehicle.plate, vehicle.label),
                    description = ('Garage: %s'):format(vehicle.garage),
                    icon = 'garage',
                    tags = { vehicle.plate, vehicle.model, vehicle.label, vehicle.owner, vehicle.garage },
                    tooltip = {
                        title = vehicle.plate,
                        description = 'Gespeicherter Datensatz aus dem registrierten Garagenadapter',
                        rows = {
                            { icon = 'car', label = 'Modell', value = vehicle.model },
                            { icon = 'garage', label = 'Garage', value = vehicle.garage },
                            { icon = 'user', label = 'Besitzer', value = vehicle.owner },
                            { icon = 'info', label = 'Status', value = vehicle.stored and 'Eingeparkt' or 'Ausgeparkt' }
                        }
                    },
                    onSelect = function()
                        push({
                            id = ('stored_actions_%s'):format(vehicle.id),
                            title = vehicle.plate,
                            breadcrumb = 'FAHRZEUGE > GARAGE',
                            items = {
                                secured('vehicles.reload', {
                                    id = 'reload', label = 'Neu laden / ausparken', icon = 'refresh',
                                    onSelect = function() action('reloadVehicle', { storedId = vehicle.id, plate = vehicle.plate }) end
                                }),
                                secured('vehicles.claim', {
                                    id = 'claim', label = 'Besitz übernehmen', icon = 'copy',
                                    onSelect = function() action('claimVehicle', { storedId = vehicle.id, plate = vehicle.plate }) end
                                }),
                                secured('vehicles.key', {
                                    id = 'key', label = 'Schlüssel erstellen', icon = 'key',
                                    onSelect = function() action('createVehicleKey', { storedId = vehicle.id, plate = vehicle.plate }) end
                                })
                            }
                        })
                    end
                }
            end
        end

        push({
            id = 'ty_admin_stored_vehicles',
            title = ConfigAdmin.MenuTitle,
            breadcrumb = 'FAHRZEUGE > GARAGE',
            search = { label = 'Gespeichertes Fahrzeug suchen', placeholder = 'Kennzeichen, Besitzer oder Garage' },
            items = items
        })
    end)
end

function Menus.OpenRoot()
    clearCallbacks()
    open({
        id = 'ty_admin_root',
        title = ConfigAdmin.MenuTitle,
        subtitle = TYAdminClient.Authorization.roleLabel,
        breadcrumb = 'ADMINISTRATION',
        footer = 'F9 Schließen · Pfeiltasten · Enter · Backspace',
        onClose = function() TYAdminClient.MenuOpen = false end,
        items = {
            secured('admin.mode', {
                id = 'admin', label = 'Admin Funktionen', icon = 'shield',
                onSelect = openAdminFunctions
            }),
            secured('players.view', {
                id = 'players', label = 'Spieler', icon = 'users',
                onSelect = function() Menus.OpenPlayers(false) end
            }),
            secured('vehicles.view', {
                id = 'vehicles', label = 'Fahrzeuge', icon = 'car',
                onSelect = openVehicleMenu
            }),
            secured('items.view', {
                id = 'items', label = 'Items', icon = 'box',
                onSelect = function() openItemsMenu(nil, nil) end
            })
        }
    })
    TYAdminClient.MenuOpen = true
end
