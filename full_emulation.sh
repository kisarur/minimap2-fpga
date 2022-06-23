aocl help > /dev/null || source /opt/intelFPGA_pro/21.2/hld/init_opencl.sh
export ACL_BOARD_VENDOR_PATH=/home/kisarul/a10-bsp/

# compile kernel code for emulation
rm -rf bin/minimap2_opencl_emul.aocx
#aoc -rtl device/minimap2_opencl.cl -o bin/minimap2_opencl_emul.aocr -board=a10gx -report # for intermediate compilation while generating reports
aoc -march=emulator -v device/minimap2_opencl.cl -o bin/minimap2_opencl_emul.aocx

# compile host code
make -j

# run host with emulation
bin/host -ax map-ont -t 40 /storage/hasindu/genome/human_genome/hg38noAlt.idx /storage/hasindu/NA12878_prom_subsample/reads.fastq > /dev/null