.PHONY: dev app python all clean dist-clean test

.DEFAULT_GOAL := all

ROOT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
VERSION := 0.1.0

PKG_NAME := com.zetier.bungeegum
APK := $(PKG_NAME)-debug.apk
LIB_DEPS := build/dep/lib
GRADLE_BUILD := gradle assembleDebug -g gradle_out
APK_PATH := $(ROOT_DIR)/android_app/$(PKG_NAME)/build/outputs/apk/debug/$(APK)
FRIDA_DOWNLOADS := https://github.com/frida/frida/releases/download
FRIDA_VERSION := 16.4.10

GADGET_ARM_SO := frida-gadget-$(FRIDA_VERSION)-android-arm.so
GADGET_ARM64_SO := frida-gadget-$(FRIDA_VERSION)-android-arm64.so
GADGET_JNI_LIB := libfrida-gadget.so

APP_JNI_DIR := $(ROOT_DIR)/android_app/$(PKG_NAME)/src/main/jniLibs
CURRENT_UID_GID := $(shell id -u):$(shell id -g)
BUILD_IMAGE := bungeegum/android_apk_builder:gradle-6.5.1-sdk-33
ARCHES := armeabi-v7a arm64-v8a
DOCKER_RUN := docker run --rm -u $(CURRENT_UID_GID) -v "$(ROOT_DIR)":/app
DOCKER_RUN_ANDROID := $(DOCKER_RUN) -w /app/android_app $(BUILD_IMAGE)
DOCKER_RUN_REPO := $(DOCKER_RUN) -w /app $(BUILD_IMAGE)

TEST_DIR := $(ROOT_DIR)/test
EXIT42_DIR := $(TEST_DIR)/exit42
EXIT42_RELEASE_DIR := $(EXIT42_DIR)/build/release
EXIT42_RELEASE_LOCAL_DIR := $(EXIT42_RELEASE_DIR)/local
TEST_BINARIES := \
	$(EXIT42_RELEASE_LOCAL_DIR)/arm64-v8a/exit42 \
	$(EXIT42_RELEASE_LOCAL_DIR)/armeabi-v7a/exit42 \
	$(EXIT42_RELEASE_LOCAL_DIR)/arm64-v8a/exit42.bin \
	$(EXIT42_RELEASE_LOCAL_DIR)/armeabi-v7a/exit42.bin

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

$(APK_PATH): $(foreach arch,$(ARCHES),$(APP_JNI_DIR)/$(arch)/$(GADGET_JNI_LIB)) build/.dockerfile_timestamp
	$(DOCKER_RUN_ANDROID) $(GRADLE_BUILD)

bungeegum/$(APK): $(APK_PATH)
	@cp $(APK_PATH) python/src/bungeegum/

build:
	@mkdir -p build

build/.dockerfile_timestamp : Dockerfile | build
	docker build . -t $(BUILD_IMAGE);
	@touch build/.dockerfile_timestamp

dev: build/.dockerfile_timestamp

app: bungeegum/$(APK)

python:
	VERSION=$(VERSION) FRIDA_VERSION=$(FRIDA_VERSION) python3 -m pip install ./python

$(TEST_BINARIES) &: build/.dockerfile_timestamp
	$(DOCKER_RUN_REPO) make -C test/exit42 artifacts

test-binaries: $(TEST_BINARIES)

test: app python test-binaries
	@bash $(TEST_DIR)/run_tests.sh

clean:
	rm -rf android_app/$(PKG_NAME)/build
	rm -rf android_app/.gradle
	rm -rf android_app/gradle_out
	rm -rf $(APP_JNI_DIR)/*
	rm -rf python/src/bungeegum.egg-info
	rm -rf python/src/bungeegum/$(APK)
	rm -rf $(EXIT42_DIR)/build
	rm -rf build

dist-clean: clean
	docker image rm $(BUILD_IMAGE) -f

all: dev app python
