# ty-admin

Eigenständiges, serverautoritatives Adminsystem auf Basis von `ty-menu`. Das Menü bleibt beim Start unsichtbar und wird standardmäßig mit F9 angefragt. Ohne `menu.open`-Berechtigung antwortet der Server nicht und es passiert sichtbar nichts.

## Funktionsfähig

- feingranulare ACE-Rollen und zusätzlich serverseitige Prüfung jeder Aktion
- Admin Mode und Development Mode als Exports und synchronisierte State Bags
- Godmode, Unsichtbarkeit, Noclip, Nametags, Thermalsicht, Koordinaten- und Fahrzeugdaten
- Selbstheilung, Wiederbelebung und Wegpunkt-Teleport
- aktive Spieler suchen und alle derzeit vorhandenen Core-Daten anzeigen
- Spieler heilen, wiederbeleben, beobachten, einfrieren, holen oder zu ihnen teleportieren
- Kick mit Begründung
- persistenter Bann mit Dauer und Begründung in `ty_characters.data_json`
- `tyunban FESTE_ID` in der Konsole beziehungsweise mit `security.unban`
- aktive Fahrzeuge nach Kennzeichen/Modell suchen
- Fahrzeug-Teleport, Reparatur, Waschen, Flippen, Godmode und Löschen
- Fahrzeuge aus erlaubten Klassen/Modellen spawnen

## Vorbereitet

Items geben benötigt einen Itemadapter. Einparken, Neu laden, Beanspruchen und Schlüssel erstellen benötigen einen Fahrzeugadapter. Fehlt ein Adapter, erscheint eine klare Meldung und bei aktivem Debug/Prepared-Print ein Konsolenprint. Es werden keine erfundenen Daten geschrieben.

## Berechtigungen

Rollen und einzelne Funktionsrechte stehen vollständig in `config_permissions.lua`. ACE-Gruppen werden in `permissions.cfg` abgebildet. Die UI zeigt fehlende Funktionen ausgegraut mit Schloss; der Server prüft sie unabhängig davon erneut.

Beispiel:

```cfg
add_principal identifier.license:DEINE_LICENSE group.supporter
```

## Admin-/Development-Status

Clientseitig, zum Beispiel im HUD:

```lua
local adminMode = exports['ty-admin']:IsAdminMode()
local developmentMode = exports['ty-admin']:IsDevelopmentMode()
```

Serverseitig für Türen, Lager, Fahrzeuge oder Inventare:

```lua
if exports['ty-admin']:IsDevelopmentMode(source) then
    -- Zugriff für aktiven Development Mode erlauben
end
```

Andere Resources können auch `Player(source).state.tyDevelopmentMode` lesen. Sicherheitskritische Entscheidungen müssen trotzdem immer serverseitig getroffen werden.
