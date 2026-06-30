#include <stdint.h>
#include <stdio.h>

#include "flowbrigade.h"

int main(void) {
  int64_t nanos = 0;
  fb_token_bucket bucket = 0;
  fb_backoff_policy backoff = 0;
  fb_bulkhead bulkhead = 0;
  fb_rate_limit_result decision;
  fb_bulkhead_result bulkhead_decision;
  int64_t delay_ns = 0;

  NimMain();

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

  puts("flowbrigade C ABI smoke test passed");
  return 0;
}
