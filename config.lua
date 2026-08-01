ConfigAdmin = {}

ConfigAdmin.Locale = 'de'
ConfigAdmin.Debug = false
ConfigAdmin.PrintPreparedFeatures = false

ConfigAdmin.MenuTitle = 'SUPPORT'
ConfigAdmin.OpenCommand = 'tyadmin'
ConfigAdmin.DefaultKey = 'F9'

ConfigAdmin.RequestCooldown = 150
ConfigAdmin.ActionCooldown = 200
ConfigAdmin.MaxReasonLength = 180
ConfigAdmin.MaxItemAmount = 1000
ConfigAdmin.MaxVehicleDistanceForLocalActions = 25.0

ConfigAdmin.BanDurations = {
    { label = '1 Stunde', seconds = 60 * 60 },
    { label = '24 Stunden', seconds = 24 * 60 * 60 },
    { label = '7 Tage', seconds = 7 * 24 * 60 * 60 },
    { label = '30 Tage', seconds = 30 * 24 * 60 * 60 },
    { label = 'Permanent', seconds = 0 }
}

-- Die folgenden Werte werden aus ty_characters.data_json gelesen, sobald
-- spätere Resources sie dort ablegen. Fehlt ein Wert, zeigt das Menü sauber
-- "Nicht vorhanden" statt erfundene Daten an.
ConfigAdmin.PlayerDataPaths = {
    cash = { 'money.cash', 'cash' },
    bank = { 'money.bank', 'bank' },
    job = { 'job.label', 'job.name', 'job' },
    gang = { 'gang.label', 'gang.name', 'gang' },
    hunger = { 'status.hunger', 'hunger' },
    thirst = { 'status.thirst', 'thirst' }
}

ConfigAdmin.Noclip = {
    NormalSpeed = 1.2,
    FastSpeed = 4.0,
    SlowSpeed = 0.35
}
