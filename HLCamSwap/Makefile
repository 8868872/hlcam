ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

# rootless（Dopamine 2 / palera1n rootless）必须加这一行
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HLCamSwap
HLCamSwap_FILES = Tweak.x
HLCamSwap_CFLAGS = -fobjc-arc
HLCamSwap_FRAMEWORKS = UIKit Photos AVFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
