#include "wb_skylight.h"

#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

#define WB_LOAD_REQUIRED(api, field, symbol) \
  do { \
    *(void **)(&((api)->field)) = dlsym((api)->handle, symbol); \
    if (!(api)->field) { \
      snprintf(error, error_size, "missing SkyLight symbol: %s", symbol); \
      wb_skylight_unload(api); \
      return false; \
    } \
  } while (0)

static void *open_skylight(void) {
  const char *paths[] = {
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
    "/System/Library/Frameworks/SkyLight.framework/SkyLight",
  };

  for (size_t i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
    void *handle = dlopen(paths[i], RTLD_LOCAL | RTLD_LAZY);
    if (handle) return handle;
  }

  return NULL;
}

bool wb_skylight_load(WBPrivateAPI *api, char *error, size_t error_size) {
  memset(api, 0, sizeof(*api));
  api->handle = open_skylight();
  if (!api->handle) {
    snprintf(error, error_size, "could not load SkyLight: %s", dlerror());
    return false;
  }

  WB_LOAD_REQUIRED(api, main_connection_id, "SLSMainConnectionID");
  WB_LOAD_REQUIRED(api, new_connection, "SLSNewConnection");
  WB_LOAD_REQUIRED(api, release_connection, "SLSReleaseConnection");
  WB_LOAD_REQUIRED(api, get_window_owner, "SLSGetWindowOwner");
  WB_LOAD_REQUIRED(api, connection_get_pid, "SLSConnectionGetPID");
  WB_LOAD_REQUIRED(api, get_window_bounds, "SLSGetWindowBounds");
  WB_LOAD_REQUIRED(api, window_is_ordered_in, "SLSWindowIsOrderedIn");
  WB_LOAD_REQUIRED(api, window_query_windows, "SLSWindowQueryWindows");
  WB_LOAD_REQUIRED(api, window_query_result_copy_windows, "SLSWindowQueryResultCopyWindows");
  WB_LOAD_REQUIRED(api, window_iterator_get_count, "SLSWindowIteratorGetCount");
  WB_LOAD_REQUIRED(api, window_iterator_advance, "SLSWindowIteratorAdvance");
  WB_LOAD_REQUIRED(api, window_iterator_get_window_id, "SLSWindowIteratorGetWindowID");
  WB_LOAD_REQUIRED(api, window_iterator_get_level, "SLSWindowIteratorGetLevel");
  WB_LOAD_REQUIRED(api, get_window_sublevel, "SLSGetWindowSubLevel");
  WB_LOAD_REQUIRED(api, new_region_with_rect, "CGSNewRegionWithRect");
  WB_LOAD_REQUIRED(api, new_window, "SLSNewWindow");
  WB_LOAD_REQUIRED(api, release_window, "SLSReleaseWindow");
  WB_LOAD_REQUIRED(api, set_window_tags, "SLSSetWindowTags");
  WB_LOAD_REQUIRED(api, clear_window_tags, "SLSClearWindowTags");
  WB_LOAD_REQUIRED(api, set_window_shape, "SLSSetWindowShape");
  WB_LOAD_REQUIRED(api, set_window_resolution, "SLSSetWindowResolution");
  WB_LOAD_REQUIRED(api, set_window_opacity, "SLSSetWindowOpacity");
  WB_LOAD_REQUIRED(api, set_window_alpha, "SLSSetWindowAlpha");
  WB_LOAD_REQUIRED(api, window_set_shadow_properties, "SLSWindowSetShadowProperties");
  WB_LOAD_REQUIRED(api, window_context_create, "SLWindowContextCreate");
  WB_LOAD_REQUIRED(api, flush_window_content_region, "SLSFlushWindowContentRegion");
  WB_LOAD_REQUIRED(api, copy_spaces_for_windows, "SLSCopySpacesForWindows");
  WB_LOAD_REQUIRED(api, move_windows_to_managed_space, "SLSMoveWindowsToManagedSpace");
  WB_LOAD_REQUIRED(api, transaction_create, "SLSTransactionCreate");
  WB_LOAD_REQUIRED(api, transaction_move_window_with_group, "SLSTransactionMoveWindowWithGroup");
  WB_LOAD_REQUIRED(api, transaction_set_window_level, "SLSTransactionSetWindowLevel");
  WB_LOAD_REQUIRED(api, transaction_set_window_sublevel, "SLSTransactionSetWindowSubLevel");
  WB_LOAD_REQUIRED(api, transaction_order_window, "SLSTransactionOrderWindow");
  WB_LOAD_REQUIRED(api, transaction_set_window_transform, "SLSTransactionSetWindowTransform");
  WB_LOAD_REQUIRED(api, transaction_commit, "SLSTransactionCommit");

  *(void **)(&api->window_iterator_get_corner_radii) = dlsym(api->handle, "SLSWindowIteratorGetCornerRadii");
  return true;
}

void wb_skylight_unload(WBPrivateAPI *api) {
  if (api->handle) dlclose(api->handle);
  memset(api, 0, sizeof(*api));
}

bool wb_skylight_has_corner_radii(const WBPrivateAPI *api) {
  return api->window_iterator_get_corner_radii != NULL;
}
