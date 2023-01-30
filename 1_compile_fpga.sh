#!/bin/bash
# "$AWS_FPGA_REPO_DIR/vitis_setup.sh" should be sourced first (i.e. source $AWS_FPGA_REPO_DIR/vitis_setup.sh)

FILE=minimap2_opencl

# make cleanall // to remove all the previously built hardware files 
make build TARGET=hw DEVICE=$AWS_PLATFORM 
cp build_dir.hw.*.xclbin bin/