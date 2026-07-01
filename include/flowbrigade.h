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

typedef struct fb_budget_result {
  int32_t allowed;
  int64_t limit;
  int64_t used;
  int64_t remaining;
  int64_t cost;
  int64_t retry_after_ns;
  int64_t reset_after_ns;
} fb_budget_result;

typedef struct fb_retry_allowance_result {
  int32_t allowed;
  int64_t limit;
  int64_t originals;
  int64_t retries;
  int64_t remaining;
  int64_t cost;
  int64_t retry_after_ns;
  int64_t reset_after_ns;
} fb_retry_allowance_result;

typedef struct fb_lock_acquire_result {
  int32_t acquired;
  int64_t ttl_ns;
} fb_lock_acquire_result;

typedef struct fb_lock_status {
  int32_t held;
  int32_t expired;
  int64_t ttl_ns;
  int64_t remaining_ns;
} fb_lock_status;

typedef struct fb_retry_result {
  int32_t succeeded;
  int32_t attempts;
  int32_t last_status;
  int64_t last_delay_ns;
} fb_retry_result;

typedef int32_t (*fb_retry_operation)(void* user_data, int32_t attempt);
typedef int32_t (*fb_retry_sleep)(void* user_data, int64_t delay_ns, int32_t attempt);

typedef struct fb_fallback_result {
  int32_t succeeded;
  int32_t attempts;
  int32_t provider_index;
  int32_t failed_count;
  int32_t last_status;
} fb_fallback_result;

typedef int32_t (*fb_fallback_operation)(void* user_data, int32_t provider_index);
typedef int32_t (*fb_fallback_predicate)(void* user_data, int32_t status, int32_t provider_index);

typedef int32_t (*fb_fixed_window_storage_operation)(
  void* user_data,
  const char* key,
  size_t key_len,
  int32_t limit,
  int64_t per_ns,
  int32_t cost,
  int64_t current_ns,
  fb_rate_limit_result* out_result
);
typedef int32_t (*fb_fixed_window_storage_clear)(
  void* user_data,
  const char* key,
  size_t key_len,
  int32_t* out_cleared
);

typedef struct fb_fallback_provider {
  fb_fallback_operation operation;
  void* user_data;
  void* breaker;
} fb_fallback_provider;

typedef struct fb_rate_limit_storage {
  fb_fixed_window_storage_operation inspect_fixed_window;
  fb_fixed_window_storage_operation consume_fixed_window;
  fb_fixed_window_storage_clear clear_fixed_window;
  void* user_data;
} fb_rate_limit_storage;

typedef void* fb_backoff_policy;
typedef void* fb_token_bucket;
typedef void* fb_gcra_limiter;
typedef void* fb_fixed_window;
typedef void* fb_keyed_fixed_window;
typedef void* fb_keyed_gcra_limiter;
typedef void* fb_sliding_window;
typedef void* fb_circuit_breaker;
typedef void* fb_bulkhead;
typedef void* fb_keyed_bulkhead;
typedef void* fb_timeout;
typedef void* fb_deadline;
typedef void* fb_budget_ledger;
typedef void* fb_retry_allowance;
typedef void* fb_lock_store;
typedef void* fb_lock_lease;
typedef void* fb_throttle;
typedef void* fb_debouncer;
typedef void* fb_limiter_registry;

void NimMain(void);

int32_t fb_abi_version(void);
const char* fb_abi_version_string(void);
int32_t fb_abi_supports(const char* feature, size_t feature_len, int32_t* out_supported);
const char* fb_last_error(void);

int32_t fb_duration_parse(const char* input, size_t input_len, int64_t* out_ns);
int32_t fb_duration_format(int64_t duration_ns, char* buffer, size_t buffer_len, size_t* out_len);
int32_t fb_rate_limit_result_to_json(const fb_rate_limit_result* result, char* buffer, size_t buffer_len, size_t* out_len);
int32_t fb_rate_limit_result_to_prometheus(const fb_rate_limit_result* result, char* buffer, size_t buffer_len, size_t* out_len);
int32_t fb_budget_result_to_json(const fb_budget_result* result, const char* key, size_t key_len, char* buffer, size_t buffer_len, size_t* out_len);
int32_t fb_budget_result_to_prometheus(const fb_budget_result* result, const char* key, size_t key_len, char* buffer, size_t buffer_len, size_t* out_len);

int32_t fb_fixed_backoff_create(int64_t delay_ns, int32_t jitter, fb_backoff_policy* out_handle);
int32_t fb_linear_backoff_create(int64_t initial_ns, int64_t increment_ns, int64_t max_delay_ns, int32_t jitter, fb_backoff_policy* out_handle);
int32_t fb_exp_backoff_create(int64_t initial_ns, double factor, int64_t max_delay_ns, int32_t jitter, fb_backoff_policy* out_handle);
void fb_backoff_destroy(fb_backoff_policy handle);
int32_t fb_backoff_delay_for(fb_backoff_policy handle, int32_t attempt, int64_t* out_delay_ns);

int32_t fb_token_bucket_create(int32_t rate, int64_t per_ns, int32_t burst, fb_token_bucket* out_handle);
void fb_token_bucket_destroy(fb_token_bucket handle);
int32_t fb_token_bucket_inspect(fb_token_bucket handle, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_token_bucket_consume(fb_token_bucket handle, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_token_bucket_reset(fb_token_bucket handle);
int32_t fb_token_bucket_configured_rate(fb_token_bucket handle, int32_t* out_rate);
int32_t fb_token_bucket_configured_period(fb_token_bucket handle, int64_t* out_period_ns);
int32_t fb_token_bucket_configured_burst(fb_token_bucket handle, int32_t* out_burst);
int32_t fb_token_bucket_available_tokens(fb_token_bucket handle, int32_t* out_tokens);

int32_t fb_gcra_create(int32_t rate, int64_t per_ns, int32_t burst, fb_gcra_limiter* out_handle);
void fb_gcra_destroy(fb_gcra_limiter handle);
int32_t fb_gcra_inspect(fb_gcra_limiter handle, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_gcra_consume(fb_gcra_limiter handle, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_gcra_allow(fb_gcra_limiter handle, int32_t cost, int32_t* out_allowed);
int32_t fb_gcra_reset(fb_gcra_limiter handle);
int32_t fb_gcra_configured_rate(fb_gcra_limiter handle, int32_t* out_rate);
int32_t fb_gcra_configured_period(fb_gcra_limiter handle, int64_t* out_period_ns);
int32_t fb_gcra_configured_burst(fb_gcra_limiter handle, int32_t* out_burst);
int32_t fb_gcra_configured_interval(fb_gcra_limiter handle, int64_t* out_interval_ns);
int32_t fb_gcra_available_capacity(fb_gcra_limiter handle, int32_t* out_capacity);

int32_t fb_fixed_window_create(int32_t limit, int64_t per_ns, fb_fixed_window* out_handle);
void fb_fixed_window_destroy(fb_fixed_window handle);
int32_t fb_fixed_window_inspect(fb_fixed_window handle, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_fixed_window_consume(fb_fixed_window handle, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_fixed_window_reset(fb_fixed_window handle);
int32_t fb_fixed_window_configured_limit(fb_fixed_window handle, int32_t* out_limit);
int32_t fb_fixed_window_configured_period(fb_fixed_window handle, int64_t* out_period_ns);
int32_t fb_fixed_window_in_use(fb_fixed_window handle, int32_t* out_in_use);

int32_t fb_keyed_fixed_window_create(int32_t limit, int64_t per_ns, int32_t max_keys, fb_keyed_fixed_window* out_handle);
void fb_keyed_fixed_window_destroy(fb_keyed_fixed_window handle);
int32_t fb_keyed_fixed_window_inspect(fb_keyed_fixed_window handle, const char* key, size_t key_len, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_keyed_fixed_window_consume(fb_keyed_fixed_window handle, const char* key, size_t key_len, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_keyed_fixed_window_clear(fb_keyed_fixed_window handle, const char* key, size_t key_len, int32_t* out_cleared);
int32_t fb_keyed_fixed_window_reset(fb_keyed_fixed_window handle, const char* key, size_t key_len, int32_t* out_reset);
int32_t fb_keyed_fixed_window_reset_all(fb_keyed_fixed_window handle, int32_t* out_removed);
int32_t fb_keyed_fixed_window_active_keys(fb_keyed_fixed_window handle, int32_t* out_count);
int32_t fb_keyed_fixed_window_configured_limit(fb_keyed_fixed_window handle, int32_t* out_limit);
int32_t fb_keyed_fixed_window_configured_period(fb_keyed_fixed_window handle, int64_t* out_period_ns);
int32_t fb_keyed_fixed_window_key_capacity(fb_keyed_fixed_window handle, int32_t* out_capacity);

int32_t fb_keyed_gcra_create(int32_t rate, int64_t per_ns, int32_t burst, int32_t max_keys, fb_keyed_gcra_limiter* out_handle);
void fb_keyed_gcra_destroy(fb_keyed_gcra_limiter handle);
int32_t fb_keyed_gcra_inspect(fb_keyed_gcra_limiter handle, const char* key, size_t key_len, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_keyed_gcra_consume(fb_keyed_gcra_limiter handle, const char* key, size_t key_len, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_keyed_gcra_allow(fb_keyed_gcra_limiter handle, const char* key, size_t key_len, int32_t cost, int32_t* out_allowed);
int32_t fb_keyed_gcra_prune_idle(fb_keyed_gcra_limiter handle);
int32_t fb_keyed_gcra_active_keys(fb_keyed_gcra_limiter handle, int32_t* out_count);
int32_t fb_keyed_gcra_clear(fb_keyed_gcra_limiter handle, const char* key, size_t key_len, int32_t* out_cleared);
int32_t fb_keyed_gcra_reset(fb_keyed_gcra_limiter handle, const char* key, size_t key_len, int32_t* out_reset);
int32_t fb_keyed_gcra_reset_all(fb_keyed_gcra_limiter handle, int32_t* out_removed);
int32_t fb_keyed_gcra_configured_rate(fb_keyed_gcra_limiter handle, int32_t* out_rate);
int32_t fb_keyed_gcra_configured_period(fb_keyed_gcra_limiter handle, int64_t* out_period_ns);
int32_t fb_keyed_gcra_configured_burst(fb_keyed_gcra_limiter handle, int32_t* out_burst);
int32_t fb_keyed_gcra_configured_interval(fb_keyed_gcra_limiter handle, int64_t* out_interval_ns);
int32_t fb_keyed_gcra_key_capacity(fb_keyed_gcra_limiter handle, int32_t* out_capacity);

int32_t fb_sliding_window_create(int32_t limit, int64_t per_ns, fb_sliding_window* out_handle);
void fb_sliding_window_destroy(fb_sliding_window handle);
int32_t fb_sliding_window_inspect(fb_sliding_window handle, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_sliding_window_consume(fb_sliding_window handle, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_sliding_window_reset(fb_sliding_window handle);
int32_t fb_sliding_window_configured_limit(fb_sliding_window handle, int32_t* out_limit);
int32_t fb_sliding_window_configured_period(fb_sliding_window handle, int64_t* out_period_ns);
int32_t fb_sliding_window_current_use(fb_sliding_window handle, int32_t* out_in_use);

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

int32_t fb_keyed_bulkhead_create(int32_t capacity, int32_t max_keys, fb_keyed_bulkhead* out_handle);
void fb_keyed_bulkhead_destroy(fb_keyed_bulkhead handle);
int32_t fb_keyed_bulkhead_inspect(fb_keyed_bulkhead handle, const char* key, size_t key_len, fb_bulkhead_result* out_result);
int32_t fb_keyed_bulkhead_acquire(fb_keyed_bulkhead handle, const char* key, size_t key_len, fb_bulkhead_result* out_result);
int32_t fb_keyed_bulkhead_release(fb_keyed_bulkhead handle, const char* key, size_t key_len);
int32_t fb_keyed_bulkhead_clear(fb_keyed_bulkhead handle, const char* key, size_t key_len, int32_t* out_cleared);
int32_t fb_keyed_bulkhead_active_keys(fb_keyed_bulkhead handle, int32_t* out_count);

int32_t fb_timeout_create(int64_t after_ns, fb_timeout* out_handle);
void fb_timeout_destroy(fb_timeout handle);
int32_t fb_timeout_expired(fb_timeout handle, int32_t* out_expired);
int32_t fb_timeout_elapsed(fb_timeout handle, int64_t* out_elapsed_ns);
int32_t fb_timeout_remaining(fb_timeout handle, int64_t* out_remaining_ns);

int32_t fb_deadline_create(int64_t after_ns, fb_deadline* out_handle);
void fb_deadline_destroy(fb_deadline handle);
int32_t fb_deadline_expired(fb_deadline handle, int32_t* out_expired);
int32_t fb_deadline_remaining(fb_deadline handle, int64_t* out_remaining_ns);
int32_t fb_deadline_clamp(fb_deadline handle, int64_t requested_ns, int64_t* out_clamped_ns);

int32_t fb_budget_ledger_create(int64_t limit, int64_t per_ns, fb_budget_ledger* out_handle);
void fb_budget_ledger_destroy(fb_budget_ledger handle);
int32_t fb_budget_inspect(fb_budget_ledger handle, const char* key, size_t key_len, int64_t cost, fb_budget_result* out_result);
int32_t fb_budget_consume(fb_budget_ledger handle, const char* key, size_t key_len, int64_t cost, fb_budget_result* out_result);
int32_t fb_budget_refund(fb_budget_ledger handle, const char* key, size_t key_len, int64_t amount, fb_budget_result* out_result);
int32_t fb_budget_reset(fb_budget_ledger handle, const char* key, size_t key_len, fb_budget_result* out_result);
int32_t fb_budget_reset_all(fb_budget_ledger handle);

int32_t fb_retry_allowance_create(double retry_ratio, int64_t per_ns, int64_t minimum_retries, int32_t max_keys, fb_retry_allowance* out_handle);
void fb_retry_allowance_destroy(fb_retry_allowance handle);
int32_t fb_retry_allowance_record_original(fb_retry_allowance handle, const char* key, size_t key_len, int64_t amount, fb_retry_allowance_result* out_result);
int32_t fb_retry_allowance_inspect_retry(fb_retry_allowance handle, const char* key, size_t key_len, int64_t cost, fb_retry_allowance_result* out_result);
int32_t fb_retry_allowance_record_retry(fb_retry_allowance handle, const char* key, size_t key_len, int64_t cost, fb_retry_allowance_result* out_result);
int32_t fb_retry_allowance_allow_retry(fb_retry_allowance handle, const char* key, size_t key_len, int64_t cost, int32_t* out_allowed);
int32_t fb_retry_allowance_clear(fb_retry_allowance handle, const char* key, size_t key_len, int32_t* out_cleared);
int32_t fb_retry_allowance_reset(fb_retry_allowance handle, const char* key, size_t key_len, int32_t* out_reset);
int32_t fb_retry_allowance_reset_all(fb_retry_allowance handle, int32_t* out_removed);
int32_t fb_retry_allowance_prune_expired(fb_retry_allowance handle);
int32_t fb_retry_allowance_active_keys(fb_retry_allowance handle, int32_t* out_count);
int32_t fb_retry_allowance_configured_retry_ratio(fb_retry_allowance handle, double* out_ratio);
int32_t fb_retry_allowance_configured_minimum_retries(fb_retry_allowance handle, int64_t* out_minimum_retries);
int32_t fb_retry_allowance_configured_period(fb_retry_allowance handle, int64_t* out_period_ns);
int32_t fb_retry_allowance_key_capacity(fb_retry_allowance handle, int32_t* out_capacity);

int32_t fb_lock_store_create(fb_lock_store* out_handle);
void fb_lock_store_destroy(fb_lock_store handle);
void fb_lock_lease_destroy(fb_lock_lease handle);
int32_t fb_lock_acquire(fb_lock_store handle, const char* key, size_t key_len, int64_t ttl_ns, fb_lock_lease* out_lease, fb_lock_acquire_result* out_result);
int32_t fb_lock_release(fb_lock_store handle, fb_lock_lease lease, int32_t* out_released);
int32_t fb_lock_release_key(fb_lock_store handle, const char* key, size_t key_len, int32_t* out_released);
int32_t fb_lock_refresh(fb_lock_store handle, fb_lock_lease lease, int64_t ttl_ns, fb_lock_acquire_result* out_result);
int32_t fb_lock_inspect(fb_lock_store handle, fb_lock_lease lease, fb_lock_status* out_status);

int32_t fb_throttle_create(int64_t every_ns, fb_throttle* out_handle);
void fb_throttle_destroy(fb_throttle handle);
int32_t fb_throttle_allow(fb_throttle handle, int32_t* out_allowed);
int32_t fb_throttle_reset(fb_throttle handle);

int32_t fb_debouncer_create(int64_t delay_ns, fb_debouncer* out_handle);
void fb_debouncer_destroy(fb_debouncer handle);
int32_t fb_debouncer_call(fb_debouncer handle);
int32_t fb_debouncer_ready(fb_debouncer handle, int32_t* out_ready);
int32_t fb_debouncer_consume_ready(fb_debouncer handle, int32_t* out_ready);
int32_t fb_debouncer_cancel(fb_debouncer handle);

int32_t fb_retry_run(fb_backoff_policy policy, int32_t max_attempts, fb_retry_operation operation, fb_retry_sleep sleep, void* user_data, fb_retry_result* out_result);
int32_t fb_fallback_run(const fb_fallback_provider* providers, size_t provider_count, fb_fallback_predicate should_fallback, fb_fallback_result* out_result);

int32_t fb_limiter_registry_create(fb_limiter_registry* out_handle);
void fb_limiter_registry_destroy(fb_limiter_registry handle);
int32_t fb_limiter_registry_add_fixed_window(fb_limiter_registry handle, const char* name, size_t name_len, int32_t limit, int64_t per_ns);
int32_t fb_limiter_registry_add_sliding_window(fb_limiter_registry handle, const char* name, size_t name_len, int32_t limit, int64_t per_ns);
int32_t fb_limiter_registry_add_token_bucket(fb_limiter_registry handle, const char* name, size_t name_len, int32_t rate, int64_t per_ns, int32_t burst);
int32_t fb_limiter_registry_add_keyed_fixed_window(fb_limiter_registry handle, const char* name, size_t name_len, int32_t limit, int64_t per_ns, int32_t max_keys);
int32_t fb_limiter_registry_add_stored_fixed_window(fb_limiter_registry handle, const char* name, size_t name_len, const char* prefix, size_t prefix_len, int32_t limit, int64_t per_ns, const fb_rate_limit_storage* storage, int32_t max_key_length);
int32_t fb_limiter_registry_add_compound(fb_limiter_registry handle, const char* name, size_t name_len, const char* const* child_names, const size_t* child_name_lens, size_t child_count);
int32_t fb_limiter_registry_inspect(fb_limiter_registry handle, const char* name, size_t name_len, const char* key, size_t key_len, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_limiter_registry_consume(fb_limiter_registry handle, const char* name, size_t name_len, const char* key, size_t key_len, int32_t cost, fb_rate_limit_result* out_result);
int32_t fb_limiter_registry_allow(fb_limiter_registry handle, const char* name, size_t name_len, const char* key, size_t key_len, int32_t cost, int32_t* out_allowed);
int32_t fb_limiter_registry_clear(fb_limiter_registry handle, const char* name, size_t name_len, const char* key, size_t key_len, int32_t* out_cleared);

#ifdef __cplusplus
}
#endif

#endif
