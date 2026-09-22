#include "../wb_renderer.h"

#include <ApplicationServices/ApplicationServices.h>
#include <stdio.h>

int main(void) {
  const size_t width = 800;
  const size_t height = 600;
  CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, colorspace,
                                                kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
  CGColorSpaceRelease(colorspace);
  if (!context) {
    fputs("could not create bitmap context\n", stderr);
    return 1;
  }

  WBRenderStyle style = {
    .width = 12,
    .rows = 6,
    .radius = 9,
    .tuck = 14,
    .color = 0xffd58561,
    .chart = -1,
    .stitch = WB_STITCH_STOCKINETTE,
  };
  char error[256] = { 0 };
  if (!wb_renderer_pattern("zigzag", &style.chart, error, sizeof(error))) {
    fprintf(stderr, "could not select pattern: %s\n", error);
    CGContextRelease(context);
    return 1;
  }
  bool drawn = wb_renderer_draw(context, CGRectMake(20, 20, 760, 560), &style, error, sizeof(error));
  CGContextRelease(context);
  wb_renderer_reset();
  if (!drawn) {
    fprintf(stderr, "renderer failed: %s\n", error);
    return 1;
  }
  return 0;
}
