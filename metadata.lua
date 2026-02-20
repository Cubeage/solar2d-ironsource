-- metadata.lua  –  Solar2D plugin metadata for plugin.ironSource
local metadata = {
    plugin = {
        format            = 'staticLibrary',
        androidEntryPoint = 'plugin.ironSource.LuaLoader',
        supportedPlatforms = {
            android       = { marketplaceId = "" },
            iphone        = {
                marketplaceId = "",
                -- Tell CoronaBuilder to link against IronSource dynamic framework
                -- (CoronaBuilder adds -framework IronSource + embeds it in the IPA)
                frameworks = { "IronSource" },
            },
            ["mac-sim"]   = false,
            ["win32-sim"] = false,
        },
    },
}
return metadata
