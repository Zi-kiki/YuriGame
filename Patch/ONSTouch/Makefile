THEOS = /var/theos

ARCHS = arm64
TARGET = iphone:15.6:14.5

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ONSTouch

ONSTouch_FILES = ONSTouch.m

ONSTouch_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
ONSTouch_CXXFLAGS = -fobjc-arc -Wno-deprecated-declarations -std=c++11
ONSTouch_LDFLAGS = -lc++
ONSTouch_FRAMEWORKS = UIKit Foundation CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
    install.exec "killall -9 SpringBoard"