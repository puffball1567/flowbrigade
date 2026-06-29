import flowbrigade

let retryConfig = apiClientRetryConfig()

var limiter = initTokenBucket(rate = 10, per = 1.sec, burst = 20)
if limiter.allow():
  let result = retry(
    policy = retryConfig.policy,
    maxAttempts = retryConfig.maxAttempts,
    operation = proc(): string = "ok"
  )
  doAssert result == "ok"
