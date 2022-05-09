
echo export QUARTUS_HOME="/opt/intelFPGA_pro/quartus_19.2.0b57/quartus"
export QUARTUS_HOME="/opt/intelFPGA_pro/quartus_19.2.0b57/quartus"

echo export OPAE_PLATFORM_ROOT="/opt/inteldevstack/a10_gx_pac_ias_1_2_1_pv"
export OPAE_PLATFORM_ROOT="/opt/inteldevstack/a10_gx_pac_ias_1_2_1_pv"

echo export AOCL_BOARD_PACKAGE_ROOT="/opt/inteldevstack/a10_gx_pac_ias_1_2_1_pv/opencl/opencl_bsp"
export AOCL_BOARD_PACKAGE_ROOT="/opt/inteldevstack/a10_gx_pac_ias_1_2_1_pv/opencl/opencl_bsp"
#if ls /dev/intel-fpga-* 1> /dev/null 2>&1; then
#echo source $AOCL_BOARD_PACKAGE_ROOT/linux64/libexec/setup_permissions.sh
#source $AOCL_BOARD_PACKAGE_ROOT/linux64/libexec/setup_permissions.sh >> /dev/null 
#fi
OPAE_PLATFORM_BIN="/opt/inteldevstack/a10_gx_pac_ias_1_2_1_pv/bin"
if [[ ":${PATH}:" = *":${OPAE_PLATFORM_BIN}:"* ]] ;then
    echo "\$OPAE_PLATFORM_ROOT/bin is in PATH already"
else
    echo "Adding \$OPAE_PLATFORM_ROOT/bin to PATH"
    export PATH="${PATH}":"${OPAE_PLATFORM_BIN}"
fi
#echo sudo cp "/opt/inteldevstack/a10_gx_pac_ias_1_2_1_pv/sw/afu_platform_info" /usr/bin/
#sudo cp "/opt/inteldevstack/a10_gx_pac_ias_1_2_1_pv/sw/afu_platform_info" /usr/bin/
#sudo chmod 755 /usr/bin/afu_platform_info

echo export INTELFPGAOCLSDKROOT="/opt/intelFPGA_pro/quartus_19.2.0b57/hld"
export INTELFPGAOCLSDKROOT="/opt/intelFPGA_pro/quartus_19.2.0b57/hld"
echo export ALTERAOCLSDKROOT=$INTELFPGAOCLSDKROOT
export ALTERAOCLSDKROOT=$INTELFPGAOCLSDKROOT

QUARTUS_BIN="/opt/intelFPGA_pro/quartus_19.2.0b57/quartus/bin"
if [[ ":${PATH}:" = *":${QUARTUS_BIN}:"* ]] ;then
    echo "\$QUARTUS_HOME/bin is in PATH already"
else
    echo "Adding \$QUARTUS_HOME/bin to PATH"
    export PATH="${QUARTUS_BIN}":"${PATH}"
fi
echo source $INTELFPGAOCLSDKROOT/init_opencl.sh
source $INTELFPGAOCLSDKROOT/init_opencl.sh >> /dev/null

