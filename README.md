# ty-admin

`ty-admin` hält sämtliche Menü-Callbacks lokal und verbindet sie über serialisierbare Callback-IDs und Client-Events mit `ty-menu`. Dadurch werden keine Lua-Funktionen in verschachtelten Tabellen zwischen Resources übertragen.

Eigenständiges, serverautoritatives Adminsystem auf Basis von `ty-menu`. Das Menü bleibt beim Start unsichtbar und wird standardmäßig mit F9 angefragt. Ohne `menu.open`-Berechtigung antwortet der Server nicht und es passiert sichtbar nichts.

## Funktionsfähig

- feingranulare ACE-Rollen und zusätzlich serverseitige Prüfung jeder Aktion
- Development Mode als Export und synchronisierter State Bag
- sauber rücksetzbarer Godmode, Unsichtbarkeit und Noclip sowie Nametags, Thermalsicht, Koordinaten- und Fahrzeugdaten
- Selbstheilung, Wiederbelebung und Wegpunkt-Teleport
- aktive Spieler suchen und alle derzeit vorhandenen Core-Daten anzeigen
- Spieler heilen, wiederbeleben, mit Rückkehrposition beobachten, einfrieren, holen oder zu ihnen teleportieren
- Kick mit Begründung
- persistenter Bann mit Dauer und Begründung in `ty_characters.data_json`
- `tyunban FESTE_ID` in der Konsole beziehungsweise mit `security.unban`
- aktive Fahrzeuge nach Kennzeichen/Modell suchen
- Fahrzeug-Teleport, Reparatur, Waschen, Flippen, Performance-Mods, Godmode und Löschen
- Fahrzeuge über Suche oder ein separates Klassen-Untermenü spawnen

Noclip verwendet `W/A/S/D`, `Q/E` für hoch/runter, `Shift` für schnell und `Strg` für langsam. Das normale Adminmenü blockiert dabei weder Bewegung noch Kamera. Sichtbarkeit, Kollision, Alpha und Invincibility werden beim Ausschalten und beim Stoppen der Resource wiederhergestellt.

In der Fahrzeugübersicht öffnet `Fahrzeuge in Umgebung` die Reparatur-, Wasch-, Flip-, Performance-, Godmode-, Einpark- und Löschaktionen für das beim Öffnen ermittelte nächste Fahrzeug. Pfeile werden ausschließlich bei echten Untermenüs dargestellt.

## Vorbereitet

Items geben benötigt einen Itemadapter. Einparken, Neu laden, Beanspruchen und Schlüssel erstellen benötigen einen Fahrzeugadapter. Fehlt ein Adapter, erscheint eine klare Meldung und bei aktivem Debug/Prepared-Print ein Konsolenprint. Es werden keine erfundenen Daten geschrieben.

## Berechtigungen

Rollen und einzelne Funktionsrechte stehen vollständig in `config_permissions.lua`. ACE-Gruppen werden in `permissions.cfg` abgebildet. Die UI zeigt fehlende Funktionen ausgegraut mit Schloss; der Server prüft sie unabhängig davon erneut.

Beispiel:

```cfg
add_principal identifier.license:DEINE_LICENSE group.supporter
```

## Development-Status

Clientseitig:

```lua
local developmentMode = exports['ty-admin']:IsDevelopmentMode()
```

Serverseitig für Türen, Lager, Fahrzeuge oder Inventare:

```lua
if exports['ty-admin']:IsDevelopmentMode(source) then
    -- Zugriff für aktiven Development Mode erlauben
end
```

Andere Resources können auch `Player(source).state.tyDevelopmentMode` lesen. Sicherheitskritische Entscheidungen müssen trotzdem immer serverseitig getroffen werden.
