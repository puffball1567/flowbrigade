#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "flowbrigade.h"

typedef struct retry_state {
  int32_t calls;
  int32_t sleep_calls;
  int64_t last_delay_ns;
} retry_state;

typedef struct fallback_state {
  int32_t calls[2];
} fallback_state;

typedef struct storage_state {
  int32_t used;
} storage_state;

static int32_t retry_operation(void* user_data, int32_t attempt) {
  retry_state* state = (retry_state*)user_data;
  state->calls = attempt;
  return attempt >= 3 ? FB_OK : 77;
}

static int32_t retry_sleep(void* user_data, int64_t delay_ns, int32_t attempt) {
  retry_state* state = (retry_state*)user_data;
  (void)attempt;
  state->sleep_calls++;
  state->last_delay_ns = delay_ns;
  return FB_OK;
}

static int32_t fallback_operation(void* user_data, int32_t provider_index) {
  fallback_state* state = (fallback_state*)user_data;
  state->calls[provider_index]++;
  return provider_index == 1 ? FB_OK : 55;
}

static int32_t storage_inspect(
  void* user_data,
  const char* key,
  size_t key_len,
  int32_t limit,
  int64_t per_ns,
  int32_t cost,
  int64_t current_ns,
  fb_rate_limit_result* out_result
) {
  storage_state* state = (storage_state*)user_data;
  int32_t allowed = state->used + cost <= limit;
  (void)key;
  (void)key_len;
  (void)current_ns;
  if (!out_result) {
    return FB_ERR_INVALID_ARGUMENT;
  }
  out_result->allowed = allowed;
  out_result->limit = limit;
  out_result->remaining = allowed ? limit - state->used - cost : limit - state->used;
  out_result->retry_after_ns = allowed ? 0 : per_ns;
  out_result->reset_after_ns = per_ns;
  return FB_OK;
}

static int32_t storage_consume(
  void* user_data,
  const char* key,
  size_t key_len,
  int32_t limit,
  int64_t per_ns,
  int32_t cost,
  int64_t current_ns,
  fb_rate_limit_result* out_result
) {
  storage_state* state = (storage_state*)user_data;
  int32_t status = storage_inspect(user_data, key, key_len, limit, per_ns, cost, current_ns, out_result);
  if (status != FB_OK) {
    return status;
  }
  if (out_result->allowed) {
    state->used += cost;
  }
  return FB_OK;
}

static int32_t storage_clear(void* user_data, const char* key, size_t key_len, int32_t* out_cleared) {
  storage_state* state = (storage_state*)user_data;
  (void)key;
  (void)key_len;
  if (!out_cleared) {
    return FB_ERR_INVALID_ARGUMENT;
  }
  *out_cleared = state->used > 0;
  state->used = 0;
  return FB_OK;
}

int main(void) {
  int64_t nanos = 0;
  fb_token_bucket bucket = 0;
  fb_keyed_fixed_window keyed_window = 0;
  fb_backoff_policy backoff = 0;
  fb_bulkhead bulkhead = 0;
  fb_keyed_bulkhead keyed_bulkhead = 0;
  fb_timeout timeout = 0;
  fb_budget_ledger budget = 0;
  fb_lock_store lock_store = 0;
  fb_lock_lease first_lease = 0;
  fb_lock_lease second_lease = 0;
  fb_throttle throttle = 0;
  fb_debouncer debouncer = 0;
  fb_limiter_registry registry = 0;
  fb_rate_limit_storage storage;
  fb_retry_result retry_decision;
  retry_state retry = {0, 0, 0};
  fb_fallback_provider fallback_providers[2];
  fb_fallback_result fallback_decision;
  fallback_state fallback = {{0, 0}};
  storage_state stored = {0};
  fb_rate_limit_result decision;
  fb_bulkhead_result bulkhead_decision;
  fb_budget_result budget_decision;
  fb_lock_acquire_result lock_decision;
  fb_lock_status lock_status;
  int64_t delay_ns = 0;
  int32_t expired = 0;
  int32_t released = 0;
  int32_t flag = 0;
  int32_t count = 0;
  char text[256];
  size_t text_len = 0;

  NimMain();

  if (fb_abi_version() < 1) {
    return 11;
  }
  if (strcmp(fb_abi_version_string(), "1") != 0) {
    return 45;
  }
  if (fb_abi_supports("storage-callback", 16, &flag) != FB_OK || !flag) {
    return 46;
  }

  if (fb_duration_parse("1s500ms", 7, &nanos) != FB_OK) {
    return 1;
  }
  if (nanos != 1500000000LL) {
    return 2;
  }

  if (fb_token_bucket_create(2, 1000000000LL, 3, &bucket) != FB_OK) {
    return 3;
  }
  if (fb_token_bucket_consume(bucket, 2, &decision) != FB_OK) {
    fb_token_bucket_destroy(bucket);
    return 4;
  }
  if (!decision.allowed || decision.remaining != 1) {
    fb_token_bucket_destroy(bucket);
    return 5;
  }

  fb_token_bucket_destroy(bucket);

  if (fb_keyed_fixed_window_create(2, 60000000000LL, 4, &keyed_window) != FB_OK) {
    return 53;
  }
  if (fb_keyed_fixed_window_consume(keyed_window, "tenant-a", 8, 1, &decision) != FB_OK || !decision.allowed) {
    fb_keyed_fixed_window_destroy(keyed_window);
    return 54;
  }
  if (fb_keyed_fixed_window_active_keys(keyed_window, &count) != FB_OK || count != 1) {
    fb_keyed_fixed_window_destroy(keyed_window);
    return 55;
  }
  if (fb_keyed_fixed_window_clear(keyed_window, "tenant-a", 8, &flag) != FB_OK || !flag) {
    fb_keyed_fixed_window_destroy(keyed_window);
    return 56;
  }
  if (fb_keyed_fixed_window_reset_all(keyed_window, &count) != FB_OK || count != 0) {
    fb_keyed_fixed_window_destroy(keyed_window);
    return 57;
  }
  fb_keyed_fixed_window_destroy(keyed_window);

  if (fb_fixed_backoff_create(250000000LL, FB_NO_JITTER, &backoff) != FB_OK) {
    return 6;
  }
  if (fb_backoff_delay_for(backoff, 2, &delay_ns) != FB_OK || delay_ns != 250000000LL) {
    fb_backoff_destroy(backoff);
    return 7;
  }
  fb_backoff_destroy(backoff);

  if (fb_bulkhead_create(1, &bulkhead) != FB_OK) {
    return 8;
  }
  if (fb_bulkhead_acquire(bulkhead, &bulkhead_decision) != FB_OK || !bulkhead_decision.allowed) {
    fb_bulkhead_destroy(bulkhead);
    return 9;
  }
  if (fb_bulkhead_release(bulkhead) != FB_OK) {
    fb_bulkhead_destroy(bulkhead);
    return 10;
  }
  fb_bulkhead_destroy(bulkhead);

  if (fb_keyed_bulkhead_create(2, 4, &keyed_bulkhead) != FB_OK) {
    return 58;
  }
  if (fb_keyed_bulkhead_acquire(keyed_bulkhead, "tenant-a", 8, &bulkhead_decision) != FB_OK ||
      !bulkhead_decision.allowed) {
    fb_keyed_bulkhead_destroy(keyed_bulkhead);
    return 59;
  }
  if (fb_keyed_bulkhead_active_keys(keyed_bulkhead, &count) != FB_OK || count != 1) {
    fb_keyed_bulkhead_destroy(keyed_bulkhead);
    return 60;
  }
  if (fb_keyed_bulkhead_release(keyed_bulkhead, "tenant-a", 8) != FB_OK) {
    fb_keyed_bulkhead_destroy(keyed_bulkhead);
    return 61;
  }
  if (fb_keyed_bulkhead_clear(keyed_bulkhead, "tenant-a", 8, &flag) != FB_OK || flag) {
    fb_keyed_bulkhead_destroy(keyed_bulkhead);
    return 62;
  }
  fb_keyed_bulkhead_destroy(keyed_bulkhead);

  if (fb_timeout_create(1000000000LL, &timeout) != FB_OK) {
    return 12;
  }
  if (fb_timeout_expired(timeout, &expired) != FB_OK || expired) {
    fb_timeout_destroy(timeout);
    return 13;
  }
  fb_timeout_destroy(timeout);

  if (fb_budget_ledger_create(10, 60000000000LL, &budget) != FB_OK) {
    return 14;
  }
  if (fb_budget_consume(budget, "tenant-a", 8, 7, &budget_decision) != FB_OK) {
    fb_budget_ledger_destroy(budget);
    return 15;
  }
  if (!budget_decision.allowed || budget_decision.remaining != 3) {
    fb_budget_ledger_destroy(budget);
    return 16;
  }
  if (fb_budget_consume(budget, "tenant-a", 8, 4, &budget_decision) != FB_OK) {
    fb_budget_ledger_destroy(budget);
    return 17;
  }
  if (budget_decision.allowed || budget_decision.remaining != 3) {
    fb_budget_ledger_destroy(budget);
    return 18;
  }
  fb_budget_ledger_destroy(budget);

  if (fb_lock_store_create(&lock_store) != FB_OK) {
    return 19;
  }
  if (fb_lock_acquire(lock_store, "job:1", 5, 60000000000LL, &first_lease, &lock_decision) != FB_OK) {
    fb_lock_store_destroy(lock_store);
    return 20;
  }
  if (!lock_decision.acquired) {
    fb_lock_lease_destroy(first_lease);
    fb_lock_store_destroy(lock_store);
    return 21;
  }
  if (fb_lock_acquire(lock_store, "job:1", 5, 60000000000LL, &second_lease, &lock_decision) != FB_OK) {
    fb_lock_lease_destroy(first_lease);
    fb_lock_store_destroy(lock_store);
    return 22;
  }
  if (lock_decision.acquired) {
    fb_lock_lease_destroy(first_lease);
    fb_lock_lease_destroy(second_lease);
    fb_lock_store_destroy(lock_store);
    return 23;
  }
  if (fb_lock_inspect(lock_store, first_lease, &lock_status) != FB_OK || !lock_status.held) {
    fb_lock_lease_destroy(first_lease);
    fb_lock_lease_destroy(second_lease);
    fb_lock_store_destroy(lock_store);
    return 24;
  }
  if (fb_lock_release(lock_store, first_lease, &released) != FB_OK || !released) {
    fb_lock_lease_destroy(first_lease);
    fb_lock_lease_destroy(second_lease);
    fb_lock_store_destroy(lock_store);
    return 25;
  }
  fb_lock_lease_destroy(first_lease);
  fb_lock_lease_destroy(second_lease);
  fb_lock_store_destroy(lock_store);

  if (fb_throttle_create(1000000000LL, &throttle) != FB_OK) {
    return 26;
  }
  if (fb_throttle_allow(throttle, &flag) != FB_OK || !flag) {
    fb_throttle_destroy(throttle);
    return 27;
  }
  if (fb_throttle_allow(throttle, &flag) != FB_OK || flag) {
    fb_throttle_destroy(throttle);
    return 28;
  }
  if (fb_throttle_reset(throttle) != FB_OK) {
    fb_throttle_destroy(throttle);
    return 29;
  }
  fb_throttle_destroy(throttle);

  if (fb_debouncer_create(1000000000LL, &debouncer) != FB_OK) {
    return 30;
  }
  if (fb_debouncer_ready(debouncer, &flag) != FB_OK || flag) {
    fb_debouncer_destroy(debouncer);
    return 31;
  }
  if (fb_debouncer_call(debouncer) != FB_OK) {
    fb_debouncer_destroy(debouncer);
    return 32;
  }
  if (fb_debouncer_cancel(debouncer) != FB_OK) {
    fb_debouncer_destroy(debouncer);
    return 33;
  }
  fb_debouncer_destroy(debouncer);

  if (fb_fixed_backoff_create(50000000LL, FB_NO_JITTER, &backoff) != FB_OK) {
    return 34;
  }
  if (fb_retry_run(backoff, 5, retry_operation, retry_sleep, &retry, &retry_decision) != FB_OK) {
    fb_backoff_destroy(backoff);
    return 35;
  }
  if (!retry_decision.succeeded || retry_decision.attempts != 3 || retry.sleep_calls != 2) {
    fb_backoff_destroy(backoff);
    return 36;
  }
  if (retry.last_delay_ns != 50000000LL) {
    fb_backoff_destroy(backoff);
    return 37;
  }
  fb_backoff_destroy(backoff);

  fallback_providers[0].operation = fallback_operation;
  fallback_providers[0].user_data = &fallback;
  fallback_providers[0].breaker = 0;
  fallback_providers[1].operation = fallback_operation;
  fallback_providers[1].user_data = &fallback;
  fallback_providers[1].breaker = 0;

  if (fb_fallback_run(fallback_providers, 2, 0, &fallback_decision) != FB_OK) {
    return 38;
  }
  if (!fallback_decision.succeeded || fallback_decision.provider_index != 1 || fallback_decision.failed_count != 1) {
    return 39;
  }
  if (fallback.calls[0] != 1 || fallback.calls[1] != 1) {
    return 40;
  }

  if (fb_limiter_registry_create(&registry) != FB_OK) {
    return 41;
  }
  if (fb_limiter_registry_add_fixed_window(registry, "global", 6, 1, 60000000000LL) != FB_OK) {
    fb_limiter_registry_destroy(registry);
    return 42;
  }
  if (fb_limiter_registry_consume(registry, "global", 6, "global", 6, 1, &decision) != FB_OK || !decision.allowed) {
    fb_limiter_registry_destroy(registry);
    return 43;
  }
  if (fb_limiter_registry_consume(registry, "global", 6, "global", 6, 1, &decision) != FB_OK || decision.allowed) {
    fb_limiter_registry_destroy(registry);
    return 44;
  }

  storage.inspect_fixed_window = storage_inspect;
  storage.consume_fixed_window = storage_consume;
  storage.clear_fixed_window = storage_clear;
  storage.user_data = &stored;
  if (fb_limiter_registry_add_stored_fixed_window(registry, "stored", 6, "login", 5, 2, 60000000000LL, &storage, 64) != FB_OK) {
    fb_limiter_registry_destroy(registry);
    return 47;
  }
  if (fb_limiter_registry_consume(registry, "stored", 6, "user:1", 6, 1, &decision) != FB_OK || !decision.allowed) {
    fb_limiter_registry_destroy(registry);
    return 48;
  }
  if (fb_limiter_registry_consume(registry, "stored", 6, "user:1", 6, 1, &decision) != FB_OK || !decision.allowed) {
    fb_limiter_registry_destroy(registry);
    return 49;
  }
  if (fb_limiter_registry_consume(registry, "stored", 6, "user:1", 6, 1, &decision) != FB_OK || decision.allowed) {
    fb_limiter_registry_destroy(registry);
    return 50;
  }
  if (fb_rate_limit_result_to_prometheus(&decision, text, sizeof(text), &text_len) != FB_OK) {
    fb_limiter_registry_destroy(registry);
    return 51;
  }
  if (strstr(text, "flowbrigade_ratelimit_decision") == 0) {
    fb_limiter_registry_destroy(registry);
    return 52;
  }
  fb_limiter_registry_destroy(registry);

  puts("flowbrigade C ABI smoke test passed");
  return 0;
}
