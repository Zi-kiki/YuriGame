THEOS ?= /var/theos

ARCHS = arm64
TARGET = iphone:15.6:14.5

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ArtemisHook

ArtemisHook_FILES = ArtemisHook.m

ArtemisHook_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
ArtemisHook_CXXFLAGS = -fobjc-arc -Wno-deprecated-declarations -std=c++11
ArtemisHook_LDFLAGS = -lc++
ArtemisHook_FRAMEWORKS = UIKit Foundation CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
    install.exec "killall -9 SpringBoard"
