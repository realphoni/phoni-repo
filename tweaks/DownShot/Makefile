ARCHS = arm64
TARGET = iphone:clang:12.4:12.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

include $(THEOS)/makefiles/common.mk
TWEAK_NAME = DownShot
DownShot_FILES = Tweak.xm
DownShot_CFLAGS = -fobjc-arc -Wall -Wextra
DownShot_FRAMEWORKS = UIKit Foundation
include $(THEOS_MAKE_PATH)/tweak.mk
