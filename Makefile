ARCHS = arm64
TARGET = iphone:15.6:14.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = YuriGame

YuriGame_FILES = main.m MainUI.m YiAppDelegate.m litehook/litehook.c litehook/Dyld.m litehook/utils.m litehook/LCMachOUtils.m

YuriGame_LDFLAGS = -e _YuriGameMain
YuriGame_CFLAGS = -fobjc-arc
YuriGame_FRAMEWORKS = UIKit CoreGraphics
YuriGame_CODESIGN_FLAGS = -Sentitlements.xml

include $(THEOS_MAKE_PATH)/application.mk

after-stage::
	@mv $(THEOS_STAGING_DIR)/Applications/YuriGame.app/YuriGame \
		$(THEOS_STAGING_DIR)/Applications/YuriGame.app/YuriGame_PleaseDoNotShortenTheExecutableNameBecauseItIsUsedToReserveSpaceForOverwritingThankYou