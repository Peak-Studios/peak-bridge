fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'peak-bridge'
description 'Peak Bridge - shared framework, inventory, SQL, and client integration bridge for Peak resources'
author 'Peak Studios'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/utils.lua',
}

server_scripts {
    'server/main.lua',
}

client_scripts {
    'client/main.lua',
}

dependencies {
    'ox_lib',
}
