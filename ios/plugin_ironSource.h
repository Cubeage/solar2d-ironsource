#ifndef PLUGIN_IRONSOURCE_H
#define PLUGIN_IRONSOURCE_H

// Expose the Lua entry-point; Lua state is opaque here.
struct lua_State;

CORONA_EXPORT int luaopen_plugin_ironSource(struct lua_State *L);

#endif // PLUGIN_IRONSOURCE_H
