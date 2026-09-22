#include "wb_overlay.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

enum { WB_BACKING_STORE_BUFFERED = 2, WB_BORDER_PADDING = 8 };

static CFArrayRef window_array(uint32_t window_id) {
  CFNumberRef number = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &window_id);
  if (!number) return NULL;
  CFArrayRef array = CFArrayCreate(kCFAllocatorDefault, (const void **)&number, 1, &kCFTypeArrayCallBacks);
  CFRelease(number);
  return array;
}

static bool target_matches_owner(WBOverlay *overlay, char *error, size_t error_size) {
  int target_connection = 0;
  pid_t owner_pid = 0;
  int main_connection = overlay->api->main_connection_id();
  if (overlay->api->get_window_owner(main_connection, overlay->target_id, &target_connection) != kCGErrorSuccess
      || overlay->api->connection_get_pid(target_connection, &owner_pid) != kCGErrorSuccess) {
    snprintf(error, error_size, "could not validate target window owner");
    return false;
  }
  if (owner_pid != overlay->owner_pid) {
    snprintf(error, error_size, "target window owner changed");
    return false;
  }
  return true;
}

static bool query_metadata(WBOverlay *overlay, int *level, int32_t *sublevel, float *radius,
                           char *error, size_t error_size) {
  CFArrayRef windows = window_array(overlay->target_id);
  if (!windows) {
    snprintf(error, error_size, "could not allocate target window query");
    return false;
  }
  CFTypeRef query = overlay->api->window_query_windows(overlay->api->main_connection_id(), windows, 0);
  CFRelease(windows);
  if (!query) {
    snprintf(error, error_size, "could not query target window metadata");
    return false;
  }
  CFTypeRef iterator = overlay->api->window_query_result_copy_windows(query);
  CFRelease(query);
  if (!iterator || overlay->api->window_iterator_get_count(iterator) < 1 || !overlay->api->window_iterator_advance(iterator)) {
    if (iterator) CFRelease(iterator);
    snprintf(error, error_size, "target window metadata is unavailable");
    return false;
  }
  *level = overlay->api->window_iterator_get_level(iterator);
  *sublevel = overlay->api->get_window_sublevel(overlay->api->main_connection_id(), overlay->target_id);
  if (overlay->api->window_iterator_get_corner_radii) {
    CFArrayRef radii = overlay->api->window_iterator_get_corner_radii(iterator);
    if (radii && CFArrayGetCount(radii) > 0) {
      CFNumberRef value = CFArrayGetValueAtIndex(radii, 0);
      int32_t native_radius = 0;
      if (value) CFNumberGetValue(value, kCFNumberSInt32Type, &native_radius);
      if (native_radius > 0) *radius = native_radius;
    }
    if (radii) CFRelease(radii);
  }
  CFRelease(iterator);
  return true;
}

static void destroy_surface(WBOverlay *overlay) {
  if (overlay->context) {
    CGContextRelease(overlay->context);
    overlay->context = NULL;
  }
  if (overlay->window_id) {
    overlay->api->release_window(overlay->connection, overlay->window_id);
    overlay->window_id = 0;
  }
  overlay->visible = false;
}

static bool create_surface(WBOverlay *overlay, CGRect frame, char *error, size_t error_size) {
  CFTypeRef region = NULL;
  if (overlay->api->new_region_with_rect(&frame, &region) != kCGErrorSuccess || !region) {
    snprintf(error, error_size, "could not create overlay shape");
    return false;
  }
  uint32_t window_id = 0;
  CGError result = overlay->api->new_window(overlay->connection, WB_BACKING_STORE_BUFFERED, -9999, -9999, region, &window_id);
  CFRelease(region);
  if (result != kCGErrorSuccess || !window_id) {
    snprintf(error, error_size, "could not create overlay window");
    return false;
  }
  overlay->window_id = window_id;
  uint64_t tags = (1ULL << 1) | (1ULL << 9);
  uint64_t clear_tags = 0;
  overlay->api->set_window_tags(overlay->connection, window_id, &tags, 64);
  overlay->api->clear_window_tags(overlay->connection, window_id, &clear_tags, 64);
  overlay->api->set_window_resolution(overlay->connection, window_id, 2.0);
  overlay->api->set_window_opacity(overlay->connection, window_id, false);
  overlay->api->set_window_alpha(overlay->connection, window_id, 0);

  CFIndex shadow_density = 0;
  CFNumberRef density = CFNumberCreate(kCFAllocatorDefault, kCFNumberCFIndexType, &shadow_density);
  const void *keys[] = { CFSTR("com.apple.WindowShadowDensity") };
  const void *values[] = { density };
  CFDictionaryRef properties = density
    ? CFDictionaryCreate(kCFAllocatorDefault, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks)
    : NULL;
  if (properties) overlay->api->window_set_shadow_properties(window_id, properties);
  if (properties) CFRelease(properties);
  if (density) CFRelease(density);

  overlay->context = overlay->api->window_context_create(overlay->connection, window_id, NULL);
  if (!overlay->context) {
    destroy_surface(overlay);
    snprintf(error, error_size, "could not create overlay drawing context");
    return false;
  }
  overlay->frame = frame;
  return true;
}

static bool first_space_id(WBOverlay *overlay, uint32_t window_id, uint64_t *space_id) {
  CFArrayRef window = window_array(window_id);
  if (!window) return false;
  CFArrayRef spaces = overlay->api->copy_spaces_for_windows(overlay->api->main_connection_id(), 0x7, window);
  CFRelease(window);
  if (!spaces || CFArrayGetCount(spaces) < 1) {
    if (spaces) CFRelease(spaces);
    return false;
  }
  CFTypeRef value = CFArrayGetValueAtIndex(spaces, 0);
  int64_t signed_space_id = 0;
  bool valid = value && CFGetTypeID(value) == CFNumberGetTypeID()
    && CFNumberGetValue(value, kCFNumberSInt64Type, &signed_space_id) && signed_space_id > 0;
  CFRelease(spaces);
  if (!valid) return false;
  *space_id = (uint64_t)signed_space_id;
  return true;
}

bool wb_overlay_matches_target_space(const WBOverlay *overlay) {
  if (!overlay || !overlay->api || !overlay->target_id || !overlay->window_id) return false;
  uint64_t target_space_id = 0;
  uint64_t overlay_space_id = 0;
  return first_space_id((WBOverlay *)overlay, overlay->target_id, &target_space_id)
    && first_space_id((WBOverlay *)overlay, overlay->window_id, &overlay_space_id)
    && target_space_id == overlay_space_id;
}

static bool synchronize_space(WBOverlay *overlay, char *error, size_t error_size) {
  CFArrayRef target = window_array(overlay->target_id);
  if (!target) {
    snprintf(error, error_size, "could not allocate target space query");
    return false;
  }
  CFArrayRef spaces = overlay->api->copy_spaces_for_windows(overlay->api->main_connection_id(), 0x7, target);
  if (!spaces || CFArrayGetCount(spaces) < 1) {
    if (spaces) CFRelease(spaces);
    CFRelease(target);
    snprintf(error, error_size, "target window space is unavailable");
    return false;
  }
  CFTypeRef space = CFArrayGetValueAtIndex(spaces, 0);
  int64_t signed_space_id = 0;
  bool valid_space = space && CFGetTypeID(space) == CFNumberGetTypeID()
    && CFNumberGetValue(space, kCFNumberSInt64Type, &signed_space_id) && signed_space_id > 0;
  CFRelease(spaces);
  CFArrayRef overlay_window = window_array(overlay->window_id);
  CFRelease(target);
  if (!overlay_window || !valid_space) {
    if (overlay_window) CFRelease(overlay_window);
    snprintf(error, error_size, "target window space is invalid");
    return false;
  }
  overlay->api->move_windows_to_managed_space(overlay->connection, overlay_window, (uint64_t)signed_space_id);
  CFRelease(overlay_window);
  if (!wb_overlay_matches_target_space(overlay)) {
    snprintf(error, error_size, "overlay did not join the target window space");
    return false;
  }
  return true;
}

bool wb_overlay_update(WBOverlay *overlay, const WBRenderStyle *style, float fallback_radius,
                       char *error, size_t error_size) {
  if (!overlay->target_id || !overlay->api) {
    snprintf(error, error_size, "no target window is attached");
    return false;
  }
  if (!target_matches_owner(overlay, error, error_size)) return false;
  CGRect bounds = CGRectZero;
  bool shown = false;
  int main_connection = overlay->api->main_connection_id();
  if (overlay->api->get_window_bounds(main_connection, overlay->target_id, &bounds) != kCGErrorSuccess
      || overlay->api->window_is_ordered_in(main_connection, overlay->target_id, &shown) != kCGErrorSuccess
      || !shown || !isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) || bounds.size.width <= 0 || bounds.size.height <= 0) {
    snprintf(error, error_size, "target window is not presentable");
    return false;
  }
  int level = 0;
  int32_t sublevel = 0;
  float radius = fallback_radius;
  if (!query_metadata(overlay, &level, &sublevel, &radius, error, error_size)) return false;
  radius = fmaxf(0, fminf(radius, fminf(bounds.size.width, bounds.size.height) / 2));
  float margin = style->width + WB_BORDER_PADDING;
  CGRect global_frame = CGRectInset(bounds, -margin, -margin);
  CGRect local_frame = CGRectMake(0, 0, global_frame.size.width, global_frame.size.height);
  bool resized = !overlay->window_id || !CGSizeEqualToSize(local_frame.size, overlay->frame.size);
  if (resized) {
    wb_overlay_hide(overlay);
    destroy_surface(overlay);
    if (!create_surface(overlay, local_frame, error, error_size)) return false;
  }
  if (!synchronize_space(overlay, error, error_size)) return false;

  CGContextClearRect(overlay->context, local_frame);
  WBRenderStyle render_style = *style;
  render_style.radius = radius;
  if (!wb_renderer_draw(overlay->context, CGRectMake(margin, margin, bounds.size.width, bounds.size.height), &render_style, error, error_size)) return false;
  CGContextFlush(overlay->context);
  overlay->api->flush_window_content_region(overlay->connection, overlay->window_id, NULL);

  CFTypeRef transaction = overlay->api->transaction_create(overlay->connection);
  if (!transaction) {
    snprintf(error, error_size, "could not create overlay transaction");
    return false;
  }
  CGAffineTransform transform = CGAffineTransformIdentity;
  transform.tx = -global_frame.origin.x;
  transform.ty = -global_frame.origin.y;
  overlay->api->transaction_move_window_with_group(transaction, overlay->window_id, global_frame.origin);
  overlay->api->transaction_set_window_transform(transaction, overlay->window_id, 0, 0, transform);
  overlay->api->transaction_set_window_level(transaction, overlay->window_id, level);
  overlay->api->transaction_set_window_sublevel(transaction, overlay->window_id, sublevel);
  overlay->api->transaction_order_window(transaction, overlay->window_id, -1, overlay->target_id);
  overlay->api->transaction_commit(transaction, 0);
  CFRelease(transaction);
  bool overlay_ordered = false;
  if (overlay->api->window_is_ordered_in(overlay->connection, overlay->window_id, &overlay_ordered) != kCGErrorSuccess || !overlay_ordered) {
    snprintf(error, error_size, "overlay did not order into the WindowServer");
    return false;
  }
  overlay->api->set_window_alpha(overlay->connection, overlay->window_id, 1);
  overlay->target_bounds = bounds;
  overlay->origin = global_frame.origin;
  overlay->visible = true;
  return true;
}

bool wb_overlay_attach(WBOverlay *overlay, WBPrivateAPI *api, uint32_t target_id, pid_t owner_pid,
                       const WBRenderStyle *style, float fallback_radius, char *error, size_t error_size) {
  wb_overlay_hide(overlay);
  overlay->api = api;
  overlay->target_id = target_id;
  overlay->owner_pid = owner_pid;
  if (!overlay->connection && api->new_connection(0, &overlay->connection) != kCGErrorSuccess) {
    snprintf(error, error_size, "could not create overlay connection");
    return false;
  }
  return wb_overlay_update(overlay, style, fallback_radius, error, error_size);
}

void wb_overlay_hide(WBOverlay *overlay) {
  if (overlay->window_id && overlay->api) {
    CFTypeRef transaction = overlay->api->transaction_create(overlay->connection);
    if (transaction) {
      overlay->api->transaction_order_window(transaction, overlay->window_id, 0, overlay->target_id);
      overlay->api->transaction_commit(transaction, 0);
      CFRelease(transaction);
    }
  }
  overlay->visible = false;
}

void wb_overlay_destroy(WBOverlay *overlay) {
  wb_overlay_hide(overlay);
  if (overlay->api) destroy_surface(overlay);
  if (overlay->connection && overlay->api) overlay->api->release_connection(overlay->connection);
  memset(overlay, 0, sizeof(*overlay));
}
