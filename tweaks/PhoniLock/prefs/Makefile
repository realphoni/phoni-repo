ARCHS = arm64
TARGET = iphone:clang:12.4:12.0
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = PhoniLockPrefs
PhoniLockPrefs_FILES = PLRootListController.m ../PLAppearance.m
PhoniLockPrefs_CFLAGS = -fobjc-arc -Wall -Wextra
PhoniLockPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation QuartzCore
PhoniLockPrefs_PRIVATE_FRAMEWORKS = Preferences
PhoniLockPrefs_INSTALL_PATH = /Library/PreferenceBundles
PhoniLockPrefs_RESOURCE_DIRS = Resources
include $(THEOS_MAKE_PATH)/bundle.mk
