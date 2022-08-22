// Copyright (C) 2013-2018 Altera Corporation, San Jose, California, USA. All rights reserved.
// Permission is hereby granted, free of charge, to any person obtaining a copy of this
// software and associated documentation files (the "Software"), to deal in the Software
// without restriction, including without limitation the rights to use, copy, modify, merge,
// publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to
// whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or
// substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
// 
// This agreement shall be governed in all respects by the laws of the State of California and
// by the laws of the United States of America.

// Author: Kisaru Liyanage 

#define MM_SEED_SEG_SHIFT  48
#define MM_SEED_SEG_MASK   (0xffULL<<(MM_SEED_SEG_SHIFT))

#define TRIPCOUNT_PER_SUBPART 64

__constant char LogTable256[256] = {
#define LT(n) n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n
	-1, 0, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3,
	LT(4), LT(5), LT(5), LT(6), LT(6), LT(6), LT(6),
	LT(7), LT(7), LT(7), LT(7), LT(7), LT(7), LT(7), LT(7)
};

inline int ilog2_32(unsigned int v)
{
	unsigned int t, tt;
	if ((tt = v>>16)) return (t = tt>>8) ? 24 + LogTable256[t] : 16 + LogTable256[tt];
	return (t = v>>8) ? 8 + LogTable256[t] : LogTable256[v];
}

inline int compute_sc(unsigned long a_x, unsigned long a_y, int f, unsigned long ri, int qi, int max_dist_x, int max_dist_y, int bw, int q_span, float avg_qspan_scaled) 
{
	long dr = ri - a_x; 
    if (dr > max_dist_x || dr <= 0) return 0; // to serve "st"'s purpose (kisaru) 
	int dq = qi - (int)a_y, dd, sc, log_dd;
	if (dq <= 0) return 0; // don't skip if an anchor is used by multiple segments; see below
	if (dq > max_dist_y || dq > max_dist_x) return 0;
	dd = dr > dq? dr - dq : dq - dr;
	if (dd > bw) return 0;
	int min_d = dq < dr? dq : dr;
	sc = min_d > q_span? q_span : dq < dr? dq : dr;
	log_dd = dd? ilog2_32(dd) : 0;
	sc -= (int)(dd * avg_qspan_scaled) + (log_dd>>1);
	sc += f;

	return sc;
}

__kernel void minimap2_opencl0(long total_subparts,
                         int max_dist_x, int max_dist_y, int bw, int q_span, float avg_qspan_scaled, 
						 __global const ulong2 *restrict a,
                         __global int *restrict f, __global int *restrict p,
                         __global const unsigned char *restrict num_subparts)
{
	unsigned long a_x_local0[TRIPCOUNT_PER_SUBPART + 1] = {0};
	int a_y_local0[TRIPCOUNT_PER_SUBPART + 1] = {0};
	int f_local0[TRIPCOUNT_PER_SUBPART + 1] = {0};

	unsigned long a_x_local1[TRIPCOUNT_PER_SUBPART] = {0};
	int a_y_local1[TRIPCOUNT_PER_SUBPART] = {0};
	int f_local1[TRIPCOUNT_PER_SUBPART] = {0};
    
	unsigned long a_x_local2[TRIPCOUNT_PER_SUBPART] = {0};
	int a_y_local2[TRIPCOUNT_PER_SUBPART] = {0};
	int f_local2[TRIPCOUNT_PER_SUBPART] = {0};
    
	unsigned long a_x_local3[TRIPCOUNT_PER_SUBPART] = {0};
	int a_y_local3[TRIPCOUNT_PER_SUBPART] = {0};
	int f_local3[TRIPCOUNT_PER_SUBPART] = {0};

    unsigned long a_x_local4[TRIPCOUNT_PER_SUBPART] = {0};
	int a_y_local4[TRIPCOUNT_PER_SUBPART] = {0};
	int f_local4[TRIPCOUNT_PER_SUBPART] = {0};

    unsigned long a_x_local5[TRIPCOUNT_PER_SUBPART] = {0};
	int a_y_local5[TRIPCOUNT_PER_SUBPART] = {0};
	int f_local5[TRIPCOUNT_PER_SUBPART] = {0};
    
    unsigned long a_x_local6[TRIPCOUNT_PER_SUBPART] = {0};
	int a_y_local6[TRIPCOUNT_PER_SUBPART] = {0};
	int f_local6[TRIPCOUNT_PER_SUBPART] = {0};

    unsigned long a_x_local7[TRIPCOUNT_PER_SUBPART] = {0};
	int a_y_local7[TRIPCOUNT_PER_SUBPART] = {0};
	int f_local7[TRIPCOUNT_PER_SUBPART] = {0};

    unsigned char subparts_processed = 0;
    unsigned char subparts_to_process = 0;

	// fill the score and backtrack arrays
    long i = 0;
	for (long g = 0; g < total_subparts; ++g) {

        // printf("%ld\t%ld\t%d\t%d\n", total_subparts, i, subparts_processed, subparts_to_process);

        if (subparts_processed == 0) {
            ulong2 a_local = __prefetching_load(&a[i]);
            a_x_local0[0] = a_local.x;
		    a_y_local0[0] = (int)a_local.y;
            subparts_to_process = __prefetching_load(&num_subparts[i]);
        }
		
		unsigned long ri = a_x_local0[0];
		int qi = a_y_local0[0];
		
		long max_j = -1;
		int max_f = q_span;

		#pragma unroll
		for (int j = TRIPCOUNT_PER_SUBPART; j > 0; j--) {
			unsigned long a_x_local_j, a_y_local_j;
			int f_local_j;

			if (subparts_processed == 0) {
				a_x_local_j = a_x_local0[j];
				a_y_local_j = a_y_local0[j];
				f_local_j = f_local0[j];
			}

			if (subparts_processed == 1) {
				a_x_local_j = a_x_local1[j - 1];
				a_y_local_j = a_y_local1[j - 1];
				f_local_j = f_local1[j - 1];
			}

            if (subparts_processed == 2) {
				a_x_local_j = a_x_local2[j - 1];
				a_y_local_j = a_y_local2[j - 1];
				f_local_j = f_local2[j - 1];
			}

            if (subparts_processed == 3) {
				a_x_local_j = a_x_local3[j - 1];
				a_y_local_j = a_y_local3[j - 1];
				f_local_j = f_local3[j - 1];
			}

            if (subparts_processed == 4) {
				a_x_local_j = a_x_local4[j - 1];
				a_y_local_j = a_y_local4[j - 1];
				f_local_j = f_local4[j - 1];
			}

            if (subparts_processed == 5) {
				a_x_local_j = a_x_local5[j - 1];
				a_y_local_j = a_y_local5[j - 1];
				f_local_j = f_local5[j - 1];
			}

            if (subparts_processed == 6) {
				a_x_local_j = a_x_local6[j - 1];
				a_y_local_j = a_y_local6[j - 1];
				f_local_j = f_local6[j - 1];
			}

            if (subparts_processed == 7) {
				a_x_local_j = a_x_local7[j - 1];
				a_y_local_j = a_y_local7[j - 1];
				f_local_j = f_local7[j - 1];
			}

            int sc = compute_sc(a_x_local_j, a_y_local_j, f_local_j, ri, qi, max_dist_x, max_dist_y, bw, q_span, avg_qspan_scaled);
			if (sc >= max_f && sc != q_span) {
				max_f = sc;
                if (subparts_processed == 0) max_j = i - j;
                if (subparts_processed == 1) max_j = i - j - TRIPCOUNT_PER_SUBPART;
                if (subparts_processed == 2) max_j = i - j - 2 * TRIPCOUNT_PER_SUBPART;
                if (subparts_processed == 3) max_j = i - j - 3 * TRIPCOUNT_PER_SUBPART;
                if (subparts_processed == 4) max_j = i - j - 4 * TRIPCOUNT_PER_SUBPART;
                if (subparts_processed == 5) max_j = i - j - 5 * TRIPCOUNT_PER_SUBPART;
                if (subparts_processed == 6) max_j = i - j - 6 * TRIPCOUNT_PER_SUBPART;
                if (subparts_processed == 7) max_j = i - j - 7 * TRIPCOUNT_PER_SUBPART;
			}
		}

        if (max_f > f_local0[0]) {
            f[i] = max_f;
            p[i] = max_j;
            f_local0[0] = max_f;
        }

        subparts_processed++;
        
        #pragma unroll
        for (int reg = TRIPCOUNT_PER_SUBPART - 1; reg > 0; reg--) {
            if (subparts_processed == subparts_to_process) {
                f_local7[reg] = f_local7[reg - 1];
                a_x_local7[reg] = a_x_local7[reg - 1];
                a_y_local7[reg] = a_y_local7[reg - 1];
            }
        }

        if (subparts_processed == subparts_to_process) {
            f_local7[0] = f_local6[TRIPCOUNT_PER_SUBPART - 1];
            a_x_local7[0] = a_x_local6[TRIPCOUNT_PER_SUBPART - 1];
            a_y_local7[0] = a_y_local6[TRIPCOUNT_PER_SUBPART - 1];
        }

        #pragma unroll
        for (int reg = TRIPCOUNT_PER_SUBPART - 1; reg > 0; reg--) {
            if (subparts_processed == subparts_to_process) {
                f_local6[reg] = f_local6[reg - 1];
                a_x_local6[reg] = a_x_local6[reg - 1];
                a_y_local6[reg] = a_y_local6[reg - 1];
            }
        }

        if (subparts_processed == subparts_to_process) {
            f_local6[0] = f_local5[TRIPCOUNT_PER_SUBPART - 1];
            a_x_local6[0] = a_x_local5[TRIPCOUNT_PER_SUBPART - 1];
            a_y_local6[0] = a_y_local5[TRIPCOUNT_PER_SUBPART - 1];
        }

        #pragma unroll
        for (int reg = TRIPCOUNT_PER_SUBPART - 1; reg > 0; reg--) {
            if (subparts_processed == subparts_to_process) {
                f_local5[reg] = f_local5[reg - 1];
                a_x_local5[reg] = a_x_local5[reg - 1];
                a_y_local5[reg] = a_y_local5[reg - 1];
            }
        }

        if (subparts_processed == subparts_to_process) {
            f_local5[0] = f_local4[TRIPCOUNT_PER_SUBPART - 1];
            a_x_local5[0] = a_x_local4[TRIPCOUNT_PER_SUBPART - 1];
            a_y_local5[0] = a_y_local4[TRIPCOUNT_PER_SUBPART - 1];
        }

        #pragma unroll
        for (int reg = TRIPCOUNT_PER_SUBPART - 1; reg > 0; reg--) {
            if (subparts_processed == subparts_to_process) {
                f_local4[reg] = f_local4[reg - 1];
                a_x_local4[reg] = a_x_local4[reg - 1];
                a_y_local4[reg] = a_y_local4[reg - 1];
            }
        }

        if (subparts_processed == subparts_to_process) {
            f_local4[0] = f_local3[TRIPCOUNT_PER_SUBPART - 1];
            a_x_local4[0] = a_x_local3[TRIPCOUNT_PER_SUBPART - 1];
            a_y_local4[0] = a_y_local3[TRIPCOUNT_PER_SUBPART - 1];
        }

        #pragma unroll
        for (int reg = TRIPCOUNT_PER_SUBPART - 1; reg > 0; reg--) {
            if (subparts_processed == subparts_to_process) {
                f_local3[reg] = f_local3[reg - 1];
                a_x_local3[reg] = a_x_local3[reg - 1];
                a_y_local3[reg] = a_y_local3[reg - 1];
            }
        }

        if (subparts_processed == subparts_to_process) {
            f_local3[0] = f_local2[TRIPCOUNT_PER_SUBPART - 1];
            a_x_local3[0] = a_x_local2[TRIPCOUNT_PER_SUBPART - 1];
            a_y_local3[0] = a_y_local2[TRIPCOUNT_PER_SUBPART - 1];
        }

        #pragma unroll
        for (int reg = TRIPCOUNT_PER_SUBPART - 1; reg > 0; reg--) {
            if (subparts_processed == subparts_to_process) {
                f_local2[reg] = f_local2[reg - 1];
                a_x_local2[reg] = a_x_local2[reg - 1];
                a_y_local2[reg] = a_y_local2[reg - 1];
            }
        }

        if (subparts_processed == subparts_to_process) {
            f_local2[0] = f_local1[TRIPCOUNT_PER_SUBPART - 1];
            a_x_local2[0] = a_x_local1[TRIPCOUNT_PER_SUBPART - 1];
            a_y_local2[0] = a_y_local1[TRIPCOUNT_PER_SUBPART - 1];
        }
        
		#pragma unroll
        for (int reg = TRIPCOUNT_PER_SUBPART - 1; reg > 0; reg--) {
            if (subparts_processed == subparts_to_process) {
                f_local1[reg] = f_local1[reg - 1];
                a_x_local1[reg] = a_x_local1[reg - 1];
                a_y_local1[reg] = a_y_local1[reg - 1];
            }
        }

        if (subparts_processed == subparts_to_process) {
            f_local1[0] = f_local0[TRIPCOUNT_PER_SUBPART];
            a_x_local1[0] = a_x_local0[TRIPCOUNT_PER_SUBPART];
            a_y_local1[0] = a_y_local0[TRIPCOUNT_PER_SUBPART];
        }

        #pragma unroll
        for (int reg = TRIPCOUNT_PER_SUBPART; reg > 0; reg--) {
            if (subparts_processed == subparts_to_process) {
                f_local0[reg] = f_local0[reg - 1];
                a_x_local0[reg] = a_x_local0[reg - 1];
                a_y_local0[reg] = a_y_local0[reg - 1];
            }
        }

        if (subparts_processed == subparts_to_process) {
            f_local0[0] = 0;
			i++;
			subparts_processed = 0;
        }      
	}
}