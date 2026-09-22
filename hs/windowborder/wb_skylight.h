#pragma once

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct {
  void *handle;

  int (*main_connection_id)(void);
  CGError (*new_connection)(int, int *);
  CGError (*release_connection)(int);
  CGError (*get_window_owner)(int, uint32_t, int *);
  CGError (*connection_get_pid)(int, pid_t *);
  CGError (*get_window_bounds)(int, uint32_t, CGRect *);
  CGError (*window_is_ordered_in)(int, uint32_t, bool *);

  CFTypeRef (*window_query_windows)(int, CFArrayRef, uint32_t);
  CFTypeRef (*window_query_result_copy_windows)(CFTypeRef);
  int (*window_iterator_get_count)(CFTypeRef);
  bool (*window_iterator_advance)(CFTypeRef);
  uint32_t (*window_iterator_get_window_id)(CFTypeRef);
  int (*window_iterator_get_level)(CFTypeRef);
  int32_t (*get_window_sublevel)(int, uint32_t);
  CFArrayRef (*window_iterator_get_corner_radii)(CFTypeRef);

  CGError (*new_region_with_rect)(CGRect *, CFTypeRef *);
  CGError (*new_window)(int, int, float, float, CFTypeRef, uint32_t *);
  CGError (*release_window)(int, uint32_t);
  CGError (*set_window_tags)(int, uint32_t, uint64_t *, int);
  CGError (*clear_window_tags)(int, uint32_t, uint64_t *, int);
  CGError (*set_window_shape)(int, uint32_t, float, float, CFTypeRef);
  CGError (*set_window_resolution)(int, uint32_t, double);
  CGError (*set_window_opacity)(int, uint32_t, bool);
  CGError (*set_window_alpha)(int, uint32_t, float);
  CGError (*window_set_shadow_properties)(uint32_t, CFDictionaryRef);
  CGContextRef (*window_context_create)(int, uint32_t, CFDictionaryRef);
  CGError (*flush_window_content_region)(int, uint32_t, void *);
  CFArrayRef (*copy_spaces_for_windows)(int, int, CFArrayRef);
  void (*move_windows_to_managed_space)(int, CFArrayRef, uint64_t);

  CFTypeRef (*transaction_create)(int);
  void (*transaction_move_window_with_group)(CFTypeRef, uint32_t, CGPoint);
  void (*transaction_set_window_level)(CFTypeRef, uint32_t, int);
  void (*transaction_set_window_sublevel)(CFTypeRef, uint32_t, int);
  void (*transaction_order_window)(CFTypeRef, uint32_t, int, uint32_t);
  void (*transaction_set_window_transform)(CFTypeRef, uint32_t, int, int, CGAffineTransform);
  void (*transaction_commit)(CFTypeRef, int);
} WBPrivateAPI;

bool wb_skylight_load(WBPrivateAPI *api, char *error, size_t error_size);
void wb_skylight_unload(WBPrivateAPI *api);
bool wb_skylight_has_corner_radii(const WBPrivateAPI *api);
