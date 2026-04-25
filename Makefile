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
FRIDA_VERSION := 17.9.1

GADGET_ARM_SO := frida-gadget-$(FRIDA_VERSION)-android-arm.so
GADGET_ARM64_SO := frida-gadget-$(FRIDA_VERSION)-android-arm64.so
GADGET_JNI_LIB := libfrida-gadget.so

APP_JNI_DIR := $(ROOT_DIR)/android_app/$(PKG_NAME)/src/main/jniLibs
CURRENT_UID_GID := $(shell id -u):$(shell id -g)
BUILD_IMAGE := bungeegum/android_apk_builder:gradle-9.4.1-sdk-24
ARCHES := armeabi-v7a arm64-v8a

BUILD_DIR := build
SRC_DIR := python/src/bungeegum
INSTALL_DIR := $(BUILD_DIR)/python/src/bungeegum
FORK_EXEC := fork_exec.js
RUN_SC := run_shellcode.js
SRC_PY :=  $(wildcard $(SRC_DIR)/*.py)

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

$(APK_PATH): $(foreach arch,$(ARCHES),$(APP_JNI_DIR)/$(arch)/$(GADGET_JNI_LIB))
	docker run -it -u $(CURRENT_UID_GID) -v "$(ROOT_DIR)"/android_app:/app -w /app $(BUILD_IMAGE) $(GRADLE_BUILD)

bungeegum/$(APK): $(APK_PATH)
	@cp $(APK_PATH) python/src/bungeegum/

# frida-compile the native bridge into the fork_exec.js script
$(INSTALL_DIR)/$(FORK_EXEC): $(SRC_DIR)/_$(FORK_EXEC)
	@cp $< $(INSTALL_DIR)
	docker run -u $(CURRENT_UID_GID) -v "$(ROOT_DIR)/$(INSTALL_DIR)":/python -w /python -e OPENSSL_FORCE_FIPS_MODE=0 $(BUILD_IMAGE) /bin/bash -c "frida-compile _fork_exec.js -o fork_exec.js"
	rm $(INSTALL_DIR)/_$(FORK_EXEC)

# frida-compile the native bridge into the run_shellcode.js script
$(INSTALL_DIR)/$(RUN_SC): $(SRC_DIR)/_$(RUN_SC)
	@cp $< $(INSTALL_DIR)
	docker run -u $(CURRENT_UID_GID) -v "$(ROOT_DIR)/$(INSTALL_DIR)":/python -w /python -e OPENSSL_FORCE_FIPS_MODE=0 $(BUILD_IMAGE) /bin/bash -c "frida-compile _run_shellcode.js -o run_shellcode.js"
	rm $(INSTALL_DIR)/_$(RUN_SC)

$(BUILD_DIR)/python: $(SRC_PY)
	@mkdir -p $(BUILD_DIR)/python
	@cp -r python/* $@/
	docker run -u $(CURRENT_UID_GID) -v "$(ROOT_DIR)/$(INSTALL_DIR)":/python -w /python -e OPENSSL_FORCE_FIPS_MODE=0 $(BUILD_IMAGE) /bin/bash -c "npm install frida-java-bridge"

build:
	@mkdir -p build

build/.dockerfile_timestamp : Dockerfile | build
	@touch build/.dockerfile_timestamp
	docker build --build-arg HOST_UID=$(shell id -u) --build-arg HOST_GID=$(shell id -g) -t $(BUILD_IMAGE) .;

dev: build/.dockerfile_timestamp

app: bungeegum/$(APK) $(BUILD_DIR)/python $(INSTALL_DIR)/$(FORK_EXEC) $(INSTALL_DIR)/$(RUN_SC)

python: app
	VERSION=$(VERSION) FRIDA_VERSION=$(FRIDA_VERSION) python3 -m pip install $(BUILD_DIR)/python


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
	rm -rf build

dist-clean: clean
	docker image rm $(BUILD_IMAGE) -f

all: dev app python
