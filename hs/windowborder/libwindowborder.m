@import Foundation;
@import LuaSkin;

#include "wb_overlay.h"

#include <math.h>
#include <string.h>

#define USERDATA_TAG "hs.windowborder"

typedef struct {
  WBPrivateAPI api;
  bool api_loaded;
  WBOverlay overlay;
  WBRenderStyle style;
  float fallback_radius;
  bool deleted;
  char state[16];
  char last_error[256];
} WBObject;

static WBObject *singleton = NULL;

static WBObject *check_object(lua_State *L) {
  WBObject **object = luaL_checkudata(L, 1, USERDATA_TAG);
  if (!object || !*object) luaL_error(L, "invalid hs.windowborder object");
  return *object;
}

static int push_error(lua_State *L, const char *code, const char *message) {
  lua_pushnil(L);
  lua_pushstring(L, code);
  lua_pushstring(L, message);
  return 3;
}

static int push_self_state(lua_State *L, const char *state) {
  lua_pushvalue(L, 1);
  lua_pushstring(L, state);
  return 2;
}

static bool finite_in_range(lua_Number value, float minimum, float maximum) {
  return isfinite(value) && value >= minimum && value <= maximum;
}

static bool get_number_option(lua_State *L, int index, const char *name, float minimum, float maximum, float *target,
                              char *error, size_t error_size) {
  lua_getfield(L, index, name);
  if (lua_isnil(L, -1)) {
    lua_pop(L, 1);
    return true;
  }
  if (!lua_isnumber(L, -1) || !finite_in_range(lua_tonumber(L, -1), minimum, maximum)) {
    snprintf(error, error_size, "%s must be a finite number between %.0f and %.0f", name, minimum, maximum);
    lua_pop(L, 1);
    return false;
  }
  *target = (float)lua_tonumber(L, -1);
  lua_pop(L, 1);
  return true;
}

static bool get_string_option(lua_State *L, int index, const char *name, const char **target) {
  lua_getfield(L, index, name);
  if (lua_isnil(L, -1)) {
    lua_pop(L, 1);
    return true;
  }
  if (!lua_isstring(L, -1)) {
    lua_pop(L, 1);
    return false;
  }
  *target = lua_tostring(L, -1);
  return true;
}

static bool parse_color(const char *text, uint32_t *color) {
  if (!text || strlen(text) != 7 || text[0] != '#') return false;
  unsigned value = 0;
  for (int i = 1; i < 7; i++) {
    char c = text[i];
    unsigned digit;
    if (c >= '0' && c <= '9') digit = (unsigned)(c - '0');
    else if (c >= 'a' && c <= 'f') digit = (unsigned)(c - 'a' + 10);
    else if (c >= 'A' && c <= 'F') digit = (unsigned)(c - 'A' + 10);
    else return false;
    value = (value << 4) | digit;
  }
  *color = 0xff000000u | value;
  return true;
}

static bool parse_options(lua_State *L, int index, WBObject *object, char *error, size_t error_size) {
  object->style = (WBRenderStyle){
    .width = 12,
    .rows = 6,
    .radius = 0,
    .tuck = 14,
    .color = 0xffd58561,
    .chart = -1,
    .stitch = WB_STITCH_STOCKINETTE,
  };
  object->fallback_radius = 9;
  if (lua_isnoneornil(L, index)) return true;
  if (!lua_istable(L, index)) {
    snprintf(error, error_size, "options must be a table");
    return false;
  }
  if (!get_number_option(L, index, "width", 8, 32, &object->style.width, error, error_size)
      || !get_number_option(L, index, "rows", 3, 12, &object->style.rows, error, error_size)
      || !get_number_option(L, index, "fallbackRadius", 0, 64, &object->fallback_radius, error, error_size)
      || !get_number_option(L, index, "tuck", 1, 24, &object->style.tuck, error, error_size)) return false;

  const char *style = NULL;
  if (!get_string_option(L, index, "style", &style)) {
    snprintf(error, error_size, "style must be a string");
    return false;
  }
  if (style && strcmp(style, "knit") != 0) {
    snprintf(error, error_size, "style must be knit");
    lua_pop(L, 1);
    return false;
  }
  if (style) lua_pop(L, 1);

  const char *color = NULL;
  if (!get_string_option(L, index, "color", &color) || (color && !parse_color(color, &object->style.color))) {
    snprintf(error, error_size, "color must use #RRGGBB");
    if (color) lua_pop(L, 1);
    return false;
  }
  if (color) lua_pop(L, 1);

  const char *pattern = "zigzag";
  lua_getfield(L, index, "pattern");
  if (lua_isnil(L, -1)) {
    lua_pop(L, 1);
  } else if (!lua_isstring(L, -1)) {
    lua_pop(L, 1);
    snprintf(error, error_size, "pattern must be a string");
    return false;
  } else {
    pattern = lua_tostring(L, -1);
    lua_pop(L, 1);
  }
  if (!wb_renderer_pattern(pattern, &object->style.chart, error, error_size)) {
    return false;
  }

  const char *stitch = NULL;
  if (!get_string_option(L, index, "stitch", &stitch)) {
    snprintf(error, error_size, "stitch must be a string");
    return false;
  }
  if (stitch) {
    if (strcmp(stitch, "stockinette") == 0) object->style.stitch = WB_STITCH_STOCKINETTE;
    else if (strcmp(stitch, "rib") == 0) object->style.stitch = WB_STITCH_RIB;
    else if (strcmp(stitch, "garter") == 0) object->style.stitch = WB_STITCH_GARTER;
    else {
      snprintf(error, error_size, "stitch must be stockinette, rib, or garter");
      lua_pop(L, 1);
      return false;
    }
    lua_pop(L, 1);
  }

  lua_getfield(L, index, "radius");
  if (lua_isnumber(L, -1) && finite_in_range(lua_tonumber(L, -1), 0, 64)) object->style.radius = (float)lua_tonumber(L, -1);
  else if (!lua_isnil(L, -1) && (!lua_isstring(L, -1) || strcmp(lua_tostring(L, -1), "auto") != 0)) {
    lua_pop(L, 1);
    snprintf(error, error_size, "radius must be auto or a finite number between 0 and 64");
    return false;
  }
  lua_pop(L, 1);
  return true;
}

static int new_object(lua_State *L) {
  if (singleton && !singleton->deleted) return push_error(L, "already_exists", "only one hs.windowborder object may exist");
  WBObject *object = calloc(1, sizeof(*object));
  if (!object) return push_error(L, "out_of_memory", "could not allocate border object");
  char error[256] = { 0 };
  if (!parse_options(L, 1, object, error, sizeof(error))) {
    free(object);
    return push_error(L, "invalid_options", error);
  }
  if (!wb_skylight_load(&object->api, error, sizeof(error))) {
    free(object);
    return push_error(L, "unsupported_platform", error);
  }
  object->api_loaded = true;
  strcpy(object->state, "detached");
  WBObject **userdata = lua_newuserdatauv(L, sizeof(*userdata), 0);
  *userdata = object;
  luaL_setmetatable(L, USERDATA_TAG);
  singleton = object;
  return 1;
}

static int attach(lua_State *L) {
  WBObject *object = check_object(L);
  if (object->deleted) return luaL_error(L, "hs.windowborder object is deleted");
  lua_Integer window_id = luaL_checkinteger(L, 2);
  lua_Integer owner_pid = luaL_checkinteger(L, 3);
  if (window_id < 1 || window_id > UINT32_MAX || owner_pid < 1 || owner_pid > INT32_MAX) {
    return push_error(L, "invalid_target", "window ID or owner PID is out of range");
  }
  char error[256] = { 0 };
  if (!wb_overlay_attach(&object->overlay, &object->api, (uint32_t)window_id, (pid_t)owner_pid,
                         &object->style, object->style.radius > 0 ? object->style.radius : object->fallback_radius,
                         error, sizeof(error))) {
    snprintf(object->last_error, sizeof(object->last_error), "%s", error);
    strcpy(object->state, "hidden");
    return push_error(L, "surface_failed", error);
  }
  object->last_error[0] = '\0';
  strcpy(object->state, "visible");
  return push_self_state(L, object->state);
}

static int update(lua_State *L) {
  WBObject *object = check_object(L);
  if (object->deleted) return luaL_error(L, "hs.windowborder object is deleted");
  if (!object->overlay.target_id) return push_self_state(L, "detached");
  char error[256] = { 0 };
  if (!wb_overlay_update(&object->overlay, &object->style,
                         object->style.radius > 0 ? object->style.radius : object->fallback_radius,
                         error, sizeof(error))) {
    wb_overlay_hide(&object->overlay);
    snprintf(object->last_error, sizeof(object->last_error), "%s", error);
    strcpy(object->state, "hidden");
    return push_error(L, "query_failed", error);
  }
  strcpy(object->state, "visible");
  return push_self_state(L, object->state);
}

static int hide(lua_State *L) {
  WBObject *object = check_object(L);
  if (!object->deleted) wb_overlay_hide(&object->overlay);
  strcpy(object->state, object->deleted ? "deleted" : "detached");
  object->overlay.target_id = 0;
  return push_self_state(L, object->state);
}

static void dispose(WBObject *object) {
  if (!object || object->deleted) return;
  wb_overlay_destroy(&object->overlay);
  wb_renderer_reset();
  if (object->api_loaded) wb_skylight_unload(&object->api);
  object->api_loaded = false;
  object->deleted = true;
  strcpy(object->state, "deleted");
  if (singleton == object) singleton = NULL;
}

static int delete_object(lua_State *L) {
  WBObject *object = check_object(L);
  dispose(object);
  return push_self_state(L, "deleted");
}

static int status(lua_State *L) {
  WBObject *object = check_object(L);
  lua_newtable(L);
  lua_pushstring(L, object->state);
  lua_setfield(L, -2, "state");
  if (object->overlay.target_id) {
    lua_pushinteger(L, object->overlay.target_id);
    lua_setfield(L, -2, "targetID");
    lua_pushinteger(L, object->overlay.owner_pid);
    lua_setfield(L, -2, "ownerPID");
  }
  if (object->overlay.window_id) {
    lua_pushinteger(L, object->overlay.window_id);
    lua_setfield(L, -2, "overlayID");
  }
  if (object->last_error[0]) {
    lua_pushstring(L, object->last_error);
    lua_setfield(L, -2, "lastError");
  }
  return 1;
}

static int update_style(lua_State *L, WBObject *object) {
  wb_renderer_reset();
  if (!object->overlay.target_id) return push_self_state(L, "detached");
  char error[256] = { 0 };
  if (!wb_overlay_update(&object->overlay, &object->style,
                         object->style.radius > 0 ? object->style.radius : object->fallback_radius,
                         error, sizeof(error))) {
    wb_overlay_hide(&object->overlay);
    snprintf(object->last_error, sizeof(object->last_error), "%s", error);
    strcpy(object->state, "hidden");
    return push_error(L, "surface_failed", error);
  }
  object->last_error[0] = '\0';
  strcpy(object->state, "visible");
  return push_self_state(L, object->state);
}

static int set_pattern(lua_State *L) {
  WBObject *object = check_object(L);
  if (object->deleted) return luaL_error(L, "hs.windowborder object is deleted");
  const char *pattern = luaL_checkstring(L, 2);
  char error[256] = { 0 };
  if (!wb_renderer_pattern(pattern, &object->style.chart, error, sizeof(error))) {
    return push_error(L, "invalid_pattern", error);
  }
  return update_style(L, object);
}

static int set_color(lua_State *L) {
  WBObject *object = check_object(L);
  if (object->deleted) return luaL_error(L, "hs.windowborder object is deleted");
  const char *color = luaL_checkstring(L, 2);
  if (!parse_color(color, &object->style.color)) return push_error(L, "invalid_color", "color must use #RRGGBB");
  return update_style(L, object);
}

static int gc(lua_State *L) {
  WBObject **userdata = luaL_checkudata(L, 1, USERDATA_TAG);
  if (userdata && *userdata) {
    dispose(*userdata);
    free(*userdata);
    *userdata = NULL;
  }
  return 0;
}

static int capabilities(lua_State *L) {
  WBPrivateAPI api;
  char error[256] = { 0 };
  bool loaded = wb_skylight_load(&api, error, sizeof(error));
  lua_newtable(L);
  lua_pushboolean(L, loaded);
  lua_setfield(L, -2, "symbolsAvailable");
  if (loaded) {
    lua_pushboolean(L, wb_skylight_has_corner_radii(&api));
    lua_setfield(L, -2, "radiusAvailable");
    wb_skylight_unload(&api);
  } else {
    lua_pushstring(L, error);
    lua_setfield(L, -2, "error");
  }
  return 1;
}

static int patterns(lua_State *L) {
  int count = wb_renderer_pattern_count();
  lua_newtable(L);
  for (int index = 0; index < count; index++) {
    lua_pushstring(L, wb_renderer_pattern_name(index));
    lua_rawseti(L, -2, index + 1);
  }
  return 1;
}

static const luaL_Reg object_methods[] = {
  { "attach", attach },
  { "update", update },
  { "hide", hide },
  { "delete", delete_object },
  { "status", status },
  { "setPattern", set_pattern },
  { "setColor", set_color },
  { NULL, NULL },
};

static const luaL_Reg module_methods[] = {
  { "new", new_object },
  { "capabilities", capabilities },
  { "patterns", patterns },
  { NULL, NULL },
};

__attribute__((visibility("default"))) int luaopen_hs_libwindowborder(lua_State *L) {
  luaL_newmetatable(L, USERDATA_TAG);
  lua_pushcfunction(L, gc);
  lua_setfield(L, -2, "__gc");
  lua_newtable(L);
  luaL_setfuncs(L, object_methods, 0);
  lua_setfield(L, -2, "__index");
  lua_pop(L, 1);
  luaL_newlib(L, module_methods);
  return 1;
}
