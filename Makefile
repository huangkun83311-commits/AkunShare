TARGET := iphone:clang:16.0:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AkunShare

AkunShare_ARCHS = arm64
AkunShare_FILES = Tweak.xm
AkunShare_FRAMEWORKS = Foundation UIKit
AkunShare_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-package::
	@echo "✅ Build Success! Check packages/ folder."