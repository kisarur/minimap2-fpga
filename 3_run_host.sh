#!/bin/bash
# "$AWS_FPGA_REPO_DIR/vitis_setup.sh" should be sourced first (i.e. source $AWS_FPGA_REPO_DIR/vitis_setup.sh)

./minimap2 -ax map-ont -t 8 ~/data/hg38noAlt.idx ~/data/reads.fastq