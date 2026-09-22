#pragma once

#include <CoreGraphics/CoreGraphics.h>
#include <stdbool.h>
#include <stdint.h>

typedef enum {
  WB_STITCH_STOCKINETTE,
  WB_STITCH_RIB,
  WB_STITCH_GARTER,
} WBStitch;

typedef struct {
  float width;
  float rows;
  float radius;
  float tuck;
  uint32_t color;
  int chart;
  WBStitch stitch;
} WBRenderStyle;

bool wb_renderer_pattern(const char *name, int *chart, char *error, size_t error_size);
int wb_renderer_pattern_count(void);
const char *wb_renderer_pattern_name(int index);
bool wb_renderer_configure(const WBRenderStyle *style, char *error, size_t error_size);
bool wb_renderer_draw(CGContextRef context, CGRect target, const WBRenderStyle *style, char *error, size_t error_size);
void wb_renderer_reset(void);
