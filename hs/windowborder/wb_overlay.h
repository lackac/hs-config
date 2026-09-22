#pragma once

#include "wb_renderer.h"
#include "wb_skylight.h"

#include <stdbool.h>
#include <sys/types.h>

typedef struct {
  WBPrivateAPI *api;
  int connection;
  uint32_t window_id;
  CGContextRef context;
  CGRect frame;
  CGPoint origin;
  CGRect target_bounds;
  uint32_t target_id;
  pid_t owner_pid;
  bool visible;
} WBOverlay;

bool wb_overlay_attach(WBOverlay *overlay, WBPrivateAPI *api, uint32_t target_id, pid_t owner_pid,
                       const WBRenderStyle *style, float fallback_radius, char *error, size_t error_size);
bool wb_overlay_update(WBOverlay *overlay, const WBRenderStyle *style, float fallback_radius,
                       char *error, size_t error_size);
void wb_overlay_hide(WBOverlay *overlay);
void wb_overlay_destroy(WBOverlay *overlay);
bool wb_overlay_matches_target_space(const WBOverlay *overlay);
