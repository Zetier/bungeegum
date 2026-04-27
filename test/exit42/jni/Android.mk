LOCAL_PATH  := $(call my-dir)/..
SRC_DIR     ?= $(LOCAL_PATH)/src

include $(CLEAR_VARS)

LOCAL_CFLAGS	+= -fPIE
LOCAL_LDFLAGS	+= -fPIE -pie

LOCAL_MODULE    := exit42
LOCAL_SRC_FILES := $(wildcard $(SRC_DIR)/*.c)

include $(BUILD_EXECUTABLE)
