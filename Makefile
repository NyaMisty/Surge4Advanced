TARGET := iphone:clang:latest:7.0
INSTALL_TARGET_PROCESSES = Surge-iOS Surge-iOS-NE


include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Surge4Advanced

Surge4Advanced_FILES = Tweak.x
Surge4Advanced_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
