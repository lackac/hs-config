HS_APP ?= /Applications/Hammerspoon.app
HS_FRAMEWORKS := $(HS_APP)/Contents/Frameworks
SDKROOT ?= $(shell xcrun --show-sdk-path)
CC ?= clang
ARCHS ?= $(shell uname -m)
MACOS_MIN ?= 13.0
BUILD_DIR := build
VENDOR := vendor/window-sweaters

CPPFLAGS := -I. -I$(VENDOR)/src -isysroot $(SDKROOT)
CFLAGS := -std=c11 -O2 -g -Wall -Wextra -Werror -fvisibility=hidden -mmacosx-version-min=$(MACOS_MIN) $(foreach arch,$(ARCHS),-arch $(arch))
FRAMEWORKS := -framework ApplicationServices

.PHONY: all doctor test probe run-probe clean distclean

all: ../libwindowborder.so

doctor:
	@$(CC) --version
	@printf 'SDK: %s\n' '$(SDKROOT)'
	@printf 'architectures: %s\n' '$(ARCHS)'
	@test -d '$(HS_FRAMEWORKS)'

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/renderer-test: tests/renderer_test.c wb_renderer.c $(VENDOR)/src/knit.c $(VENDOR)/src/chart.c | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wno-error=unused-function $^ $(FRAMEWORKS) -o $@

$(BUILD_DIR)/windowborder-probe: tests/overlay_probe.c wb_skylight.c wb_overlay.c wb_renderer.c $(VENDOR)/src/knit.c $(VENDOR)/src/chart.c | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wno-error=unused-function $^ $(FRAMEWORKS) -o $@

../libwindowborder.so: libwindowborder.m wb_overlay.c wb_renderer.c wb_skylight.c $(VENDOR)/src/knit.c $(VENDOR)/src/chart.c | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wno-error=unused-function -fobjc-arc -fmodules -F$(HS_FRAMEWORKS) $^ -bundle -undefined dynamic_lookup $(FRAMEWORKS) -framework LuaSkin -o $@

test: $(BUILD_DIR)/renderer-test
	$(BUILD_DIR)/renderer-test

probe: $(BUILD_DIR)/windowborder-probe

run-probe: probe
	$(BUILD_DIR)/windowborder-probe $(ARGS)

clean:
	rm -rf $(BUILD_DIR)

distclean: clean
	rm -f ../libwindowborder.so
