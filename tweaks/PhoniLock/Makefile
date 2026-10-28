ARCHS = arm64
TARGET = iphone:clang:12.4:12.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PhoniLock
PhoniLock_FILES = Tweak.xm PLAppearance.m
PhoniLock_CFLAGS = -fobjc-arc -Wall -Wextra
PhoniLock_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
