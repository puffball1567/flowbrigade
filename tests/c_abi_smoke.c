#include <stdint.h>
#include <stdio.h>

#include "flowbrigade.h"

int main(void) {
  int64_t nanos = 0;
  fb_token_bucket bucket = 0;
  fb_rate_limit_result decision;

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
  puts("flowbrigade C ABI smoke test passed");
  return 0;
}
