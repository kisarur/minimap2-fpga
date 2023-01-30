#!/bin/bash
# "$AWS_FPGA_REPO_DIR/vitis_setup.sh" should be sourced first (i.e. source $AWS_FPGA_REPO_DIR/vitis_setup.sh)
# "XCLBIN_FILE" chain_hardware.h in should be set to  to "bin/minimap2_opencl.xclbin"

# make cleanall // to remove all the previously built emulation hardware files 
make build TARGET=sw_emu DEVICE=$AWS_PLATFORM 
cp build_dir.sw_emu.*/minimap2_opencl.xclbin bin/

# make clean // to remove previously built software binaries
make host 

make run TARGET=sw_emu DEVICE=$AWS_PLATFORM CMD_ARGS="-ax map-ont -t 8 ~/data/hg38noAlt.idx ~/data/reads.fastq"