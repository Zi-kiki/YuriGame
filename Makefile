TARGET := iphone:15.6:14.0
ARCHS := arm64
THEOS ?= /var/theos

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := YuriGame
YuriGame_FILES := main.m MainUI.m YiAppDelegate.m litehook/Dyld.m litehook/LCMachOUtils.m litehook/utils.m litehook/litehook.c
YuriGame_FRAMEWORKS := UIKit CoreGraphics
YuriGame_CFLAGS := -fobjc-arc
YuriGame_LDFLAGS := -e _YuriGameMain

include $(THEOS_MAKE_PATH)/application.mk
