#include <stdlib.h>
#include <string.h>
#include <emscripten.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

__attribute__((import_module("lunar"), import_name("host")))
extern int lunar_host(lua_State *L, int operation, int handle);

static const char *HANDLE = "lunar.javascript";
static char handles_key;

static int dispatch(lua_State *L, int operation, int handle) {
  int result = lunar_host(L, operation, handle);
  return result < 0 ? lua_error(L) : result;
}

static int get(lua_State *L) { return dispatch(L, 0, 0); }
static int set(lua_State *L) { return dispatch(L, 1, 0); }
static int call(lua_State *L) { return dispatch(L, 2, 0); }
static int construct(lua_State *L) { return dispatch(L, 3, 0); }
static int stringify(lua_State *L) { return dispatch(L, 4, 0); }
static int proxy(lua_State *L) { return dispatch(L, 6, 0); }

static int release(lua_State *L) {
  int *handle = luaL_checkudata(L, 1, HANDLE);
  return dispatch(L, 5, *handle);
}

EMSCRIPTEN_KEEPALIVE void lunar_pushhandle(lua_State *L, int handle) {
  lua_rawgetp(L, LUA_REGISTRYINDEX, &handles_key);
  lua_rawgeti(L, -1, handle);
  if (!lua_isnil(L, -1)) {
    lua_remove(L, -2);
    return;
  }
  lua_pop(L, 1);
  int *value = lua_newuserdatauv(L, sizeof(int), 0);
  *value = handle;
  luaL_setmetatable(L, HANDLE);
  lua_pushvalue(L, -1);
  lua_rawseti(L, -3, handle);
  lua_remove(L, -2);
}

static int open_js(lua_State *L) {
  lua_newtable(L);
  lua_pushcfunction(L, construct);
  lua_setfield(L, -2, "new");
  lua_pushcfunction(L, proxy);
  lua_setfield(L, -2, "createproxy");
  lunar_pushhandle(L, 1);
  lua_setfield(L, -2, "global");
  lunar_pushhandle(L, 0);
  lua_setfield(L, -2, "null");
  return 1;
}

EMSCRIPTEN_KEEPALIVE lua_State *lunar_open(void) {
  lua_State *L = luaL_newstate();
  if (!L) return NULL;
  luaL_openlibs(L);
  lua_newtable(L);
  lua_newtable(L);
  lua_pushliteral(L, "v");
  lua_setfield(L, -2, "__mode");
  lua_setmetatable(L, -2);
  lua_rawsetp(L, LUA_REGISTRYINDEX, &handles_key);
  luaL_newmetatable(L, HANDLE);
  const luaL_Reg methods[] = {
    {"__index", get}, {"__newindex", set}, {"__call", call},
    {"__tostring", stringify}, {"__gc", release}, {NULL, NULL}
  };
  luaL_setfuncs(L, methods, 0);
  lua_pop(L, 1);
  luaL_requiref(L, "js", open_js, 0);
  lua_pop(L, 1);
  return L;
}

EMSCRIPTEN_KEEPALIVE void lunar_close(lua_State *L) { lua_close(L); }
EMSCRIPTEN_KEEPALIVE void *lunar_alloc(size_t size) { return malloc(size); }
EMSCRIPTEN_KEEPALIVE void lunar_free(void *pointer) { free(pointer); }
EMSCRIPTEN_KEEPALIVE int lunar_top(lua_State *L) { return lua_gettop(L); }
EMSCRIPTEN_KEEPALIVE void lunar_settop(lua_State *L, int index) { lua_settop(L, index); }
EMSCRIPTEN_KEEPALIVE int lunar_type(lua_State *L, int index) { return lua_type(L, index); }
EMSCRIPTEN_KEEPALIVE int lunar_isinteger(lua_State *L, int index) { return lua_isinteger(L, index); }
EMSCRIPTEN_KEEPALIVE lua_Integer lunar_integer(lua_State *L, int index) { return lua_tointeger(L, index); }
EMSCRIPTEN_KEEPALIVE double lunar_number(lua_State *L, int index) { return lua_tonumber(L, index); }
EMSCRIPTEN_KEEPALIVE int lunar_boolean(lua_State *L, int index) { return lua_toboolean(L, index); }
EMSCRIPTEN_KEEPALIVE const char *lunar_string(lua_State *L, int index) { return lua_tolstring(L, index, NULL); }
EMSCRIPTEN_KEEPALIVE size_t lunar_length(lua_State *L, int index) { return lua_rawlen(L, index); }
EMSCRIPTEN_KEEPALIVE const void *lunar_identity(lua_State *L, int index) { return lua_topointer(L, index); }
EMSCRIPTEN_KEEPALIVE int lunar_handle(lua_State *L, int index) {
  int *handle = luaL_testudata(L, index, HANDLE);
  return handle ? *handle : -1;
}
EMSCRIPTEN_KEEPALIVE void lunar_pushnil(lua_State *L) { lua_pushnil(L); }
EMSCRIPTEN_KEEPALIVE void lunar_pushboolean(lua_State *L, int value) { lua_pushboolean(L, value); }
EMSCRIPTEN_KEEPALIVE void lunar_pushnumber(lua_State *L, double value) { lua_pushnumber(L, value); }
EMSCRIPTEN_KEEPALIVE void lunar_pushinteger(lua_State *L, lua_Integer value) { lua_pushinteger(L, value); }
EMSCRIPTEN_KEEPALIVE void lunar_pushstring(lua_State *L, const char *value, size_t size) {
  lua_pushlstring(L, value, size);
}
EMSCRIPTEN_KEEPALIVE int lunar_ref(lua_State *L, int index) {
  lua_pushvalue(L, index);
  return luaL_ref(L, LUA_REGISTRYINDEX);
}
EMSCRIPTEN_KEEPALIVE void lunar_unref(lua_State *L, int reference) {
  luaL_unref(L, LUA_REGISTRYINDEX, reference);
}
EMSCRIPTEN_KEEPALIVE int lunar_eval(lua_State *L, const char *source, size_t size, const char *name) {
  int status = luaL_loadbuffer(L, source, size, name);
  return status == LUA_OK ? lua_pcall(L, 0, LUA_MULTRET, 0) : status;
}
EMSCRIPTEN_KEEPALIVE int lunar_call(lua_State *L, int reference, int count) {
  lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  lua_insert(L, -count - 1);
  return lua_pcall(L, count, LUA_MULTRET, 0);
}
static int index_ref(lua_State *L) {
  lua_gettable(L, 1);
  return 1;
}
static int assign_ref(lua_State *L) {
  lua_settable(L, 1);
  return 0;
}
EMSCRIPTEN_KEEPALIVE int lunar_index(lua_State *L, int reference) {
  lua_pushcfunction(L, index_ref);
  lua_insert(L, -2);
  lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  lua_insert(L, -2);
  return lua_pcall(L, 2, 1, 0);
}
EMSCRIPTEN_KEEPALIVE int lunar_assign(lua_State *L, int reference) {
  lua_pushcfunction(L, assign_ref);
  lua_insert(L, -3);
  lua_rawgeti(L, LUA_REGISTRYINDEX, reference);
  lua_insert(L, -3);
  return lua_pcall(L, 3, 0, 0);
}
