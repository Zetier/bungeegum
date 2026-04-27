NDK ?= $(error NDK environment variable must be defined)

PROJECT = exit42

PROJECT_DIR = $(abspath $(CURDIR))
SRC_DIR = $(addprefix $(PROJECT_DIR)/, src)
JNI_DIR = $(addprefix $(PROJECT_DIR)/, jni)
OUT_DIR = $(addprefix $(PROJECT_DIR)/, build)
DEBUG_OUT_DIR ?= $(addprefix $(OUT_DIR)/, debug)
RELEASE_OUT_DIR ?= $(addprefix $(OUT_DIR)/, release)
RELEASE_LOCAL_OUT_DIR ?= $(addprefix $(RELEASE_OUT_DIR)/, local)
ABIS := armeabi-v7a arm64-v8a

RM ?= rm
CLANG_FORMAT ?= clang-format
NDK_BUILD ?= $(NDK)/ndk-build
TOOLCHAIN_DIR ?= $(NDK)/toolchains/llvm/prebuilt/linux-x86_64/bin
LLVM_OBJCOPY ?= $(TOOLCHAIN_DIR)/llvm-objcopy

AARCH64_CLANG ?= $(TOOLCHAIN_DIR)/aarch64-linux-android21-clang
ARM_CLANG ?= $(TOOLCHAIN_DIR)/armv7a-linux-androideabi21-clang

ELFS := $(foreach abi,$(ABIS),$(RELEASE_LOCAL_OUT_DIR)/$(abi)/$(PROJECT))
SHELLCODE_BLOBS := \
	$(RELEASE_LOCAL_OUT_DIR)/arm64-v8a/$(PROJECT).bin \
	$(RELEASE_LOCAL_OUT_DIR)/armeabi-v7a/$(PROJECT).bin

.PHONY: all
all: debug release shellcode

.PHONY: artifacts
artifacts: $(ELFS) $(SHELLCODE_BLOBS)

.PHONY: shellcode
shellcode: $(SHELLCODE_BLOBS)

.PHONY: debug release
release: $(RELEASE_OUT_DIR)/.stamp

debug: $(DEBUG_OUT_DIR)/.stamp

$(DEBUG_OUT_DIR)/.stamp: $(wildcard $(SRC_DIR)/*) $(wildcard $(JNI_DIR)/*) Makefile
	@mkdir -p $(DEBUG_OUT_DIR)
	@NDK_LIBS_OUT=$(DEBUG_OUT_DIR) NDK_OUT=$(DEBUG_OUT_DIR) NDK_DEBUG=1 PRIVATE_STRIP= $(NDK_BUILD)
	@touch $@

$(RELEASE_OUT_DIR)/.stamp: $(wildcard $(SRC_DIR)/*) $(wildcard $(JNI_DIR)/*) Makefile
	@mkdir -p $(RELEASE_OUT_DIR)
	@NDK_LIBS_OUT=$(RELEASE_OUT_DIR) NDK_OUT=$(RELEASE_OUT_DIR) $(NDK_BUILD)
	@touch $@

$(RELEASE_LOCAL_OUT_DIR)/%/$(PROJECT): $(RELEASE_OUT_DIR)/.stamp
	@test -f $@

$(RELEASE_LOCAL_OUT_DIR)/arm64-v8a/$(PROJECT).shellcode.o: $(SRC_DIR)/$(PROJECT)_shellcode_arm64.S
	@mkdir -p $(@D)
	@$(AARCH64_CLANG) -c -nostdlib $< -o $@

$(RELEASE_LOCAL_OUT_DIR)/arm64-v8a/$(PROJECT).shellcode.elf: $(RELEASE_LOCAL_OUT_DIR)/arm64-v8a/$(PROJECT).shellcode.o
	@$(AARCH64_CLANG) -nostdlib -fuse-ld=lld -Wl,-e,_start -Wl,-Ttext=0x0 $< -o $@

$(RELEASE_LOCAL_OUT_DIR)/armeabi-v7a/$(PROJECT).shellcode.o: $(SRC_DIR)/$(PROJECT)_shellcode_arm.S
	@mkdir -p $(@D)
	@$(ARM_CLANG) -c -nostdlib $< -o $@

$(RELEASE_LOCAL_OUT_DIR)/armeabi-v7a/$(PROJECT).shellcode.elf: $(RELEASE_LOCAL_OUT_DIR)/armeabi-v7a/$(PROJECT).shellcode.o
	@$(ARM_CLANG) -nostdlib -fuse-ld=lld -Wl,-e,_start -Wl,-Ttext=0x0 $< -o $@

$(RELEASE_LOCAL_OUT_DIR)/arm64-v8a/$(PROJECT).bin: $(RELEASE_LOCAL_OUT_DIR)/arm64-v8a/$(PROJECT).shellcode.elf
	@$(LLVM_OBJCOPY) -O binary --only-section=.text $< $@

$(RELEASE_LOCAL_OUT_DIR)/armeabi-v7a/$(PROJECT).bin: $(RELEASE_LOCAL_OUT_DIR)/armeabi-v7a/$(PROJECT).shellcode.elf
	@$(LLVM_OBJCOPY) -O binary --only-section=.text $< $@

.PHONY: build
build:
	@$(NDK_BUILD)

.PHONY: format
format:
	@$(CLANG_FORMAT) -i $(SRC_DIR)/*

.PHONY: clean
clean:
	@$(RM) -rf $(OUT_DIR)
