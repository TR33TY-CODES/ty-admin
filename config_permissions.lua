ConfigPermissions = {}

-- Reihenfolge ist wichtig: Die erste passende ACE-Rolle gewinnt.
ConfigPermissions.RoleOrder = {
    'projectlead',
    'admin',
    'developer',
    'supporter',
    'trial_supporter'
}

ConfigPermissions.Roles = {
    projectlead = {
        label = 'Projektleitung',
        ace = 'ty.role.projectlead',
        permissions = { '*' }
    },
    admin = {
        label = 'Administrator',
        ace = 'ty.role.admin',
        permissions = {
            'menu.open', 'development.toggle',
            'self.*', 'players.*', 'vehicles.*', 'items.*',
            'world.*', 'security.*'
        }
    },
    developer = {
        label = 'Entwicklung',
        ace = 'ty.role.developer',
        permissions = {
            'menu.open', 'development.toggle',
            'self.*', 'players.view', 'players.details', 'players.goto',
            'players.spectate', 'vehicles.*', 'items.view'
        }
    },
    supporter = {
        label = 'Supporter',
        ace = 'ty.role.supporter',
        permissions = {
            'menu.open',
            'self.heal', 'self.revive', 'self.noclip', 'self.nametags',
            'self.coordinates', 'self.teleport_waypoint',
            'players.view', 'players.details', 'players.heal', 'players.revive',
            'players.goto', 'players.bring', 'players.spectate', 'players.freeze',
            'players.kick',
            'vehicles.view', 'vehicles.search', 'vehicles.teleport',
            'vehicles.repair', 'vehicles.wash', 'vehicles.flip'
        }
    },
    trial_supporter = {
        label = 'Test-Supporter',
        ace = 'ty.role.trialsupporter',
        permissions = {
            'menu.open',
            'self.heal', 'self.noclip', 'self.nametags', 'self.coordinates',
            'players.view', 'players.details', 'players.goto',
            'players.spectate', 'players.heal'
        }
    }
}

ConfigPermissions.KnownPermissions = {
    'menu.open',
    'development.toggle',
    'self.heal',
    'self.revive',
    'self.godmode',
    'self.invisible',
    'self.noclip',
    'self.nametags',
    'self.thermal',
    'self.coordinates',
    'self.vehicledata',
    'self.teleport_waypoint',
    'world.weather',
    'world.power',
    'players.view',
    'players.details',
    'players.heal',
    'players.revive',
    'players.goto',
    'players.bring',
    'players.spectate',
    'players.freeze',
    'players.give_item',
    'players.kick',
    'players.ban',
    'items.view',
    'items.give',
    'vehicles.view',
    'vehicles.search',
    'vehicles.spawn',
    'vehicles.teleport',
    'vehicles.repair',
    'vehicles.wash',
    'vehicles.flip',
    'vehicles.modify',
    'vehicles.delete',
    'vehicles.godmode',
    'vehicles.park',
    'vehicles.reload',
    'vehicles.claim',
    'vehicles.key',
    'security.unban'
}
