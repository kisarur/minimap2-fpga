
#define MM_SEED_SEG_SHIFT  48
#define MM_SEED_SEG_MASK   (0xffULL<<(MM_SEED_SEG_SHIFT))

#define TRIPCOUNT_PER_SUBPART 128
#define MAX_SUBPARTS 8

#define PREFETCH_BUFFER_SIZE 64

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

inline void chain(long total_subparts,
					int max_dist_x, int max_dist_y, int bw, int q_span, float avg_qspan_scaled, 
					__global const ulong2 *restrict a,
					__global int *restrict f, __global int *restrict p,
					__global const unsigned char *restrict num_subparts)
{
	unsigned long a_x_local[TRIPCOUNT_PER_SUBPART * MAX_SUBPARTS + 1] __attribute__((xcl_array_partition(complete, 1))) = {0};
	int a_y_local[TRIPCOUNT_PER_SUBPART * MAX_SUBPARTS + 1] __attribute__((xcl_array_partition(complete, 1))) = {0};
	int f_local[TRIPCOUNT_PER_SUBPART * MAX_SUBPARTS + 1] __attribute__((xcl_array_partition(complete, 1))) = {0};

    unsigned char subparts_processed = 0;
	unsigned char subparts_to_process = 0;

	ulong2 a_local_next[PREFETCH_BUFFER_SIZE] __attribute__((xcl_array_partition(complete, 1)));
	unsigned char subparts_to_process_next[PREFETCH_BUFFER_SIZE] __attribute__((xcl_array_partition(complete, 1)));

	__attribute__((opencl_unroll_hint(PREFETCH_BUFFER_SIZE))) init_prefetch_loop :  for (int j = 0; j < PREFETCH_BUFFER_SIZE; j++) {
		a_local_next[j] = a[j];
		subparts_to_process_next[j] =  num_subparts[j];
	}

	int prefetch_ptr = PREFETCH_BUFFER_SIZE;

	// fill the score and backtrack arrays
    long i = 0;
	__attribute__((xcl_pipeline_loop(3))) main_outer_loop : for (long g = 0; g < total_subparts; ++g) {
		if (subparts_processed == 0) {
			ulong2 a_local = a_local_next[0];
			a_x_local[0] = a_local.x;
			a_y_local[0] = (int)a_local.y;
			subparts_to_process = subparts_to_process_next[0];

			__attribute__((opencl_unroll_hint(PREFETCH_BUFFER_SIZE - 1))) prefetch_shift_loop :  for (int j = 0; j < PREFETCH_BUFFER_SIZE - 1; j++) {
				a_local_next[j] = a_local_next[j + 1];
				subparts_to_process_next[j] = subparts_to_process_next[j + 1];
			}

			a_local_next[PREFETCH_BUFFER_SIZE - 1] = a[prefetch_ptr];
            subparts_to_process_next[PREFETCH_BUFFER_SIZE - 1] = num_subparts[prefetch_ptr];
			prefetch_ptr++;
        }
		
		unsigned long ri = a_x_local[0];
		int qi = a_y_local[0];
		
		unsigned long sc_a[TRIPCOUNT_PER_SUBPART] __attribute__((xcl_array_partition(complete, 1))) = {0};

		__attribute__((opencl_unroll_hint(TRIPCOUNT_PER_SUBPART))) score_loop :  for (int j = TRIPCOUNT_PER_SUBPART; j > 0; j--) {
			unsigned long a_x_local_j, a_y_local_j;
			int f_local_j;

			if (subparts_processed == 0) {
				a_x_local_j = a_x_local[j];
				a_y_local_j = a_y_local[j];
				f_local_j = f_local[j];
			}
			if (subparts_processed == 1) {
                a_x_local_j = a_x_local[TRIPCOUNT_PER_SUBPART + j];
				a_y_local_j = a_y_local[TRIPCOUNT_PER_SUBPART + j];
				f_local_j = f_local[TRIPCOUNT_PER_SUBPART + j];
            } 
			if (subparts_processed == 2) {
                a_x_local_j = a_x_local[2 * TRIPCOUNT_PER_SUBPART + j];
				a_y_local_j = a_y_local[2 * TRIPCOUNT_PER_SUBPART + j];
				f_local_j = f_local[2 * TRIPCOUNT_PER_SUBPART + j];
            } 
			if (subparts_processed == 3) {
                a_x_local_j = a_x_local[3 * TRIPCOUNT_PER_SUBPART + j];
				a_y_local_j = a_y_local[3 * TRIPCOUNT_PER_SUBPART + j];
				f_local_j = f_local[3 * TRIPCOUNT_PER_SUBPART + j];
            } 
			if (subparts_processed == 4) {
                a_x_local_j = a_x_local[4 * TRIPCOUNT_PER_SUBPART + j];
				a_y_local_j = a_y_local[4 * TRIPCOUNT_PER_SUBPART + j];
				f_local_j = f_local[4 * TRIPCOUNT_PER_SUBPART + j];
            } 
			if (subparts_processed == 5) {
                a_x_local_j = a_x_local[5 * TRIPCOUNT_PER_SUBPART + j];
				a_y_local_j = a_y_local[5 * TRIPCOUNT_PER_SUBPART + j];
				f_local_j = f_local[5 * TRIPCOUNT_PER_SUBPART + j];
            } 
			if (subparts_processed == 6) {
                a_x_local_j = a_x_local[6 * TRIPCOUNT_PER_SUBPART + j];
				a_y_local_j = a_y_local[6 * TRIPCOUNT_PER_SUBPART + j];
				f_local_j = f_local[6 * TRIPCOUNT_PER_SUBPART + j];
            } 
			if (subparts_processed == 7) {
                a_x_local_j = a_x_local[7 * TRIPCOUNT_PER_SUBPART + j];
				a_y_local_j = a_y_local[7 * TRIPCOUNT_PER_SUBPART + j];
				f_local_j = f_local[7 * TRIPCOUNT_PER_SUBPART + j];
            }

			long dr = ri - a_x_local_j; 
			if (dr > max_dist_x || dr <= 0) continue; // to serve "st"'s purpose (kisaru) 
			int dq = qi - (int)a_y_local_j, dd, log_dd;
			if (dq <= 0) continue; // don't skip if an anchor is used by multiple segments; see below
			if (dq > max_dist_y || dq > max_dist_x) continue;
			dd = dr > dq? dr - dq : dq - dr;
			if (dd > bw) continue;
			int min_d = dq < dr? dq : dr;
			int sc = min_d > q_span? q_span : dq < dr? dq : dr;
			log_dd = dd? ilog2_32(dd) : 0;
			sc -= (int)(dd * avg_qspan_scaled) + (log_dd>>1);
			sc += f_local_j;

			sc_a[j - 1] = sc;
		}

		long max_j = -1;
		int max_f = q_span;

		__attribute__((opencl_unroll_hint(TRIPCOUNT_PER_SUBPART))) max_score_loop :  for (int j = TRIPCOUNT_PER_SUBPART; j > 0; j--) {
			int sc = sc_a[j - 1];
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

        if (max_f > f_local[0]) {
            f[i] = max_f;
            p[i] = max_j;
            f_local[0] = max_f;
        }

        subparts_processed++;
        
        __attribute__((opencl_unroll_hint(TRIPCOUNT_PER_SUBPART * MAX_SUBPARTS))) shift_loop : for (int reg = TRIPCOUNT_PER_SUBPART * MAX_SUBPARTS; reg > 0; reg--) {
            if (subparts_processed == subparts_to_process) {
                f_local[reg] = f_local[reg - 1];
                a_x_local[reg] = a_x_local[reg - 1];
                a_y_local[reg] = a_y_local[reg - 1];
            }
        }

        if (subparts_processed == subparts_to_process) {
            f_local[0] = 0;
			i++;
			subparts_processed = 0;
        }      
	}
}


kernel __attribute__((reqd_work_group_size(1, 1, 1))) void chain0(long total_subparts,
                         int max_dist_x, int max_dist_y, int bw, int q_span, float avg_qspan_scaled, 
						 __global const ulong2 *restrict a,
                         __global int *restrict f, __global int *restrict p,
                         __global const unsigned char *restrict num_subparts)
{
	chain(total_subparts, max_dist_x, max_dist_y, bw, q_span, avg_qspan_scaled, a, f, p, num_subparts);
}
/*
kernel __attribute__((reqd_work_group_size(1, 1, 1))) void chain1(long total_subparts,
                         int max_dist_x, int max_dist_y, int bw, int q_span, float avg_qspan_scaled, 
						 __global const ulong2 *restrict a,
                         __global int *restrict f, __global int *restrict p,
                         __global const unsigned char *restrict num_subparts)
{
	chain(total_subparts, max_dist_x, max_dist_y, bw, q_span, avg_qspan_scaled, a, f, p, num_subparts);
}

kernel __attribute__((reqd_work_group_size(1, 1, 1))) void chain2(long total_subparts,
                         int max_dist_x, int max_dist_y, int bw, int q_span, float avg_qspan_scaled, 
						 __global const ulong2 *restrict a,
                         __global int *restrict f, __global int *restrict p,
                         __global const unsigned char *restrict num_subparts)
{
	chain(total_subparts, max_dist_x, max_dist_y, bw, q_span, avg_qspan_scaled, a, f, p, num_subparts);
}

kernel __attribute__((reqd_work_group_size(1, 1, 1))) void chain3(long total_subparts,
                         int max_dist_x, int max_dist_y, int bw, int q_span, float avg_qspan_scaled, 
						 __global const ulong2 *restrict a,
                         __global int *restrict f, __global int *restrict p,
                         __global const unsigned char *restrict num_subparts)
{
	chain(total_subparts, max_dist_x, max_dist_y, bw, q_span, avg_qspan_scaled, a, f, p, num_subparts);
}
*/