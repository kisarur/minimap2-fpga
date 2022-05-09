#!/bin/bash

FILE=minimap2_opencl

aocl help > /dev/null || source ../init_env.sh
rm -rf bin/*
aoc device/$FILE.cl -o bin/$FILE.aocx -board=pac_a10 -report
mv bin/$FILE.aocx bin/$FILE.tmp.aocx
printf 'Y\nY\n' | $AOCL_BOARD_PACKAGE_ROOT/linux64/libexec/sign_aocx.sh -H openssl_manager -i bin/$FILE.tmp.aocx -r NULL -k NULL -o bin/$FILE.aocx
rm bin/$FILE.tmp.aocx

