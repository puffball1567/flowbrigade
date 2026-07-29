type
  RetryConfigError* = object of ValueError
  RetryDeadlineExceededError* = object of CatchableError
  RetryCancelledError* = object of CatchableError
