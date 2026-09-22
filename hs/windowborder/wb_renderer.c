#include "wb_renderer.h"

#include "vendor/window-sweaters/src/misc/chart.h"
#include "vendor/window-sweaters/src/misc/knit.h"

#include <math.h>
#include <stdio.h>

static void load_patterns(void) {
  if (g_chart_count == 0) knit_charts_load(NULL);
}

bool wb_renderer_pattern(const char *name, int *chart, char *error, size_t error_size) {
  if (!name || !chart) {
    snprintf(error, error_size, "missing knit pattern");
    return false;
  }
  load_patterns();
  *chart = knit_chart_index(name);
  if (*chart < 0) {
    snprintf(error, error_size, "unknown knit pattern: %s", name);
    return false;
  }
  return true;
}

int wb_renderer_pattern_count(void) {
  load_patterns();
  return g_chart_count;
}

const char *wb_renderer_pattern_name(int index) {
  load_patterns();
  return index >= 0 && index < g_chart_count ? g_charts[index].name : NULL;
}

bool wb_renderer_configure(const WBRenderStyle *style, char *error, size_t error_size) {
  if (!style || !isfinite(style->width) || !isfinite(style->rows) || !isfinite(style->radius)
      || !isfinite(style->tuck) || style->width < 8 || style->width > 32 || style->rows < 3
      || style->rows > 12 || style->radius < 0 || style->radius > 64 || style->tuck < 1
      || style->tuck > 24 || style->stitch < WB_STITCH_STOCKINETTE || style->stitch > WB_STITCH_GARTER) {
    snprintf(error, error_size, "invalid knit border style");
    return false;
  }

  g_knit.rows = style->rows;
  g_knit_stitch = (int)style->stitch;
  g_knit_anchor = KNIT_ANCHOR_CORNER;
  g_knit_dim = 0;
  g_knit_on = true;
  return true;
}

bool wb_renderer_draw(CGContextRef context, CGRect target, const WBRenderStyle *style, char *error, size_t error_size) {
  if (!context || !isfinite(target.origin.x) || !isfinite(target.origin.y) || !isfinite(target.size.width)
      || !isfinite(target.size.height) || target.size.width <= 0 || target.size.height <= 0) {
    snprintf(error, error_size, "invalid border drawing context or target bounds");
    return false;
  }

  if (!wb_renderer_configure(style, error, error_size)) return false;
  knit_draw(context, target, style->radius, style->width, style->color, style->chart, 0, style->tuck);
  return true;
}

void wb_renderer_reset(void) {
  knit_flush_cache();
  g_chart_active = -1;
}
