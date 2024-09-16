.PHONY: dev app all clean docker-clean test package

.DEFAULT_GOAL := all

ROOT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))

PKG_NAME := com.zetier.bungeegum
APK := $(PKG_NAME)-debug.apk
LIB_DEPS := build/dep/lib
GRADLE_BUILD := gradle assembleDebug -g gradle_out
APK_PATH := $(ROOT_DIR)/android_app/$(PKG_NAME)/build/outputs/apk/debug/$(APK)
FRIDA_DOWNLOADS := https://github.com/frida/frida/releases/download
PYPROJECT := python/pyproject.toml
FRIDA_VERSION := $(shell grep "frida==" $(PYPROJECT) | sed -n 's/.*frida==\([0-9\.]*\).*/\1/p')
VERSION := $(shell python -m setuptools_scm -c $(PYPROJECT))

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

$(APK_PATH): $(foreach arch,$(ARCHES),$(APP_JNI_DIR)/$(arch)/$(GADGET_JNI_LIB))
	docker run -it -u $(CURRENT_UID_GID) -v "$(ROOT_DIR)"/android_app:/app -w /app $(BUILD_IMAGE) $(GRADLE_BUILD)

bungeegum/$(APK): $(APK_PATH)
	@cp $(APK_PATH) python/src/bungeegum/

build:
	@mkdir -p $(ROOT_DIR)/build

build/.dockerfile_timestamp : Dockerfile | build
	@touch build/.dockerfile_timestamp
	docker build . -t $(BUILD_IMAGE);

dev: build/.dockerfile_timestamp

app: bungeegum/$(APK)

dist:
	@mkdir -p $(ROOT_DIR)/dist

dist/bungeegum-$(VERSION)-py3-none-any.whl dist/bungeegum-$(VERSION).tar.gz: app | dist
	python3 -m build --outdir dist python/

package: dist/bungeegum-$(VERSION)-py3-none-any.whl dist/bungeegum-$(VERSION).tar.gz

.PHONY: package-test-setup
package-test-setup: package
	-rm -rf $(ROOT_DIR)/$(VERSION)_venv
	python3 -m venv $(ROOT_DIR)/$(VERSION)_venv
	"$(ROOT_DIR)"/"$(VERSION)_venv"/bin/python3 -m pip install $(ROOT_DIR)/dist/*.whl

.PHONY: test-package
test-package: package-test-setup
	$(call run_tests, "$(ROOT_DIR)"/"$(VERSION)_venv"/bin/bungeegum)

TEST_COMMANDS = \
	"--version && sh -c 'exit 42'" \
	"--elf $(TEST_DIR)/exit42_arm64-v8a" \
	"--shellcode $(TEST_DIR)/exit42_arm64-v8a.bin" \
	"--remote --elf /system/bin/sh --args -c 'return 42;'"

define run_tests
	@if ! out=$$(adb shell getprop ro.product.cpu.abi) || ! [ $$out = arm64-v8a ]; then \
		echo "A single arm64-v8a device must be attached via adb to run tests"; \
		exit 1; \
	fi
	@-adb uninstall $(PKG_NAME);
	@for cmd in $(TEST_COMMANDS); do \
		eval "$(1) $$cmd"; \
		ret=$$?; \
		if [ $$ret -ne 42 ]; then \
			echo "$$cmd returned $$ret"; \
			exit 1; \
		fi; \
	done
endef

test:
	$(call run_tests, "bungeegum")

CLEAN_PATHS = \
	"$(APP_JNI_DIR)/*" \
	"android_app/$(PKG_NAME)/build" \
	"android_app/.gradle" \
	"android_app/gradle_out" \
	"build" \
	"dist" \
	"python/src/__pycache__" \
	"python/src/bungeegum.egg-info" \
	"python/src/bungeegum/$(APK)"

clean:
	@for path in $(CLEAN_PATHS); do \
		rm -rf $$path; \
	done

docker-clean: clean
	docker image rm $(BUILD_IMAGE) -f

all: dev app
