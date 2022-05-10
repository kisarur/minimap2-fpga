#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <cstring>
#include "CL/opencl.h"
#include "AOCLUtils/aocl_utils.h"

#include <sys/time.h>
#include <sys/resource.h>

#include <sstream>
#include <iostream>
#include <fstream>
#include <string>

#include "minimap.h"

//#define DEBUG_HW          // chain_hardware.cpp (to print out steps in hardware processing)
//#define VERIFY_OUTPUT       // chain.c (to run both on software and hardware and cross-check the outputs)
//#define MIMIC_HW            // chain_hardware.cpp (to mimic hardware on software -- used for debugging with logical hardware simulation)

// used for measuring the time taken for each chaining task (only the time taken by the section computed on hardware/software)
// this also includes the overhead taken for threshold computation and extra malloc for trip_count
// #define MEASURE_CHAINING_TIME // chain.c

// #define MEASURE_CHAINING_TIME_HW_FINE // chain_hardware.cpp (measures chaining time and wait time seperately in hardware chaining)
 
#define EXTRA_ELEMS 100 // added to temporarily fix the issue with parallel execution of OpenCL hardware kernels 
                        // (i.e. all input/output arrays used in hardware chaining are filled with EXTRA_ELEMS no. of elements)

using namespace std;

// threshold for SW-HW split (0 - all on hardware, 1 - all on software)
#define BETTER_ON_HW_THRESH 0.2

// Important: don't change the value below unless you recompile hardware code (device/minimap2_opencl.cl)
#define NUM_HW_KERNELS 4

#define DEVICE_MAX_N 332000000
#define BUFFER_MAX_N (DEVICE_MAX_N / 2)
#define BUFFER_N (BUFFER_MAX_N / 32)  // can change the divisor

#define STRING_BUFFER_LEN 1024

int run_chaining_on_hw(cl_long n, cl_int max_dist_x, cl_int max_dist_y, cl_int bw, cl_float avg_qspan,
                mm128_t * a, cl_int* f, cl_int* p, cl_int* v, cl_int * trip_count, int tid);
bool hardware_init(long);
void cleanup();



