TYAdmin.Adapters = TYAdmin.Adapters or {
    Items = nil,
    Vehicles = nil
}

local Adapters = TYAdmin.Adapters

local function debugPrepared(feature)
    if ConfigAdmin.Debug or ConfigAdmin.PrintPreparedFeatures then
        print(('[ty-admin][VORBEREITET] %s ist vorbereitet, aber noch nicht durch eine andere Resource implementiert.'):format(feature))
    end
end

local function sanitizeItem(item)
    if type(item) ~= 'table' or type(item.name) ~= 'string' or item.name == '' then
        return nil
    end

    return {
        name = item.name:sub(1, 64),
        label = tostring(item.label or item.name):sub(1, 96),
        description = tostring(item.description or ''):sub(1, 512),
        category = tostring(item.category or 'Sonstiges'):sub(1, 64),
        itemType = tostring(item.itemType or item.type or 'item'):sub(1, 48),
        usable = item.usable == true,
        image = item.image and tostring(item.image):sub(1, 160) or nil,
        metadata = type(item.metadata) == 'table' and item.metadata or {}
    }
end

function Adapters.RegisterItems(resourceName, adapter)
    if adapter == nil and type(resourceName) == 'table' then
        adapter = resourceName
        resourceName = GetInvokingResource()
    end

    if type(adapter) ~= 'table' or type(adapter.GetItems) ~= 'function' or type(adapter.GiveItem) ~= 'function' then
        return false, 'Der Item-Adapter benoetigt GetItems und GiveItem.'
    end

    Adapters.Items = {
        resource = tostring(resourceName or GetInvokingResource() or 'unbekannt'),
        GetItems = adapter.GetItems,
        GiveItem = adapter.GiveItem
    }

    print(('[ty-admin][ADAPTER] Itemsystem von %s registriert.'):format(Adapters.Items.resource))
    return true
end

function Adapters.GetItems()
    if not Adapters.Items then
        debugPrepared('Items suchen und geben')
        return false, {}
    end

    local success, items = pcall(Adapters.Items.GetItems)
    if not success or type(items) ~= 'table' then
        print(('[ty-admin][ADAPTER-FEHLER] GetItems (%s): %s'):format(Adapters.Items.resource, tostring(items)))
        return false, {}
    end

    local sanitized = {}
    for index = 1, #items do
        local item = sanitizeItem(items[index])
        if item then
            sanitized[#sanitized + 1] = item
        end
    end

    table.sort(sanitized, function(left, right)
        return left.label:lower() < right.label:lower()
    end)

    return true, sanitized
end

function Adapters.GiveItem(targetSource, itemName, amount, metadata)
    if not Adapters.Items then
        debugPrepared('Item geben')
        return false, 'Kein Inventar-/Itemsystem hat einen Adapter registriert.'
    end

    local success, result, errorMessage = pcall(
        Adapters.Items.GiveItem,
        targetSource,
        itemName,
        amount,
        metadata or {}
    )

    if not success then
        return false, tostring(result)
    end

    return result == true, errorMessage
end

function Adapters.RegisterVehicles(resourceName, adapter)
    if adapter == nil and type(resourceName) == 'table' then
        adapter = resourceName
        resourceName = GetInvokingResource()
    end

    if type(adapter) ~= 'table' then
        return false, 'Der Fahrzeug-Adapter muss eine Tabelle sein.'
    end

    Adapters.Vehicles = {
        resource = tostring(resourceName or GetInvokingResource() or 'unbekannt'),
        SearchStored = adapter.SearchStored,
        Park = adapter.Park,
        Reload = adapter.Reload,
        Claim = adapter.Claim,
        CreateKey = adapter.CreateKey
    }

    print(('[ty-admin][ADAPTER] Fahrzeugsystem von %s registriert.'):format(Adapters.Vehicles.resource))
    return true
end

function Adapters.CallVehicle(operation, ...)
    if not Adapters.Vehicles or type(Adapters.Vehicles[operation]) ~= 'function' then
        debugPrepared(('Fahrzeugfunktion %s'):format(operation))
        return false, ('%s ist vorbereitet, aber noch nicht mit Garage/Besitz/Schluesseln verbunden.'):format(operation)
    end

    local success, result, errorMessage = pcall(Adapters.Vehicles[operation], ...)
    if not success then
        return false, tostring(result)
    end

    return result == true, errorMessage
end

function Adapters.SearchStored(searchText)
    if not Adapters.Vehicles or type(Adapters.Vehicles.SearchStored) ~= 'function' then
        debugPrepared('Gespeicherte Fahrzeuge durchsuchen')
        return false, {}
    end

    local success, vehicles = pcall(Adapters.Vehicles.SearchStored, tostring(searchText or ''))
    if not success or type(vehicles) ~= 'table' then
        print(('[ty-admin][ADAPTER-FEHLER] SearchStored: %s'):format(tostring(vehicles)))
        return false, {}
    end

    local result = {}
    for index = 1, #vehicles do
        local vehicle = vehicles[index]
        if type(vehicle) == 'table' and (vehicle.id ~= nil or vehicle.plate ~= nil) then
            result[#result + 1] = {
                id = tostring(vehicle.id or vehicle.plate):sub(1, 64),
                plate = tostring(vehicle.plate or 'UNBEKANNT'):sub(1, 16),
                model = tostring(vehicle.model or 'unbekannt'):sub(1, 64),
                label = tostring(vehicle.label or vehicle.model or 'Fahrzeug'):sub(1, 96),
                garage = tostring(vehicle.garage or 'Unbekannt'):sub(1, 64),
                owner = tostring(vehicle.owner or 'Nicht aufgelöst'):sub(1, 96),
                stored = vehicle.stored ~= false
            }
        end
    end

    return true, result
end

exports('RegisterItemAdapter', Adapters.RegisterItems)
exports('RegisterVehicleAdapter', Adapters.RegisterVehicles)
