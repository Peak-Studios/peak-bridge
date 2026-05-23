const fs = require('fs');
const luaparse = require('luaparse');

const files = [
  'fxmanifest.lua',
  'shared/config.lua',
  'shared/utils.lua',
  'server/main.lua',
  'client/main.lua',
];

for (const file of files) {
  const source = fs.readFileSync(file, 'utf8');
  luaparse.parse(source, {
    luaVersion: '5.3',
    locations: true,
  });
}

console.log(`Parsed ${files.length} Lua files.`);
