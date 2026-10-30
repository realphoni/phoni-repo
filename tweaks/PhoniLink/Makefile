ARCHS = arm64
TARGET = iphone:clang:12.4:12.0
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

include $(THEOS)/makefiles/common.mk
APPLICATION_NAME = PhoniLink
PhoniLink_FILES = main.m PLViewController.m PLCallManager.m PLAudio.m
PhoniLink_CFLAGS = -fobjc-arc -std=gnu11 -Wall -Wextra
PhoniLink_FRAMEWORKS = UIKit Foundation AVFoundation AudioToolbox MultipeerConnectivity
PhoniLink_RESOURCE_DIRS = Resources
include $(THEOS_MAKE_PATH)/application.mk

before-package:: $(THEOS_STAGING_DIR)/DEBIAN/control
	chmod 755 $(THEOS_STAGING_DIR)/DEBIAN/postinst $(THEOS_STAGING_DIR)/DEBIAN/postrm
