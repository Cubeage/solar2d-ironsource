-- metadata.lua  –  Solar2D plugin metadata for plugin.ironSource
local metadata = {
    plugin = {
        format           = 'staticLibrary',
        androidEntryPoint = 'plugin.ironSource.LuaLoader',
        supportedPlatforms = {
            android       = { marketplaceId = "" },
            iphone        = { marketplaceId = "" },
            ["mac-sim"]   = false,
            ["win32-sim"] = false,
        },
    },
}
return metadata
