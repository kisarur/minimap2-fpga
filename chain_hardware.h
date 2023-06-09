#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <cstring>
#include "xcl2.hpp"

#include <sys/time.h>
#include <sys/resource.h>

#include <sstream>
#include <iostream>
#include <fstream>
#include <string>

#include "minimap.h"

// Parameters used for HW/SW split (ONT)
#define ONT_K1_HW 0.00029920281819506773
#define ONT_K2_HW 1.2153902649654212e-05
#define ONT_C_HW 0.31943459842651833
#define ONT_K_SW 5.234146622662154e-06
#define ONT_C_SW -1.0015246428158706

// Parameters used for HW/SW split (PacBio CCS)
#define PBCCS_K1_HW 0.00015880136988084205
#define PBCCS_K2_HW 2.0434022672867257e-05
#define PBCCS_C_HW 0.29147412805014916
#define PBCCS_K_SW 3.0803281020398428e-06
#define PBCCS_C_SW -5.074490710236282

#define XCLBIN_FILE "bin/minimap2_opencl.awsxclbin" // use this for execution on AWS F1 FPGA

// #define FIND_HWSW_PARAMS  // to print details that are used to find HW/SW split parameters above 

// #define DEBUG_HW          // chain_hardware.cpp (to print out steps in hardware processing)
// #define VERIFY_OUTPUT       // chain.c (to run both on software and hardware and cross-check the outputs)

// used for measuring the time taken for each chaining task (only the time taken by the section computed on hardware/software)
// this also includes the overhead taken for threshold computation and extra malloc for trip_count
// #define MEASURE_CHAINING_TIME // chain.c

// #define MEASURE_CORE_CHAINING_TIME // chain.c (to measure total time taken for core part of chaining. IMPORTANT: minimap2 should be run with 1 thread to get accurate timing)

// #define MEASURE_CHAINING_TIME_HW_FINE // chain_hardware.cpp (measures chaining time and wait time seperately in hardware chaining)
 
#define EXTRA_ELEMS 0 // added to temporarily fix the issue with parallel execution of OpenCL hardware kernels 
                        // (i.e. all input/output arrays used in hardware chaining are filled with EXTRA_ELEMS no. of elements)

#define PROCESS_ON_SW_IF_HW_BUSY // controls whether to process chaining tasks (chosen for hardware) on software if it's more suitable to do so

#define ENABLE_MAX_SKIP_ON_SW // enables max_skip heuristic for chaining on software

using namespace std;

// Important: don't change the values below unless you recompile hardware code (device/minimap2_opencl.cl)
#define NUM_HW_KERNELS 1
#define TRIPCOUNT_PER_SUBPART 128
#define MAX_SUBPARTS 8
#define MAX_TRIPCOUNT (TRIPCOUNT_PER_SUBPART * MAX_SUBPARTS)

#define DEVICE_MAX_N 332000000
#define BUFFER_MAX_N (DEVICE_MAX_N / 2)
#define BUFFER_N (BUFFER_MAX_N / 32)  // can change the divisor

#define STRING_BUFFER_LEN 1024

int run_chaining_on_hw(cl_long n, cl_int max_dist_x, cl_int max_dist_y, cl_int bw, cl_int q_span, cl_float avg_qspan,
                mm128_t * a, cl_int* f, cl_int* p, cl_uchar* num_subparts, cl_long total_subparts, int tid, float hw_time_pred, float sw_time_pred);
bool hardware_init(long, char *);
void cleanup();
void checkError(cl_int err, const string message);



