-- metadata.lua  –  Solar2D plugin metadata for plugin.ironSource
-- v9.3.5: IronSource is statically merged into libplugin_ironSource.a.
-- No dynamic framework embedding required.
local metadata = {
    plugin = {
        format            = 'staticLibrary',
        androidEntryPoint = 'plugin.ironSource.LuaLoader',
        supportedPlatforms = {
            android       = { marketplaceId = "" },
            iphone        = {
                marketplaceId = "",
                -- IronSource SDK is statically linked (merged into libplugin_ironSource.a).
                -- No frameworks entry needed — nothing to embed dynamically.
            },
            ["mac-sim"]   = false,
            ["win32-sim"] = false,
        },
    },
}
return metadata
