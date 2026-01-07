.PHONY: dev app python all clean dist-clean test

.DEFAULT_GOAL := all

ROOT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
VERSION := 0.1.0

PKG_NAME := com.zetier.bungeegum
APK_API21 := $(PKG_NAME)-debug-api21.apk
APK_API24 := $(PKG_NAME)-debug-api24.apk
LIB_DEPS := build/dep/lib
GRADLE_BUILD := gradle assembleDebug -g gradle_out
APK_PATH := $(ROOT_DIR)/android_app/$(PKG_NAME)/build/outputs/apk/debug/$(PKG_NAME)-debug.apk
BUILD_GRADLE := $(ROOT_DIR)/android_app/$(PKG_NAME)/build.gradle
FRIDA_DOWNLOADS := https://github.com/frida/frida/releases/download
FRIDA_VERSION := 16.4.10

GADGET_ARM_SO := frida-gadget-$(FRIDA_VERSION)-android-arm.so
GADGET_ARM64_SO := frida-gadget-$(FRIDA_VERSION)-android-arm64.so
GADGET_JNI_LIB := libfrida-gadget.so

APP_JNI_DIR := $(ROOT_DIR)/android_app/$(PKG_NAME)/src/main/jniLibs
CURRENT_UID_GID := $(shell id -u):$(shell id -g)
BUILD_IMAGE := bungeegum/android_apk_builder:gradle-6.5.1-sdk-33
ARCHES := armeabi-v7a arm64-v8a

TEST_DIR := $(ROOT_DIR)/test

$(LIB_DEPS):
	mkdir -p $@

.PRECIOUS: $(LIB_DEPS)/%.so

$(LIB_DEPS)/%.so: | $(LIB_DEPS)
	wget $(FRIDA_DOWNLOADS)/$(FRIDA_VERSION)/$*.so.xz -O $@.xz;
	@xz -dv $@.xz;

$(APP_JNI_DIR)/%/$(GADGET_JNI_LIB): $(LIB_DEPS)/$(GADGET_ARM64_SO) $(LIB_DEPS)/$(GADGET_ARM_SO)
	mkdir -p $(@D)
	@if [ "$(findstring armeabi,$*)" != "" ]; then \
		cp $(LIB_DEPS)/$(GADGET_ARM_SO) $@; \
	else \
		cp $(LIB_DEPS)/$(GADGET_ARM64_SO) $@; \
	fi

# Build API variants
build/$(PKG_NAME)-debug-api%.apk: $(BUILD_GRADLE).api% $(foreach arch,$(ARCHES),$(APP_JNI_DIR)/$(arch)/$(GADGET_JNI_LIB)) | build
	@echo "Building API $* variant..."
	@cp $< $(BUILD_GRADLE)
	docker run -it -u $(CURRENT_UID_GID) -v "$(ROOT_DIR)"/android_app:/app -w /app $(BUILD_IMAGE) $(GRADLE_BUILD)
	@cp $(APK_PATH) $@

build:
	@mkdir -p build

build/.dockerfile_timestamp : Dockerfile | build
	@touch build/.dockerfile_timestamp
	docker build . -t $(BUILD_IMAGE);

dev: build/.dockerfile_timestamp

# Copy both variants to Python package
app: build/$(APK_API21) build/$(APK_API24)
	@cp $^ python/src/bungeegum/

python:
	VERSION=$(VERSION) FRIDA_VERSION=$(FRIDA_VERSION) python3 -m pip install ./python


TEST_COMMANDS = \
	"bungeegum --elf $(TEST_DIR)/exit42_arm64-v8a" \
	"bungeegum --shellcode $(TEST_DIR)/exit42_arm64-v8a.bin" \
	"bungeegum --remote --elf /system/bin/sh --args -c 'return 42;'"

test:
	@if ! out=$$(adb shell getprop ro.product.cpu.abi) || ! [ $$out = arm64-v8a ]; then \
		echo "A single arm64-v8a device must be attached via adb to run tests"; \
		exit 1; \
	fi
	@if adb shell pm list packages $(PKG_NAME) | grep -q $(PKG_NAME); then \
		adb uninstall $(PKG_NAME); \
	fi
	@for cmd in $(TEST_COMMANDS); do \
		eval $$cmd; \
		ret=$$?; \
		if [ $$ret -ne 42 ]; then \
			echo "$$cmd returned $$ret"; \
			exit 1; \
		fi; \
	done

clean:
	rm -rf android_app/$(PKG_NAME)/build
	rm -rf android_app/.gradle
	rm -rf android_app/gradle_out
	rm -rf $(APP_JNI_DIR)/*
	rm -rf python/src/bungeegum.egg-info
	rm -f python/src/bungeegum/$(APK_API21)
	rm -f python/src/bungeegum/$(APK_API24)
	rm -f $(BUILD_GRADLE)
	rm -rf build

dist-clean: clean
	docker image rm $(BUILD_IMAGE) -f

all: dev app python
