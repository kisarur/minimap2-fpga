exit_error () {
    echo "[ERROR] "$1
    exit 1
}

check_error () {
    if [ $? -ne 0 ]; then
        exit_error "$1"
    fi
}

if [ "$#" -ne 3 ]; then
    exit_error "Usage: $0 <minimap2_configuration(map-ont/asm20)> <reference> <query>"
fi

mm2_config=$1
reference=$(realpath $2)
reads=$(realpath $3)

# get minimap2_fpga_opencl from GitHub if it's not already downloaded
if [ ! -d minimap2_fpga_param_search  ]; then
    git clone git@github.com:kisarur/minimap2_fpga_opencl.git -b minimap2_v2.18_fpga_xilinx minimap2_fpga_param_search
    check_error "Git clone failed."
    echo "[INFO] Git clone success."
fi

# enabel FIND_HWSW_PARAMS macro in chain_hardware.h and compile
cd minimap2_fpga_param_search
sed -i '/#define FIND_HWSW_PARAMS/c\#define FIND_HWSW_PARAMS' chain_hardware.h
make host -j
check_error "Compilation failed."
echo "[INFO] Compilation success."

# run minimap2_fpga with the given training data using a single-thread to output data used for hw/sw split parameter searching
./minimap2_fpga -x $mm2_config -t 1 $reference $reads > /dev/null 2> ../param_data_file.txt
check_error "Run failed. Check param_data_file.txt for details."
echo "[INFO] Run success."

# filter the output generated above
cd ../
grep -w "param" param_data_file.txt | sed 's/\<param\>//g' > param_data_file_filt.txt
check_error "Parameter data file filtering failed."
echo "[INFO] Parameter data file filtering success."
echo ""

# find the HW/SW split parameters and print them
python3 find_params.py param_data_file_filt.txt