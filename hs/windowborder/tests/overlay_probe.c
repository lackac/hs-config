#include "../wb_overlay.h"

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
  WBPrivateAPI api;
  char error[256] = { 0 };
  if (!wb_skylight_load(&api, error, sizeof(error))) {
    fprintf(stderr, "windowborder private API probe failed: %s\n", error);
    return 1;
  }

  printf("SkyLight symbols resolved; corner radii: %s\n", wb_skylight_has_corner_radii(&api) ? "available" : "unavailable");
  if (argc == 1) {
    wb_skylight_unload(&api);
    return 0;
  }
  if (argc != 3) {
    fputs("usage: windowborder-probe [window-id owner-pid]\n", stderr);
    wb_skylight_unload(&api);
    return 2;
  }

  uint32_t target_id = (uint32_t)strtoul(argv[1], NULL, 10);
  pid_t owner_pid = (pid_t)strtol(argv[2], NULL, 10);
  WBRenderStyle style = {
    .width = 12,
    .rows = 6,
    .radius = 0,
    .tuck = 14,
    .color = 0xffd58561,
    .chart = -1,
    .stitch = WB_STITCH_STOCKINETTE,
  };
  WBOverlay overlay = { 0 };
  if (!wb_overlay_attach(&overlay, &api, target_id, owner_pid, &style, 9, error, sizeof(error))) {
    fprintf(stderr, "windowborder overlay probe failed: %s\n", error);
    wb_overlay_destroy(&overlay);
    wb_skylight_unload(&api);
    return 1;
  }
  usleep(250000);
  if (!wb_overlay_matches_target_space(&overlay)) {
    fputs("windowborder overlay probe failed: overlay left target space\n", stderr);
    wb_overlay_destroy(&overlay);
    wb_skylight_unload(&api);
    return 1;
  }
  wb_overlay_hide(&overlay);
  wb_overlay_destroy(&overlay);
  wb_skylight_unload(&api);
  return 0;
}
