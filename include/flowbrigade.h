#ifndef FLOWBRIGADE_H
#define FLOWBRIGADE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum fb_status {
  FB_OK = 0,
  FB_ERR_INVALID_ARGUMENT = 1,
  FB_ERR_BUFFER_TOO_SMALL = 2,
  FB_ERR_INTERNAL = 100
} fb_status;

typedef enum fb_circuit_state {
  FB_CIRCUIT_CLOSED = 0,
  FB_CIRCUIT_OPEN = 1,
  FB_CIRCUIT_HALF_OPEN = 2
} fb_circuit_state;

typedef enum fb_jitter_kind {
  FB_NO_JITTER = 0,
  FB_FULL_JITTER = 1,
  FB_EQUAL_JITTER = 2,
  FB_DECORRELATED_JITTER = 3
} fb_jitter_kind;

typedef struct fb_rate_limit_result {
  int32_t allowed;
  int32_t limit;
  int32_t remaining;
  int64_t retry_after_ns;
  int64_t reset_after_ns;
} fb_rate_limit_result;

typedef struct fb_bulkhead_result {
  int32_t allowed;
  int32_t capacity;
  int32_t in_use;
  int32_t remaining;
} fb_bulkhead_result;

typedef void* fb_backoff_policy;
typedef void* fb_token_bucket;
typedef void* fb_fixed_window;
typedef void* fb_sliding_window;
typedef void* fb_circuit_breaker;
typedef void* fb_bulkhead;

void NimMain(void);

int32_t fb_duration_parse(const char* input, size_t input_len, int64_t* out_ns);
int32_t fb_duration_format(int64_t duration_ns, char* buffer, size_t buffer_len, size_t* out_len);

int32_t fb_fixed_backoff_create(int64_t delay_ns, int32_t jitter, fb_backoff_policy* out_handle);
int32_t fb_linear_backoff_create(int64_t initial_ns, int64_t increment_ns, int64_t max_delay_ns, int32_t jitter, fb_backoff_policy* out_handle);
int32_t fb_exp_backoff_create(int64_t initial_ns, double factor, int64_t max_delay_ns, int32_t jitter, fb_backoff_policy* out_handle);
void fb_backoff_destroy(fb_backoff_policy handle);
int32_t fb_backoff_delay_for(fb_backoff_policy handle, int32_t attempt, int64_t* out_delay_ns);

int32_t fb_token_bucket_create(int32_t rate, int64_t per_ns, int32_t burst, fb_token_bucket* out_handle);
void fb_token_bucket_destroy(fb_token_bucket handle);
int32_t fb_token_bucket_inspect(fb_token_bucket handle, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_token_bucket_consume(fb_token_bucket handle, int32_t cost, fb_rate_limit_result* out_result);

int32_t fb_fixed_window_create(int32_t limit, int64_t per_ns, fb_fixed_window* out_handle);
void fb_fixed_window_destroy(fb_fixed_window handle);
int32_t fb_fixed_window_inspect(fb_fixed_window handle, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_fixed_window_consume(fb_fixed_window handle, int32_t cost, fb_rate_limit_result* out_result);

int32_t fb_sliding_window_create(int32_t limit, int64_t per_ns, fb_sliding_window* out_handle);
void fb_sliding_window_destroy(fb_sliding_window handle);
int32_t fb_sliding_window_inspect(fb_sliding_window handle, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_sliding_window_consume(fb_sliding_window handle, int32_t cost, fb_rate_limit_result* out_result);

int32_t fb_circuit_breaker_create(int32_t failure_threshold, int64_t reset_after_ns, fb_circuit_breaker* out_handle);
void fb_circuit_breaker_destroy(fb_circuit_breaker handle);
int32_t fb_circuit_breaker_allow(fb_circuit_breaker handle, int32_t* out_allowed);
int32_t fb_circuit_breaker_record_success(fb_circuit_breaker handle);
int32_t fb_circuit_breaker_record_failure(fb_circuit_breaker handle);
int32_t fb_circuit_breaker_state(fb_circuit_breaker handle, int32_t* out_state);

int32_t fb_bulkhead_create(int32_t capacity, fb_bulkhead* out_handle);
void fb_bulkhead_destroy(fb_bulkhead handle);
int32_t fb_bulkhead_inspect(fb_bulkhead handle, fb_bulkhead_result* out_result);
int32_t fb_bulkhead_acquire(fb_bulkhead handle, fb_bulkhead_result* out_result);
int32_t fb_bulkhead_release(fb_bulkhead handle);

#ifdef __cplusplus
}
#endif

#endif
