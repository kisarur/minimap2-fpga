#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include "minimap.h"
#include "mmpriv.h"
#include "kalloc.h"
#include "chain_hardware.h"

#ifdef MEASURE_CORE_CHAINING_TIME
extern double core_chaining_time_total;
#endif

extern float SW_HW_THRESHOLD;

static const char LogTable256[256] = {
#define LT(n) n, n, n, n, n, n, n, n, n, n, n, n, n, n, n, n
	-1, 0, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3,
	LT(4), LT(5), LT(5), LT(6), LT(6), LT(6), LT(6),
	LT(7), LT(7), LT(7), LT(7), LT(7), LT(7), LT(7), LT(7)
};

static inline int ilog2_32(uint32_t v)
{
	register uint32_t t, tt;
	if ((tt = v>>16)) return (t = tt>>8) ? 24 + LogTable256[t] : 16 + LogTable256[tt];
	return (t = v>>8) ? 8 + LogTable256[t] : LogTable256[v];
}

mm128_t *mm_chain_dp(int max_dist_x, int max_dist_y, int bw, int max_skip, int min_cnt, int min_sc, int is_cdna, int n_segs, int64_t n, mm128_t *a, int *n_u_, uint64_t **_u, void *km, int tid)
{ // TODO: make sure this works when n has more than 32 bits
	int32_t k, *f, *p, *t, *v, n_u, n_v;
	int64_t i, j, st;
	uint64_t *u, *u2, sum_qspan = 0;
	mm128_t *b, *w;

	if (_u) *_u = 0, *n_u_ = 0;
	f = (int32_t*)kmalloc(km, (n + EXTRA_ELEMS) * 4);
	p = (int32_t*)kmalloc(km, (n + EXTRA_ELEMS) * 4);
	t = (int32_t*)kmalloc(km, n * 4);
	v = (int32_t*)kmalloc(km, (n + EXTRA_ELEMS) * 4);
	memset(t, 0, n * 4);

	for (i = 0; i < n; ++i) sum_qspan += a[i].y>>32&0xff;
	float avg_qspan_scaled = .01 * (float)sum_qspan / n;


#ifdef MEASURE_CHAINING_TIME
	double chaining_start = realtime();
	bool was_exec_on_hw = false;
#endif


	/*--------- Calculating sw_hw_frac Start ------------*/
	
	long total_trip_count = 0;
	st = 0;
	bool is_hw_supported_call = true;
	int64_t total_subparts = 0;
	unsigned char * num_subparts = (unsigned char*)kmalloc(km, (n + EXTRA_ELEMS));

#ifdef VERIFY_OUTPUT
	int32_t * tc = (int32_t*)malloc(n * sizeof(int32_t));
#endif 

	for (i = 0; i < n; i++) {
		// determine and store the inner loop's trip count (max is INNER_LOOP_TRIP_COUNT_MAX)
		while (st < i && a[i].x > a[st].x + max_dist_x) ++st;
		int inner_loop_trip_count = i - st;
		if (inner_loop_trip_count > MAX_TRIPCOUNT) { 
			inner_loop_trip_count = MAX_TRIPCOUNT;
		}
		total_trip_count += inner_loop_trip_count;
#ifdef VERIFY_OUTPUT
		tc[i] = inner_loop_trip_count;
#endif 

		int subparts = inner_loop_trip_count / TRIPCOUNT_PER_SUBPART;
		if (inner_loop_trip_count == 0 || inner_loop_trip_count % TRIPCOUNT_PER_SUBPART > 0) subparts++;
		num_subparts[i] = (unsigned char)subparts;
		total_subparts += subparts;
	}
	
	float sw_hw_frac = 0;
	if (n > 0 && is_hw_supported_call) { // can have some other threshold than 0 for n (eg. MIN_ANCHORS) to force processing small calls on software
		sw_hw_frac = (float) total_trip_count / (n * MAX_TRIPCOUNT);
	}

	/*--------- Calculating sw_hw_frac End ------------*/

#ifdef MEASURE_CHAINING_TIME
	double overhead = realtime() - chaining_start;
#endif


#ifdef VERIFY_OUTPUT
	int32_t * f_hw = (int32_t*)malloc((n + EXTRA_ELEMS) * sizeof(int32_t));
	int32_t * p_hw = (int32_t*)malloc((n + EXTRA_ELEMS) * sizeof(int32_t));
	int32_t * v_hw = (int32_t*)malloc((n + EXTRA_ELEMS) * sizeof(int32_t));
#endif

#ifdef MEASURE_CORE_CHAINING_TIME
	double core_chaining_start = realtime();
#endif


#ifndef VERIFY_OUTPUT
	if (sw_hw_frac > SW_HW_THRESHOLD) { // execute on HW
#endif


#ifndef VERIFY_OUTPUT
		run_chaining_on_hw(n, max_dist_x, max_dist_y, bw, Q_SPAN, avg_qspan_scaled, a, f, p, num_subparts, total_subparts, tid);

		for (i = 0; i < n; ++i) {
			int32_t max_f = f[i];
			int64_t max_j = p[i];
			v[i] = max_j >= 0 && v[max_j] > max_f? v[max_j] : max_f; // v[] keeps the peak score up to i; f[] is the score ending at i, not always the peak
		}
#else
		run_chaining_on_hw(n, max_dist_x, max_dist_y, bw, Q_SPAN, avg_qspan_scaled, a, f_hw, p_hw, num_subparts, total_subparts, tid);

		for (i = 0; i < n; ++i) {
			int32_t max_f = f_hw[i];
			int64_t max_j = p_hw[i];
			v_hw[i] = max_j >= 0 && v_hw[max_j] > max_f? v_hw[max_j] : max_f; // v[] keeps the peak score up to i; f[] is the score ending at i, not always the peak
 
		}
#endif


#ifdef MEASURE_CHAINING_TIME
		was_exec_on_hw = true;
#endif


#ifndef VERIFY_OUTPUT
	} else { // execute on SW
#endif
	
		// double sw_start = realtime();

		st = 0;
		for (i = 0; i < n; ++i) {
			uint64_t ri = a[i].x;
			int64_t max_j = -1;
			int32_t qi = (int32_t)a[i].y, q_span = a[i].y>>32&0xff; // NB: only 8 bits of span is used!!!
			int32_t max_f = q_span, min_d;
			int32_t sidi = (a[i].y & MM_SEED_SEG_MASK) >> MM_SEED_SEG_SHIFT;
			while (st < i && ri > a[st].x + max_dist_x) ++st;
			for (j = i - 1; j >= st && j > (i - MAX_TRIPCOUNT - 1); --j) {
				int64_t dr = ri - a[j].x;
				int32_t dq = qi - (int32_t)a[j].y, dd, sc, log_dd;
				int32_t sidj = (a[j].y & MM_SEED_SEG_MASK) >> MM_SEED_SEG_SHIFT;

				if ((sidi == sidj && dr == 0) || dq <= 0) continue; // don't skip if an anchor is used by multiple segments; see below
				if ((sidi == sidj && dq > max_dist_y) || dq > max_dist_x) continue;
				dd = dr > dq? dr - dq : dq - dr;
				if (sidi == sidj && dd > bw) continue;
				if (n_segs > 1 && !is_cdna && sidi == sidj && dr > max_dist_y) continue;
				min_d = dq < dr? dq : dr;
				sc = min_d > q_span? q_span : dq < dr? dq : dr;
				log_dd = dd? ilog2_32(dd) : 0;
				sc -= (int)(dd * avg_qspan_scaled) + (log_dd>>1);
				sc += f[j];
				if (sc > max_f) {
					max_f = sc, max_j = j;
				} 
			}
			f[i] = max_f, p[i] = max_j;
			v[i] = max_j >= 0 && v[max_j] > max_f? v[max_j] : max_f; // v[] keeps the peak score up to i; f[] is the score ending at i, not always the peak
		}
		
		// fprintf(stderr, "tid: %d, chaining_time: %.3f\n", tid, (realtime() - sw_start) * 1000);
		
#ifndef VERIFY_OUTPUT
	}
#endif

#ifdef MEASURE_CORE_CHAINING_TIME
	double core_chaining_time = realtime() - core_chaining_start;
	core_chaining_time_total += core_chaining_time;
#endif

#ifdef MEASURE_CHAINING_TIME
	double overhead2_start = realtime();
#endif

#ifdef MEASURE_CHAINING_TIME
	double end = realtime();
	overhead += (end - overhead2_start);

	fprintf(stderr, "tid: %d, chaining_time: %.3f, overhead: %.3f, was_exec_on_hw: %d, sw_hw_frac: %.3f\n", tid, (end - chaining_start) * 1000, overhead * 1000, was_exec_on_hw, sw_hw_frac);
#endif


#ifdef VERIFY_OUTPUT
	int mismatched = 0;
	for (i = 0; i < n; i++) {
		if (f[i] != f_hw[i] || p[i] != p_hw[i] || v[i] != v_hw[i]) {
			fprintf(stderr, "n = %ld, i = %d | f = %d, f_hw = %d | p = %d, p_hw = %d | v = %d, v_hw = %d | %d, %d\n", n, i, f[i], f_hw[i], p[i], p_hw[i], v[i], v_hw[i], num_subparts[i], tc[i]);
			exit(1);
			mismatched++;
		}
	}
	if (mismatched > 0) {
		fprintf(stderr, "mismatched = %d/%ld\n", mismatched, n);
		//fprintf(stderr, "total_trip_count = %d, sw_hw_frac = %f\n", total_trip_count, sw_hw_frac);
	}

	free(f_hw);
	free(p_hw);
	free(v_hw);
	free(tc);
#endif

kfree(km, num_subparts);

	// find the ending positions of chains
	memset(t, 0, n * 4);
	for (i = 0; i < n; ++i)
		if (p[i] >= 0) t[p[i]] = 1;
	for (i = n_u = 0; i < n; ++i)
		if (t[i] == 0 && v[i] >= min_sc)
			++n_u;
	if (n_u == 0) {
		kfree(km, a); kfree(km, f); kfree(km, p); kfree(km, t); kfree(km, v);
		return 0;
	}
	u = (uint64_t*)kmalloc(km, n_u * 8);
	for (i = n_u = 0; i < n; ++i) {
		if (t[i] == 0 && v[i] >= min_sc) {
			j = i;
			while (j >= 0 && f[j] < v[j]) j = p[j]; // find the peak that maximizes f[]
			if (j < 0) j = i; // TODO: this should really be assert(j>=0)
			u[n_u++] = (uint64_t)f[j] << 32 | j;
		}
	}
	radix_sort_64(u, u + n_u);
	for (i = 0; i < n_u>>1; ++i) { // reverse, s.t. the highest scoring chain is the first
		uint64_t t = u[i];
		u[i] = u[n_u - i - 1], u[n_u - i - 1] = t;
	}

	// backtrack
	memset(t, 0, n * 4);
	for (i = n_v = k = 0; i < n_u; ++i) { // starting from the highest score
		int32_t n_v0 = n_v, k0 = k;
		j = (int32_t)u[i];
		do {
			v[n_v++] = j;
			t[j] = 1;
			j = p[j];
		} while (j >= 0 && t[j] == 0);
		if (j < 0) {
			if (n_v - n_v0 >= min_cnt) u[k++] = u[i]>>32<<32 | (n_v - n_v0);
		} else if ((int32_t)(u[i]>>32) - f[j] >= min_sc) {
			if (n_v - n_v0 >= min_cnt) u[k++] = ((u[i]>>32) - f[j]) << 32 | (n_v - n_v0);
		}
		if (k0 == k) n_v = n_v0; // no new chain added, reset
	}
	*n_u_ = n_u = k, *_u = u; // NB: note that u[] may not be sorted by score here

	// free temporary arrays
	kfree(km, f); kfree(km, p); kfree(km, t);

	// write the result to b[]
	b = (mm128_t*)kmalloc(km, n_v * sizeof(mm128_t));
	for (i = 0, k = 0; i < n_u; ++i) {
		int32_t k0 = k, ni = (int32_t)u[i];
		for (j = 0; j < ni; ++j)
			b[k] = a[v[k0 + (ni - j - 1)]], ++k;
	}
	kfree(km, v);

	// sort u[] and a[] by a[].x, such that adjacent chains may be joined (required by mm_join_long)
	w = (mm128_t*)kmalloc(km, n_u * sizeof(mm128_t));
	for (i = k = 0; i < n_u; ++i) {
		w[i].x = b[k].x, w[i].y = (uint64_t)k<<32|i;
		k += (int32_t)u[i];
	}
	radix_sort_128x(w, w + n_u);
	u2 = (uint64_t*)kmalloc(km, n_u * 8);
	for (i = k = 0; i < n_u; ++i) {
		int32_t j = (int32_t)w[i].y, n = (int32_t)u[j];
		u2[i] = u[j];
		memcpy(&a[k], &b[w[i].y>>32], n * sizeof(mm128_t));
		k += n;
	}
	memcpy(u, u2, n_u * 8);
	memcpy(b, a, k * sizeof(mm128_t)); // write _a_ to _b_ and deallocate _a_ because _a_ is oversized, sometimes a lot
	kfree(km, a); kfree(km, w); kfree(km, u2);
	return b;
}
