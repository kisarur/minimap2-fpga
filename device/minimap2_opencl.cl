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

#define INNER_LOOP_TRIP_COUNT 64

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

inline int compute_sc(unsigned long a_x, unsigned long a_y, int f, unsigned long ri, int qi, int q_span, float block_avg_qspan, int block_max_dist_x, int block_max_dist_y, int block_bw) 
{
	long dr = ri - a_x; 
    if (dr > block_max_dist_x || dr <= 0) return 0; // to serve "st"'s purpose (kisaru) 
	int dq = qi - (int)a_y, dd, sc, log_dd;
	if (dq <= 0) return 0; // don't skip if an anchor is used by multiple segments; see below
	if (dq > block_max_dist_y || dq > block_max_dist_x) return 0;
	dd = dr > dq? dr - dq : dq - dr;
	if (dd > block_bw) return 0;
	//if (dr > block_max_dist_y) return 0;
	int min_d = dq < dr? dq : dr;
	sc = min_d > q_span? q_span : dq < dr? dq : dr;
	log_dd = dd? ilog2_32(dd) : 0;
	sc -= (int)(dd * block_avg_qspan) + (log_dd>>1);
	sc += f;

	return sc;
}

inline void minimap2_opencl(long block_n, int block_max_dist_x, 
						 int block_max_dist_y, int block_bw, 
                         float block_avg_qspan,
						 __global const ulong2 *restrict a,
                         __global int *restrict f, __global int *restrict p, __global int *restrict v)
{
	unsigned long a_x_local[INNER_LOOP_TRIP_COUNT + 1] = {0};
	unsigned long a_y_local[INNER_LOOP_TRIP_COUNT + 1] = {0};
	int f_local[INNER_LOOP_TRIP_COUNT + 1] = {0};
    int v_local[INNER_LOOP_TRIP_COUNT + 1] = {0};

	// fill the score and backtrack arrays
	for (long i = 0; i < block_n; ++i) {

		a_x_local[0] = a[i].x;
		a_y_local[0] = a[i].y;

		unsigned long ri = a_x_local[0];
		int qi = (int)a_y_local[0], q_span = a_y_local[0]>>32&0xff; // NB: only 8 bits of span is used!!!
		
		long max_j = -1;
		int max_f = q_span;
        int peak_sc = q_span;

		#pragma unroll
		for (int j = INNER_LOOP_TRIP_COUNT; j > 0; j--) {
			int sc = compute_sc(a_x_local[j], a_y_local[j], f_local[j], ri, qi, q_span, block_avg_qspan, block_max_dist_x, block_max_dist_y, block_bw);
			if (sc >= max_f && sc != q_span) {
				max_f = sc, max_j = i - j;
                peak_sc = v_local[j] > max_f ? v_local[j] : max_f;
			}
		}
		
		f[i] = max_f;
        p[i] = max_j;
        v[i] = peak_sc;
		f_local[0] = max_f;
        v_local[0] = peak_sc;
        
		#pragma unroll
		for (int reg = INNER_LOOP_TRIP_COUNT; reg > 0; reg--) {
			f_local[reg] = f_local[reg - 1];
		}

        #pragma unroll
		for (int reg = INNER_LOOP_TRIP_COUNT; reg > 0; reg--) {
			v_local[reg] = v_local[reg - 1];
		}

		#pragma unroll
		for (int reg = INNER_LOOP_TRIP_COUNT; reg > 0; reg--) {
			a_x_local[reg] = a_x_local[reg - 1];
		}

		#pragma unroll
		for (int reg = INNER_LOOP_TRIP_COUNT; reg > 0; reg--) {
			a_y_local[reg] = a_y_local[reg - 1];
		}
	}
}


__kernel void minimap2_opencl0(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan,
                             __global const ulong2 *restrict a,
                             __global int *restrict f, __global int *restrict p, __global int *restrict v)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, a, f, p, v);
}

__kernel void minimap2_opencl1(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan,
                             __global const ulong2 *restrict a,
                             __global int *restrict f, __global int *restrict p, __global int *restrict v)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, a, f, p, v);
}

__kernel void minimap2_opencl2(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan,
                             __global const ulong2 *restrict a,
                             __global int *restrict f, __global int *restrict p, __global int *restrict v)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, a, f, p, v);
}

__kernel void minimap2_opencl3(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan,
                             __global const ulong2 *restrict a,
                             __global int *restrict f, __global int *restrict p, __global int *restrict v)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, a, f, p, v);
}
/*
__kernel void minimap2_opencl4(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan,
                             __global const ulong2 *restrict a,
                             __global int *restrict f, __global int *restrict p, __global int *restrict v)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, a, f, p, v);
}

__kernel void minimap2_opencl5(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan,
                             __global const ulong2 *restrict a,
                             __global int *restrict f, __global int *restrict p, __global int *restrict v)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, a, f, p, v);
}





__kernel void minimap2_opencl6(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const ulong2 *restrict a,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a, f, p);
}

__kernel void minimap2_opencl7(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl8(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl9(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl10(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl11(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl12(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl13(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl14(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl15(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl16(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl17(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl18(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl19(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl20(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl21(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl22(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl23(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl24(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl25(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl26(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl27(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl28(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl29(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl30(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl31(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl32(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl33(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl34(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl35(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl36(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl37(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl38(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}

__kernel void minimap2_opencl39(long n, int max_dist_x, 
                             int max_dist_y, int bw, 
                             float avg_qspan, long offset,
                             __global const unsigned long *restrict a_x, __global const unsigned long *restrict a_y,
                             __global int *restrict f, __global int *restrict p)
{
    minimap2_opencl(n, max_dist_x, max_dist_y, bw, avg_qspan, offset, a_x, a_y, f, p);
}
*/