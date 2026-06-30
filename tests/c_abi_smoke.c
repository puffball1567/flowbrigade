#include <stdint.h>
#include <stdio.h>

#include "flowbrigade.h"

int main(void) {
  int64_t nanos = 0;
  fb_token_bucket bucket = 0;
  fb_backoff_policy backoff = 0;
  fb_bulkhead bulkhead = 0;
  fb_timeout timeout = 0;
  fb_budget_ledger budget = 0;
  fb_lock_store lock_store = 0;
  fb_lock_lease first_lease = 0;
  fb_lock_lease second_lease = 0;
  fb_rate_limit_result decision;
  fb_bulkhead_result bulkhead_decision;
  fb_budget_result budget_decision;
  fb_lock_acquire_result lock_decision;
  fb_lock_status lock_status;
  int64_t delay_ns = 0;
  int32_t expired = 0;
  int32_t released = 0;

  NimMain();

  if (fb_abi_version() < 1) {
    return 11;
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

  puts("flowbrigade C ABI smoke test passed");
  return 0;
}
