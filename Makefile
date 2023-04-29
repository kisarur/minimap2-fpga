#
# Copyright 2019-2021 Xilinx, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# makefile-generator v1.0.3
#

############################## Help Section ##############################
.PHONY: help

help::
	$(ECHO) "Makefile Usage:"
	$(ECHO) "  make all TARGET=<sw_emu/hw_emu/hw> PLATFORM=<FPGA platform> HOST_ARCH=<aarch32/aarch64/x86> EDGE_COMMON_SW=<rootfs and kernel image path>"
	$(ECHO) "      Command to generate the design for specified Target and Shell."
	$(ECHO) ""
	$(ECHO) "  make clean "
	$(ECHO) "      Command to remove the generated non-hardware files."
	$(ECHO) ""
	$(ECHO) "  make cleanall"
	$(ECHO) "      Command to remove all the generated files."
	$(ECHO) ""
	$(ECHO) "  make test PLATFORM=<FPGA platform>"
	$(ECHO) "      Command to run the application. This is same as 'run' target but does not have any makefile dependency."
	$(ECHO) ""
	$(ECHO) "  make sd_card TARGET=<sw_emu/hw_emu/hw> PLATFORM=<FPGA platform> HOST_ARCH=<aarch32/aarch64/x86> EDGE_COMMON_SW=<rootfs and kernel image path>"
	$(ECHO) "      Command to prepare sd_card files."
	$(ECHO) ""
	$(ECHO) "  make run TARGET=<sw_emu/hw_emu/hw> PLATFORM=<FPGA platform> HOST_ARCH=<aarch32/aarch64/x86> EDGE_COMMON_SW=<rootfs and kernel image path>"
	$(ECHO) "      Command to run application in emulation."
	$(ECHO) ""
	$(ECHO) "  make build TARGET=<sw_emu/hw_emu/hw> PLATFORM=<FPGA platform> HOST_ARCH=<aarch32/aarch64/x86> EDGE_COMMON_SW=<rootfs and kernel image path>"
	$(ECHO) "      Command to build xclbin application."
	$(ECHO) ""
	$(ECHO) "  make host HOST_ARCH=<aarch32/aarch64/x86> EDGE_COMMON_SW=<rootfs and kernel image path>"
	$(ECHO) "      Command to build host application."
	$(ECHO) "  By default, HOST_ARCH=x86. HOST_ARCH and EDGE_COMMON_SW is required for SoC shells"
	$(ECHO) ""

############################## Setting up Project Variables ##############################
# Points to top directory of Git repository
COMMON_REPO ?= ./
PWD = $(shell readlink -f .)
XF_PROJ_ROOT = $(shell readlink -f $(COMMON_REPO))

TARGET := hw
HOST_ARCH := x86
SYSROOT := 

include ./utils.mk

XSA := 
ifneq ($(PLATFORM), )
XSA := $(call device2xsa, $(PLATFORM))
endif
TEMP_DIR := ./_x.$(TARGET).$(XSA)
BUILD_DIR := ./build_dir.$(TARGET).$(XSA)

# SoC variables
RUN_APP_SCRIPT = ./run_app.sh
PACKAGE_OUT = ./package.$(TARGET)

LAUNCH_EMULATOR = $(PACKAGE_OUT)/launch_$(TARGET).sh
RESULT_STRING = TEST PASSED

VPP := v++
VPP_PFLAGS := 
CMD_ARGS ?= 
SDCARD := sd_card

include $(XF_PROJ_ROOT)/opencl/includes/opencl/opencl.mk
# CXXFLAGS += $(opencl_CXXFLAGS) -Wall -O0 -g -std=c++1y
CXXFLAGS += $(opencl_CXXFLAGS) -Wall -O2 -g -std=c++1y
LDFLAGS += $(opencl_LDFLAGS) 


########################## Checking if PLATFORM in whitelist #######################
PLATFORM_BLOCKLIST += nodma 
############################## Setting up Host Variables ##############################
#Include Required Host Source Files
CXXFLAGS += -I$(XF_PROJ_ROOT)/opencl/includes/xcl2
HOST_SRCS += $(XF_PROJ_ROOT)/opencl/includes/xcl2/xcl2.cpp ./*.cpp ./main.c
# Host compiler global settings
CXXFLAGS += -fmessage-length=0
LDFLAGS += -lrt -lstdc++ -lm -lz -lpthread

ifneq ($(HOST_ARCH), x86)
	LDFLAGS += --sysroot=$(SYSROOT)
endif

############################## Setting up Kernel Variables ##############################
# Kernel compiler global settings
VPP_FLAGS += -t $(TARGET) --platform $(PLATFORM) --save-temps 
ifneq ($(TARGET), hw)
	VPP_FLAGS += -g
endif



EXECUTABLE = ./minimap2-fpga
EMCONFIG_DIR = $(TEMP_DIR)
EMU_DIR = $(SDCARD)/data/emulation

############################## Declaring Binary Containers ##############################
BINARY_CONTAINERS += $(BUILD_DIR)/minimap2_opencl.xclbin
BINARY_CONTAINER_minimap2_opencl_OBJS += $(TEMP_DIR)/chain0.xo
# BINARY_CONTAINER_minimap2_opencl_OBJS += $(TEMP_DIR)/chain1.xo
# BINARY_CONTAINER_minimap2_opencl_OBJS += $(TEMP_DIR)/chain2.xo
# BINARY_CONTAINER_minimap2_opencl_OBJS += $(TEMP_DIR)/chain3.xo

############################## Setting Targets ##############################
CP = cp -rf

.PHONY: all clean cleanall docs emconfig
all: check-platform check-device $(EXECUTABLE) $(BINARY_CONTAINERS) emconfig sd_card

.PHONY: host
host: $(EXECUTABLE)

.PHONY: build
build: check-vitis check-device $(BINARY_CONTAINERS)

.PHONY: xclbin
xclbin: build

############################## Setting Rules for Binary Containers (Building Kernels) ##############################
$(TEMP_DIR)/chain0.xo: device/minimap2_opencl.cl
	mkdir -p $(TEMP_DIR)
	$(VPP) $(VPP_FLAGS) -c -k chain0 --temp_dir $(TEMP_DIR)  -I'$(<D)' -o'$@' '$<'
# $(TEMP_DIR)/chain1.xo: device/minimap2_opencl.cl
# 	mkdir -p $(TEMP_DIR)
# 	$(VPP) $(VPP_FLAGS) -c -k chain1 --temp_dir $(TEMP_DIR)  -I'$(<D)' -o'$@' '$<'
# $(TEMP_DIR)/chain2.xo: device/minimap2_opencl.cl
# 	mkdir -p $(TEMP_DIR)
# 	$(VPP) $(VPP_FLAGS) -c -k chain2 --temp_dir $(TEMP_DIR)  -I'$(<D)' -o'$@' '$<'
# $(TEMP_DIR)/chain3.xo: device/minimap2_opencl.cl
# 	mkdir -p $(TEMP_DIR)
# 	$(VPP) $(VPP_FLAGS) -c -k chain3 --temp_dir $(TEMP_DIR)  -I'$(<D)' -o'$@' '$<'
$(BUILD_DIR)/minimap2_opencl.xclbin: $(BINARY_CONTAINER_minimap2_opencl_OBJS)
	mkdir -p $(BUILD_DIR)
ifeq ($(HOST_ARCH), x86)
	$(VPP) $(VPP_FLAGS) -l $(VPP_LDFLAGS) --temp_dir $(TEMP_DIR) -o'$(BUILD_DIR)/minimap2_opencl.link.xclbin' $(+)
	$(VPP) -p $(BUILD_DIR)/minimap2_opencl.link.xclbin -t $(TARGET) --platform $(PLATFORM) --package.out_dir $(PACKAGE_OUT) -o $(BUILD_DIR)/minimap2_opencl.xclbin
else
	$(VPP) $(VPP_FLAGS) -l $(VPP_LDFLAGS) --temp_dir $(TEMP_DIR) -o'$(BUILD_DIR)/minimap2_opencl.xclbin' $(+)
endif

############################## Setting Rules for Host (Building Host Executable) ##############################

OBJS=		kthread.o kalloc.o misc.o bseq.o sketch.o sdust.o options.o index.o chain.o align.o hit.o map.o format.o pe.o esterr.o splitidx.o ksw2_ll_sse.o
CFLAGS=		-I$(XF_PROJ_ROOT)/opencl/includes/xcl2 -g -Wall -O2 
CPPFLAGS=	-DHAVE_KALLOC

ifeq ($(arm_neon),) # if arm_neon is not defined
ifeq ($(sse2only),) # if sse2only is not defined
	OBJS+=ksw2_extz2_sse41.o ksw2_extd2_sse41.o ksw2_exts2_sse41.o ksw2_extz2_sse2.o ksw2_extd2_sse2.o ksw2_exts2_sse2.o ksw2_dispatch.o
else                # if sse2only is defined
	OBJS+=ksw2_extz2_sse.o ksw2_extd2_sse.o ksw2_exts2_sse.o
endif
else				# if arm_neon is defined
	OBJS+=ksw2_extz2_neon.o ksw2_extd2_neon.o ksw2_exts2_neon.o
    INCLUDES+=-Isse2neon
ifeq ($(aarch64),)	#if aarch64 is not defined
	CFLAGS+=-D_FILE_OFFSET_BITS=64 -mfpu=neon -fsigned-char
else				#if aarch64 is defined
	CFLAGS+=-D_FILE_OFFSET_BITS=64 -fsigned-char
endif
endif

$(EXECUTABLE): $(HOST_SRCS) $(OBJS) | check-xrt
		$(CXX) -o $@ $^ $(CXXFLAGS) $(LDFLAGS)

.SUFFIXES:.c .o

.c.o:
		$(CXX) -c $(CFLAGS) $(CPPFLAGS) $(CXXFLAGS) $(INCLUDES) $< -o $@

# SSE-specific targets on x86/x86_64

ifeq ($(arm_neon),)   # if arm_neon is defined, compile this target with the default setting (i.e. no -msse2)
ksw2_ll_sse.o:ksw2_ll_sse.c ksw2.h kalloc.h
		$(CC) -c $(CFLAGS) -msse2 $(CPPFLAGS) $(INCLUDES) $< -o $@
endif

ksw2_extz2_sse41.o:ksw2_extz2_sse.c ksw2.h kalloc.h
		$(CC) -c $(CFLAGS) -msse4.1 $(CPPFLAGS) -DKSW_CPU_DISPATCH $(INCLUDES) $< -o $@

ksw2_extz2_sse2.o:ksw2_extz2_sse.c ksw2.h kalloc.h
		$(CC) -c $(CFLAGS) -msse2 -mno-sse4.1 $(CPPFLAGS) -DKSW_CPU_DISPATCH -DKSW_SSE2_ONLY $(INCLUDES) $< -o $@

ksw2_extd2_sse41.o:ksw2_extd2_sse.c ksw2.h kalloc.h
		$(CC) -c $(CFLAGS) -msse4.1 $(CPPFLAGS) -DKSW_CPU_DISPATCH $(INCLUDES) $< -o $@

ksw2_extd2_sse2.o:ksw2_extd2_sse.c ksw2.h kalloc.h
		$(CC) -c $(CFLAGS) -msse2 -mno-sse4.1 $(CPPFLAGS) -DKSW_CPU_DISPATCH -DKSW_SSE2_ONLY $(INCLUDES) $< -o $@

ksw2_exts2_sse41.o:ksw2_exts2_sse.c ksw2.h kalloc.h
		$(CC) -c $(CFLAGS) -msse4.1 $(CPPFLAGS) -DKSW_CPU_DISPATCH $(INCLUDES) $< -o $@

ksw2_exts2_sse2.o:ksw2_exts2_sse.c ksw2.h kalloc.h
		$(CC) -c $(CFLAGS) -msse2 -mno-sse4.1 $(CPPFLAGS) -DKSW_CPU_DISPATCH -DKSW_SSE2_ONLY $(INCLUDES) $< -o $@

ksw2_dispatch.o:ksw2_dispatch.c ksw2.h
		$(CC) -c $(CFLAGS) -msse4.1 $(CPPFLAGS) -DKSW_CPU_DISPATCH $(INCLUDES) $< -o $@

# NEON-specific targets on ARM

ksw2_extz2_neon.o:ksw2_extz2_sse.c ksw2.h kalloc.h
		$(CC) -c $(CFLAGS) $(CPPFLAGS) -DKSW_SSE2_ONLY -D__SSE2__ $(INCLUDES) $< -o $@

ksw2_extd2_neon.o:ksw2_extd2_sse.c ksw2.h kalloc.h
		$(CC) -c $(CFLAGS) $(CPPFLAGS) -DKSW_SSE2_ONLY -D__SSE2__ $(INCLUDES) $< -o $@

ksw2_exts2_neon.o:ksw2_exts2_sse.c ksw2.h kalloc.h
		$(CC) -c $(CFLAGS) $(CPPFLAGS) -DKSW_SSE2_ONLY -D__SSE2__ $(INCLUDES) $< -o $@

# DO NOT DELETE

align.o: minimap.h mmpriv.h bseq.h ksw2.h kalloc.h
bseq.o: bseq.h kvec.h kalloc.h kseq.h
chain.o: minimap.h mmpriv.h bseq.h kalloc.h
esterr.o: mmpriv.h minimap.h bseq.h
example.o: minimap.h kseq.h
format.o: kalloc.h mmpriv.h minimap.h bseq.h
hit.o: mmpriv.h minimap.h bseq.h kalloc.h khash.h
index.o: kthread.h bseq.h minimap.h mmpriv.h kvec.h kalloc.h khash.h
kalloc.o: kalloc.h
ksw2_extd2_sse.o: ksw2.h kalloc.h
ksw2_exts2_sse.o: ksw2.h kalloc.h
ksw2_extz2_sse.o: ksw2.h kalloc.h
ksw2_ll_sse.o: ksw2.h kalloc.h
kthread.o: kthread.h
main.o: bseq.h minimap.h mmpriv.h ketopt.h
map.o: kthread.h kvec.h kalloc.h sdust.h mmpriv.h minimap.h bseq.h khash.h
map.o: ksort.h
misc.o: mmpriv.h minimap.h bseq.h ksort.h
options.o: mmpriv.h minimap.h bseq.h
pe.o: mmpriv.h minimap.h bseq.h kvec.h kalloc.h ksort.h
sdust.o: kalloc.h kdq.h kvec.h ketopt.h sdust.h
sketch.o: kvec.h kalloc.h mmpriv.h minimap.h bseq.h
splitidx.o: mmpriv.h minimap.h bseq.h


emconfig:$(EMCONFIG_DIR)/emconfig.json
$(EMCONFIG_DIR)/emconfig.json:
	emconfigutil --platform $(PLATFORM) --od $(EMCONFIG_DIR)

############################## Setting Essential Checks and Running Rules ##############################
run: all
ifeq ($(TARGET),$(filter $(TARGET),sw_emu hw_emu))
ifeq ($(HOST_ARCH), x86)
	$(CP) $(EMCONFIG_DIR)/emconfig.json .
	XCL_EMULATION_MODE=$(TARGET) $(EXECUTABLE) $(CMD_ARGS)
else
	$(LAUNCH_EMULATOR) -run-app $(RUN_APP_SCRIPT) | tee run_app.log; exit $${PIPESTATUS[0]}
endif
else
ifeq ($(HOST_ARCH), x86)
	$(EXECUTABLE) $(CMD_ARGS)
endif
endif


.PHONY: test
test: $(EXECUTABLE)
ifeq ($(TARGET),$(filter $(TARGET),sw_emu hw_emu))
ifeq ($(HOST_ARCH), x86)
	XCL_EMULATION_MODE=$(TARGET) $(EXECUTABLE) $(CMD_ARGS)
else
	$(LAUNCH_EMULATOR) -run-app $(RUN_APP_SCRIPT) | tee run_app.log; exit $${PIPESTATUS[0]}
endif
else
ifeq ($(HOST_ARCH), x86)
	$(EXECUTABLE) $(CMD_ARGS)
else
	$(ECHO) "Please copy the content of sd_card folder and data to an SD Card and run on the board"
endif
endif


############################## Preparing sdcard ##############################
sd_card: $(BINARY_CONTAINERS) $(EXECUTABLE) gen_run_app
ifneq ($(HOST_ARCH), x86)
	$(VPP) $(VPP_PFLAGS) -p $(BUILD_DIR)/minimap2_opencl.xclbin -t $(TARGET) --platform $(PLATFORM) --package.out_dir $(PACKAGE_OUT) --package.rootfs $(EDGE_COMMON_SW)/rootfs.ext4 --package.sd_file $(SD_IMAGE_FILE) --package.sd_file xrt.ini --package.sd_file $(RUN_APP_SCRIPT) --package.sd_file $(EXECUTABLE) -o minimap2_opencl.xclbin
endif

############################## Cleaning Rules ##############################
# Cleaning stuff
clean:
	-$(RMDIR) $(EXECUTABLE) $(XCLBIN)/{*sw_emu*,*hw_emu*} 
	-$(RMDIR) profile_* TempConfig system_estimate.xtxt *.rpt *.csv 
	-$(RMDIR) device/*.ll *v++* .Xil emconfig.json dltmp* xmltmp* *.log *.jou *.wcfg *.wdb
	-$(RMDIR) gmon.out *.o a.out $(PROG) $(PROG_EXTRA) *~ *.a *.dSYM build dist mappy*.so mappy.c python/mappy.c mappy.egg*

cleanall: clean
	-$(RMDIR) build_dir* sd_card*
	-$(RMDIR) package.*
	-$(RMDIR) _x* *xclbin.run_summary qemu-memory-_* emulation _vimage pl* start_simulation.sh *.xclbin