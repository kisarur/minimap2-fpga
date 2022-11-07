#include "chain_hardware.h"
#include "mmpriv.h"

// control whether the emulator should be used.
static bool use_emulator = false;

using namespace aocl_utils;

// OpenCL runtime configuration
static cl_platform_id platform = NULL;
static cl_device_id device = NULL;
static cl_context context = NULL;
static cl_command_queue queue[NUM_HW_KERNELS] = {NULL};
static cl_kernel kernels[NUM_HW_KERNELS] = {NULL};
static cl_program program = NULL;

// For input and output buffers
cl_mem input_a_buf[NUM_HW_KERNELS];
cl_mem input_num_subparts_buf[NUM_HW_KERNELS];
cl_mem output_f_buf[NUM_HW_KERNELS];
cl_mem output_p_buf[NUM_HW_KERNELS];

pthread_mutex_t hw_lock[NUM_HW_KERNELS] = {PTHREAD_MUTEX_INITIALIZER};

// int kernel_status[NUM_HW_KERNELS] = {0};
// pthread_mutex_t status_lock[NUM_HW_KERNELS] = {PTHREAD_MUTEX_INITIALIZER};


// Run chaining on OpenCL hardware
int run_chaining_on_hw(cl_long n, cl_int max_dist_x, cl_int max_dist_y, cl_int bw, cl_int q_span, cl_float avg_qspan_scaled,
                mm128_t * a, cl_int* f, cl_int* p, cl_uchar* num_subparts, cl_long total_subparts, int tid) {
    
    if (n == 0) {
        return 0;
    }
            
    if (n > BUFFER_N) {
        fprintf(stderr, "Error: The size of the call (n = %ld) exceeds buffer size (%d). Process this read on SW?\n", n, BUFFER_N);
        exit(1);
    }


#ifdef MEASURE_CHAINING_TIME_HW_FINE    
    double start = realtime();
#endif
    
    // scheduling 0 (basic scheduling)
#if defined(VERIFY_OUTPUT) || !defined(PROCESS_ON_SW_IF_HW_BUSY)
    pthread_mutex_lock(&hw_lock[0]);
#else
    int ret = pthread_mutex_trylock(&hw_lock[0]);
    if (ret != 0) return -1;
#endif
    int kernel_id = 0;
    
    // scheduling 1
    /* int kernel_id = -1;
    int ret = -1;
    while (ret != 0) {
        kernel_id = (kernel_id + 1) % NUM_HW_KERNELS;
        ret = pthread_mutex_trylock(&hw_lock[kernel_id]);
    }  */

    /* 
    // scheduling 2
    int kernel_id = -1;
    int ret = -1;
    while (ret != 0) {
        kernel_id++;
        if (kernel_id >= NUM_HW_KERNELS) {
            kernel_id = 0;
        }
        ret = pthread_mutex_trylock(&hw_lock[kernel_id]);
    } */
   

    /*
    // scheduling 3. IMPORTANT: unlock the mutex after chaining is done (i.e. uncomment the lines at the end of chaining)
    int i = 0;
    int kernel_id = -1;
    while (kernel_id == -1) {
        pthread_mutex_lock(&status_lock[i]);
        if (kernel_status[i] == 0) {
            kernel_status[i] = 1;
            kernel_id = i;
        }
        pthread_mutex_unlock(&status_lock[i]);
        i = (i + 1) % NUM_HW_KERNELS;        
    }
    pthread_mutex_lock(&hw_lock[kernel_id]);
    */

#ifdef MEASURE_CHAINING_TIME_HW_FINE    
    double kernel_start = realtime();
#endif

    cl_event write_event[2];
    cl_event kernel_event[1];
    cl_event read_event[2];
    cl_int status;

    // Transfer inputs to device.
    status = clEnqueueWriteBuffer(queue[kernel_id], input_a_buf[kernel_id], CL_FALSE,
        0, (n + EXTRA_ELEMS) * sizeof(cl_ulong2), a, 0, NULL, &write_event[0]);
    checkError(status, "Failed to transfer input a");

    status = clEnqueueWriteBuffer(queue[kernel_id], input_num_subparts_buf[kernel_id], CL_FALSE,
        0, (n + EXTRA_ELEMS) * sizeof(cl_uchar), num_subparts, 0, NULL, &write_event[1]);
    checkError(status, "Failed to transfer input num_subparts");

    // Wait until the a trasfer is completed.
    //clWaitForEvents(1, write_event);

#ifdef DEBUG_HW
    fprintf(stderr, "[INFO] n = %ld on kernel_id = %d input transfer completed\n", n, kernel_id);
#endif
    
    // Set the kernel arguments.
    status = clSetKernelArg(kernels[kernel_id], 0, sizeof(cl_long), &total_subparts);
    checkError(status, "Failed to set argument 0");                

    status = clSetKernelArg(kernels[kernel_id], 1, sizeof(cl_int), &max_dist_x);
    checkError(status, "Failed to set argument 1");

    status = clSetKernelArg(kernels[kernel_id], 2, sizeof(cl_int), &max_dist_y);
    checkError(status, "Failed to set argument 2");

    status = clSetKernelArg(kernels[kernel_id], 3, sizeof(cl_int), &bw);
    checkError(status, "Failed to set argument 3");

    status = clSetKernelArg(kernels[kernel_id], 4, sizeof(cl_int), &q_span);
    checkError(status, "Failed to set argument 4");

    status = clSetKernelArg(kernels[kernel_id], 5, sizeof(cl_float), &avg_qspan_scaled);
    checkError(status, "Failed to set argument 5");

    status = clSetKernelArg(kernels[kernel_id], 6, sizeof(cl_mem), &input_a_buf[kernel_id]);
    checkError(status, "Failed to set argument 6");

    status = clSetKernelArg(kernels[kernel_id], 7, sizeof(cl_mem), &output_f_buf[kernel_id]);
    checkError(status, "Failed to set argument 7");

    status = clSetKernelArg(kernels[kernel_id], 8, sizeof(cl_mem), &output_p_buf[kernel_id]);
    checkError(status, "Failed to set argument 8");

    status = clSetKernelArg(kernels[kernel_id], 9, sizeof(cl_mem), &input_num_subparts_buf[kernel_id]);
    checkError(status, "Failed to set argument 9");

    status = clEnqueueTask(queue[kernel_id], kernels[kernel_id], 2, write_event, &kernel_event[0]);
    checkError(status, "Failed to launch kernel");

    // Wait until the kernel work is completed.
    //clWaitForEvents(1, kernel_event);

#ifdef DEBUG_HW
    fprintf(stderr, "[INFO] n = %ld on kernel_id = %d kernel completed\n", n, kernel_id);
#endif

    // Read the results. This is the final operation.
    status = clEnqueueReadBuffer(queue[kernel_id], output_f_buf[kernel_id], CL_FALSE,
        0, (n + EXTRA_ELEMS) * sizeof(cl_int), f, 1, kernel_event, &read_event[0]);

    status = clEnqueueReadBuffer(queue[kernel_id], output_p_buf[kernel_id], CL_FALSE,
        0, (n + EXTRA_ELEMS) * sizeof(cl_int), p, 1, kernel_event, &read_event[1]);

    // Wait for read events to finish.
    //clWaitForEvents(3, read_event);
    clFinish(queue[kernel_id]);

#ifdef DEBUG_HW
    fprintf(stderr, "[INFO] n = %ld on kernel_id = %d output transfer completed\n", n, kernel_id);
#endif

    // Release events
    clReleaseEvent(write_event[0]);
    clReleaseEvent(write_event[1]);
    clReleaseEvent(kernel_event[0]);
    for (int i = 0; i < 2; i++) {
        clReleaseEvent(read_event[i]);
    }

    // pthread_mutex_unlock(&hw_lock[kernel_id]);
    pthread_mutex_unlock(&hw_lock[0]);

    /* 
    pthread_mutex_lock(&status_lock[kernel_id]);
    kernel_status[kernel_id] = 0;
    pthread_mutex_unlock(&status_lock[kernel_id]);
    */

 
#ifdef MEASURE_CHAINING_TIME_HW_FINE    
    fprintf(stderr, "tid: %d, kernel_id: %d, queued_time: %.3f, start_time: %.3f, end_time: %.3f\n", tid, kernel_id, start * 1000, kernel_start * 1000, realtime() * 1000);
#endif 

    return 0;

}


/////// HELPER FUNCTIONS ///////

static void device_info_ulong( cl_device_id device, cl_device_info param, const char* name);
static void device_info_uint( cl_device_id device, cl_device_info param, const char* name);
static void device_info_bool( cl_device_id device, cl_device_info param, const char* name);
static void device_info_string( cl_device_id device, cl_device_info param, const char* name);
static void display_device_info( cl_device_id device );

bool hardware_init(long buf_size) {
    cl_int status;

    if (!setCwdToExeDir()) {
        return false;
    }

    // Get the OpenCL platform.
    if (use_emulator) {
        platform = findPlatform("Intel(R) FPGA Emulation Platform for OpenCL(TM)");
    } else {
        platform = findPlatform("Intel(R) FPGA SDK for OpenCL(TM)");
    }
    if (platform == NULL) {
        fprintf(stderr, "ERROR: Unable to find Intel(R) FPGA OpenCL platform.\n");
        return false;
    }

    // User-visible output - Platform information
    {
        char char_buffer[STRING_BUFFER_LEN];
        fprintf(stderr, "Querying platform for info:\n");
        fprintf(stderr, "==========================\n");
        clGetPlatformInfo(platform, CL_PLATFORM_NAME, STRING_BUFFER_LEN, char_buffer, NULL);
        fprintf(stderr, "%-40s = %s\n", "CL_PLATFORM_NAME", char_buffer);
        clGetPlatformInfo(platform, CL_PLATFORM_VENDOR, STRING_BUFFER_LEN, char_buffer, NULL);
        fprintf(stderr, "%-40s = %s\n", "CL_PLATFORM_VENDOR ", char_buffer);
        clGetPlatformInfo(platform, CL_PLATFORM_VERSION, STRING_BUFFER_LEN, char_buffer, NULL);
        fprintf(stderr, "%-40s = %s\n\n", "CL_PLATFORM_VERSION ", char_buffer);
    }

    // Query the available OpenCL devices.
    scoped_array<cl_device_id> devices;
    cl_uint num_devices;

    devices.reset(getDevices(platform, CL_DEVICE_TYPE_ALL, &num_devices));

    // We'll just use the first device.
    device = devices[0];

    // Display some device information.
    display_device_info(device);

    // Create the context.
    context = clCreateContext(NULL, 1, &device, &oclContextCallback, NULL, &status);
    checkError(status, "Failed to create context");

    // Create the program.
    std::string binary_file;
    if (use_emulator) {
        binary_file = getBoardBinaryFile("minimap2_opencl_emul", device);
    } else {
        binary_file = getBoardBinaryFile("minimap2_opencl", device);
    }
    fprintf(stderr, "Using AOCX: %s\n", binary_file.c_str());
    program = createProgramFromBinary(context, binary_file.c_str(), &device, 1);

    // Build the program that was just created.
    status = clBuildProgram(program, 0, NULL, "", NULL, NULL);
    checkError(status, "Failed to build program");

    // Create the kernels - name passed in here must match kernel names in the
    // original CL file, that was compiled into an AOCX file using the AOC tool
    // This also creates a seperate command queue for each kernel
    for (int i = 0; i < NUM_HW_KERNELS; i++) {
        // Generate the kernel name (minimap2_opencl0, minimap2_opencl1, minimap2_opencl2, etc.), as defined in the CL file
        std::ostringstream kernel_name;
        kernel_name << "minimap2_opencl" << i;

        kernels[i] = clCreateKernel(program, kernel_name.str().c_str(), &status);
        checkError(status, "Failed to create kernel");

        // Create a seperate queue for kernel.
        queue[i] = clCreateCommandQueue(context, device, CL_QUEUE_PROFILING_ENABLE, &status);
        checkError(status, "Failed to create command queue");
    }

    // Create buffers for each kernel
    for (int i = 0; i < NUM_HW_KERNELS; i++) {
        // Input buffers
        input_a_buf[i] = clCreateBuffer(context, CL_MEM_READ_ONLY,
                                        buf_size * sizeof(cl_ulong2), NULL, &status);
        checkError(status, "Failed to create buffer for input a");

        input_num_subparts_buf[i] = clCreateBuffer(context, CL_MEM_READ_ONLY,
                                        buf_size * sizeof(cl_uchar), NULL, &status);
        checkError(status, "Failed to create buffer for input num_subparts");

        // Output buffers
        output_f_buf[i] = clCreateBuffer(context, CL_MEM_WRITE_ONLY,
                                            buf_size * sizeof(cl_int), NULL, &status);
        checkError(status, "Failed to create buffer for f");
        
        output_p_buf[i] = clCreateBuffer(context, CL_MEM_WRITE_ONLY,
                                            buf_size * sizeof(cl_int), NULL, &status);
        checkError(status, "Failed to create buffer for p");
    }

    return true;
}

// Free the resources allocated during initialization
void cleanup() {
    if (kernels) {
        for (int i = 0; i < NUM_HW_KERNELS; i++) {
            clReleaseKernel(kernels[i]);
        }
    }

    if (input_a_buf) {
        for (int i = 0; i < NUM_HW_KERNELS; i++) {
            clReleaseMemObject(input_a_buf[i]);
        }
    }
    if (input_num_subparts_buf) {
        for (int i = 0; i < NUM_HW_KERNELS; i++) {
            clReleaseMemObject(input_num_subparts_buf[i]);
        }
    }
    if (output_f_buf) {
        for (int i = 0; i < NUM_HW_KERNELS; i++) {
            clReleaseMemObject(output_f_buf[i]);
        }
    }
    if (output_p_buf) {
        for (int i = 0; i < NUM_HW_KERNELS; i++) {
            clReleaseMemObject(output_p_buf[i]);
        }
    }
    if (program) {
        clReleaseProgram(program);
    }
    if (queue) {
        for (int i = 0; i < NUM_HW_KERNELS; i++) {
            clReleaseCommandQueue(queue[i]);
        }
    }
    if (context) {
        clReleaseContext(context);
    }
}

// Helper functions to display parameters returned by OpenCL queries
static void device_info_ulong(cl_device_id device, cl_device_info param, const char* name) {
    cl_ulong a;
    clGetDeviceInfo(device, param, sizeof(cl_ulong), &a, NULL);
    fprintf(stderr, "%-40s = %lu\n", name, a);
}
static void device_info_uint(cl_device_id device, cl_device_info param, const char* name) {
    cl_uint a;
    clGetDeviceInfo(device, param, sizeof(cl_uint), &a, NULL);
    fprintf(stderr, "%-40s = %u\n", name, a);
}
static void device_info_bool(cl_device_id device, cl_device_info param, const char* name) {
    cl_bool a;
    clGetDeviceInfo(device, param, sizeof(cl_bool), &a, NULL);
    fprintf(stderr, "%-40s = %s\n", name, (a ? "true" : "false"));
}
static void device_info_string(cl_device_id device, cl_device_info param, const char* name) {
    char a[STRING_BUFFER_LEN];
    clGetDeviceInfo(device, param, STRING_BUFFER_LEN, &a, NULL);
    fprintf(stderr, "%-40s = %s\n", name, a);
}

// Query and display OpenCL information on device and runtime environment
static void display_device_info(cl_device_id device) {
    fprintf(stderr, "Querying device for info:\n");
    fprintf(stderr, "========================\n");
    device_info_string(device, CL_DEVICE_NAME, "CL_DEVICE_NAME");
    device_info_string(device, CL_DEVICE_VENDOR, "CL_DEVICE_VENDOR");
    device_info_uint(device, CL_DEVICE_VENDOR_ID, "CL_DEVICE_VENDOR_ID");
    device_info_string(device, CL_DEVICE_VERSION, "CL_DEVICE_VERSION");
    device_info_string(device, CL_DRIVER_VERSION, "CL_DRIVER_VERSION");
    device_info_uint(device, CL_DEVICE_ADDRESS_BITS, "CL_DEVICE_ADDRESS_BITS");
    device_info_bool(device, CL_DEVICE_AVAILABLE, "CL_DEVICE_AVAILABLE");
    device_info_bool(device, CL_DEVICE_ENDIAN_LITTLE, "CL_DEVICE_ENDIAN_LITTLE");
    device_info_ulong(device, CL_DEVICE_GLOBAL_MEM_CACHE_SIZE, "CL_DEVICE_GLOBAL_MEM_CACHE_SIZE");
    device_info_ulong(device, CL_DEVICE_GLOBAL_MEM_CACHELINE_SIZE, "CL_DEVICE_GLOBAL_MEM_CACHELINE_SIZE");
    device_info_ulong(device, CL_DEVICE_GLOBAL_MEM_SIZE, "CL_DEVICE_GLOBAL_MEM_SIZE");
    device_info_bool(device, CL_DEVICE_IMAGE_SUPPORT, "CL_DEVICE_IMAGE_SUPPORT");
    device_info_ulong(device, CL_DEVICE_LOCAL_MEM_SIZE, "CL_DEVICE_LOCAL_MEM_SIZE");
    device_info_ulong(device, CL_DEVICE_MAX_CLOCK_FREQUENCY, "CL_DEVICE_MAX_CLOCK_FREQUENCY");
    device_info_ulong(device, CL_DEVICE_MAX_COMPUTE_UNITS, "CL_DEVICE_MAX_COMPUTE_UNITS");
    device_info_ulong(device, CL_DEVICE_MAX_CONSTANT_ARGS, "CL_DEVICE_MAX_CONSTANT_ARGS");
    device_info_ulong(device, CL_DEVICE_MAX_CONSTANT_BUFFER_SIZE, "CL_DEVICE_MAX_CONSTANT_BUFFER_SIZE");
    device_info_uint(device, CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS, "CL_DEVICE_MAX_WORK_ITEM_DIMENSIONS");
    device_info_uint(device, CL_DEVICE_MEM_BASE_ADDR_ALIGN, "CL_DEVICE_MEM_BASE_ADDR_ALIGN");
    device_info_uint(device, CL_DEVICE_MIN_DATA_TYPE_ALIGN_SIZE, "CL_DEVICE_MIN_DATA_TYPE_ALIGN_SIZE");
    device_info_uint(device, CL_DEVICE_PREFERRED_VECTOR_WIDTH_CHAR, "CL_DEVICE_PREFERRED_VECTOR_WIDTH_CHAR");
    device_info_uint(device, CL_DEVICE_PREFERRED_VECTOR_WIDTH_SHORT, "CL_DEVICE_PREFERRED_VECTOR_WIDTH_SHORT");
    device_info_uint(device, CL_DEVICE_PREFERRED_VECTOR_WIDTH_INT, "CL_DEVICE_PREFERRED_VECTOR_WIDTH_INT");
    device_info_uint(device, CL_DEVICE_PREFERRED_VECTOR_WIDTH_LONG, "CL_DEVICE_PREFERRED_VECTOR_WIDTH_LONG");
    device_info_uint(device, CL_DEVICE_PREFERRED_VECTOR_WIDTH_FLOAT, "CL_DEVICE_PREFERRED_VECTOR_WIDTH_FLOAT");
    device_info_uint(device, CL_DEVICE_PREFERRED_VECTOR_WIDTH_DOUBLE, "CL_DEVICE_PREFERRED_VECTOR_WIDTH_DOUBLE");

    {
        cl_command_queue_properties ccp;
        clGetDeviceInfo(device, CL_DEVICE_QUEUE_PROPERTIES, sizeof(cl_command_queue_properties), &ccp, NULL);
        fprintf(stderr, "%-40s = %s\n", "Command queue out of order? ", ((ccp & CL_QUEUE_OUT_OF_ORDER_EXEC_MODE_ENABLE) ? "true" : "false"));
        fprintf(stderr, "%-40s = %s\n", "Command queue profiling enabled? ", ((ccp & CL_QUEUE_PROFILING_ENABLE) ? "true" : "false"));
    }
}
