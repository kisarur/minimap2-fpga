# environment setup for scylla
# aocl help > /dev/null || source /opt/intelFPGA_pro/21.2/hld/init_opencl.sh
# export ACL_BOARD_VENDOR_PATH=/home/kisarul/a10-bsp/

# environment setup for brenner-fpga
aocl help > /dev/null || source init_env.sh
export ACL_BOARD_VENDOR_PATH=/home/kisliy/ocl_emulator/a10_ref_install/
export LD_LIBRARY_PATH=/home/kisliy/opt/gcc-9.1.0/lib64:$LD_LIBRARY_PATH # for newer libstdc++.so required by OpenCL Emulator 

# compile kernel code for emulation
rm bin/minimap2_opencl_emul.aocx
aoc -march=emulator -v device/minimap2_opencl.cl -o bin/minimap2_opencl_emul.aocx
# aoc -march=emulator -v device/minimap2_opencl.cl -o bin/minimap2_opencl_emul.aocx -I $INTELFPGAOCLSDKROOT/include/kernel_headers

# for intermediate compilation while generating OpenCL reports 
# aoc -rtl device/minimap2_opencl.cl -o bin/minimap2_opencl_emul.aocr -board=a10gx -report # scylla
# aoc -rtl device/minimap2_opencl.cl -o bin/minimap2_opencl_emul.aocr -board=pac_a10 -report # brenner-fpga

# compile host code for hardware emulation
sed -i '/static bool use_emulator/c\static bool use_emulator = true;' chain_hardware.cpp
make clean
make -j

# run host with hardware emulation
# bin/host -ax map-ont -t 20 /storage/hasindu/genome/human_genome/hg38noAlt.idx /storage/hasindu/NA12878_prom_subsample/reads.fastq > /dev/null # scylla
bin/host -ax map-ont -t 20 /share/ScratchGeneral/kisliy/minimap2_inout/hg38noAlt.idx /share/ScratchGeneral/kisliy/minimap2_inout/reads.fastq > /dev/null # brenner-fpga
# bin/host -ax map-ont -t 1 /share/ScratchGeneral/kisliy/minimap2_inout/hg38noAlt.idx /share/ScratchGeneral/kisliy/minimap2_inout/reads.fastq # brenner-fpga