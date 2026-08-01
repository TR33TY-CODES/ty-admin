fx_version 'cerulean'
game 'gta5'

author 'Treety / FuseLab Studios'
description 'Modulares TY Adminsystem auf Basis von ty-menu'
version '0.2.0'

lua54 'yes'

shared_scripts {
    'config.lua',
    'config_permissions.lua',
    'shared/vehicles.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/permissions.lua',
    'server/adapters.lua',
    'server/data.lua',
    'server/actions.lua',
    'server/main.lua'
}

client_scripts {
    'client/effects.lua',
    'client/menus.lua',
    'client/main.lua'
}

dependencies {
    'oxmysql',
    'ty-core',
    'ty-menu'
}
