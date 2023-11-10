TARGET := iphone:clang:latest:7.0
INSTALL_TARGET_PROCESSES = Surge-iOS Surge-iOS-NE

ifndef ROOTLESS
$(info Build as a ROOTFUL Substrate Tweak)
PACKAGE_BUILDNAME := rootful
else # ROOTLESS
$(info Build as a ROOTLESS Substrate Tweak)
THEOS_PACKAGE_SCHEME=rootless
PACKAGE_BUILDNAME := rootless
endif # ROOTLESS

ifneq ($(findstring DEBUG,$(THEOS_SCHEMA)),)
PACKAGE_BUILDNAME := $(PACKAGE_BUILDNAME)debug
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Surge4Advanced

Surge4Advanced_FILES = Tweak.x
Surge4Advanced_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
