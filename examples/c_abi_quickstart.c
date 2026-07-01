#include <stdint.h>
#include <stdio.h>

#include "flowbrigade.h"

int main(void) {
  int64_t nanos = 0;
  fb_fixed_window limiter = 0;
  fb_rate_limit_result decision;

  NimMain();

  if (fb_abi_version() < 2) {
    fprintf(stderr, "unsupported FlowBrigade C ABI\n");
    return 1;
  }

  if (fb_duration_parse("1s500ms", 7, &nanos) != FB_OK) {
    fprintf(stderr, "duration parse failed: %s\n", fb_last_error());
    return 2;
  }

  if (fb_fixed_window_create(2, 60000000000LL, &limiter) != FB_OK) {
    fprintf(stderr, "limiter create failed: %s\n", fb_last_error());
    return 3;
  }

  if (fb_fixed_window_consume(limiter, 1, &decision) != FB_OK) {
    fprintf(stderr, "limiter consume failed: %s\n", fb_last_error());
    fb_fixed_window_destroy(limiter);
    return 4;
  }

  printf("duration_ns=%lld allowed=%d remaining=%d\n",
         (long long)nanos,
         decision.allowed,
         decision.remaining);

  fb_fixed_window_destroy(limiter);
  return 0;
}
