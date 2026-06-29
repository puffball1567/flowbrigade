import std/[asyncdispatch, strutils]

import ./circuit_breaker

type
  FallbackConfigError* = object of ValueError
  FallbackError* = object of CatchableError

  FallbackEventKind* = enum
    fallbackAttempt,
    fallbackSucceeded,
    fallbackFailed,
    fallbackSkipped

  FallbackEvent* = object
    kind*: FallbackEventKind
    provider*: string
    attempt*: int
    error*: string

  FallbackObserverProc* = proc(event: FallbackEvent) {.closure.}
  FallbackPredicate* = proc(error: ref CatchableError): bool {.closure.}

  FallbackProvider*[T] = object
    name*: string
    call*: proc(): T {.closure.}
    breaker*: ptr CircuitBreaker

  AsyncFallbackProvider*[T] = object
    name*: string
    call*: proc(): Future[T] {.closure.}
    breaker*: ptr CircuitBreaker

  FallbackResult*[T] = object
    value*: T
    provider*: string
    attempts*: int
    failedProviders*: seq[string]
    lastError*: string

proc defaultFallbackPredicate*(error: ref CatchableError): bool =
  true

proc validateProviderName(name: string): string =
  result = name.strip()
  if result.len == 0:
    raise newException(FallbackConfigError, "provider name must not be empty")

proc fallbackProvider*[T](
    name: string;
    call: proc(): T {.closure.}
): FallbackProvider[T] =
  if call.isNil:
    raise newException(FallbackConfigError, "provider call must not be nil")
  FallbackProvider[T](name: validateProviderName(name), call: call)

proc fallbackProvider*[T](
    name: string;
    breaker: var CircuitBreaker;
    call: proc(): T {.closure.}
): FallbackProvider[T] =
  result = fallbackProvider(name, call)
  result.breaker = breaker.addr

proc asyncFallbackProvider*[T](
    name: string;
    call: proc(): Future[T] {.closure.}
): AsyncFallbackProvider[T] =
  if call.isNil:
    raise newException(FallbackConfigError, "provider call must not be nil")
  AsyncFallbackProvider[T](name: validateProviderName(name), call: call)

proc asyncFallbackProvider*[T](
    name: string;
    breaker: var CircuitBreaker;
    call: proc(): Future[T] {.closure.}
): AsyncFallbackProvider[T] =
  result = asyncFallbackProvider(name, call)
  result.breaker = breaker.addr

proc emit(observer: FallbackObserverProc; event: FallbackEvent) =
  if not observer.isNil:
    observer(event)

proc fallbackErrorMessage(error: ref CatchableError): string =
  result = error.msg
  let marker = result.find("\nAsync traceback:")
  if marker >= 0:
    result = result[0 ..< marker]

proc tryFallback*[T](
    providers: openArray[FallbackProvider[T]];
    shouldFallback: FallbackPredicate = defaultFallbackPredicate;
    observer: FallbackObserverProc = nil
): FallbackResult[T] =
  if providers.len == 0:
    raise newException(FallbackConfigError, "at least one provider is required")
  if shouldFallback.isNil:
    raise newException(FallbackConfigError, "fallback predicate must not be nil")

  var lastError = ""
  var failedProviders: seq[string] = @[]
  var attempts = 0

  for provider in providers:
    let name = validateProviderName(provider.name)
    if provider.call.isNil:
      raise newException(FallbackConfigError, "provider call must not be nil")

    if provider.breaker != nil and not provider.breaker[].allow():
      observer.emit(FallbackEvent(
        kind: fallbackSkipped,
        provider: name,
        attempt: attempts + 1,
        error: "circuit breaker is open"
      ))
      failedProviders.add(name)
      lastError = "circuit breaker is open"
      continue

    inc attempts
    observer.emit(FallbackEvent(kind: fallbackAttempt, provider: name, attempt: attempts))
    try:
      let value = provider.call()
      if provider.breaker != nil:
        provider.breaker[].recordSuccess()
      observer.emit(FallbackEvent(kind: fallbackSucceeded, provider: name, attempt: attempts))
      return FallbackResult[T](
        value: value,
        provider: name,
        attempts: attempts,
        failedProviders: failedProviders,
        lastError: lastError
      )
    except CatchableError as error:
      if provider.breaker != nil:
        provider.breaker[].recordFailure()
      lastError = fallbackErrorMessage(error)
      failedProviders.add(name)
      observer.emit(FallbackEvent(
        kind: fallbackFailed,
        provider: name,
        attempt: attempts,
        error: lastError
      ))
      if not shouldFallback(error):
        raise

  raise newException(FallbackError, "all fallback providers failed: " & lastError)

proc fallback*[T](
    primary: proc(): T {.closure.};
    secondary: proc(): T {.closure.};
    shouldFallback: FallbackPredicate = defaultFallbackPredicate;
    observer: FallbackObserverProc = nil
): T =
  tryFallback(
    [
      fallbackProvider("primary", primary),
      fallbackProvider("secondary", secondary)
    ],
    shouldFallback = shouldFallback,
    observer = observer
  ).value

proc tryInOrder*[T](
    providers: openArray[FallbackProvider[T]];
    shouldFallback: FallbackPredicate = defaultFallbackPredicate;
    observer: FallbackObserverProc = nil
): FallbackResult[T] =
  tryFallback(providers, shouldFallback = shouldFallback, observer = observer)

proc tryFallbackAsyncSeq[T](
    providers: seq[AsyncFallbackProvider[T]];
    shouldFallback: FallbackPredicate = defaultFallbackPredicate;
    observer: FallbackObserverProc = nil
): Future[FallbackResult[T]] {.async.} =
  if providers.len == 0:
    raise newException(FallbackConfigError, "at least one provider is required")
  if shouldFallback.isNil:
    raise newException(FallbackConfigError, "fallback predicate must not be nil")

  var lastError = ""
  var failedProviders: seq[string] = @[]
  var attempts = 0

  for provider in providers:
    let name = validateProviderName(provider.name)
    if provider.call.isNil:
      raise newException(FallbackConfigError, "provider call must not be nil")

    if provider.breaker != nil and not provider.breaker[].allow():
      observer.emit(FallbackEvent(
        kind: fallbackSkipped,
        provider: name,
        attempt: attempts + 1,
        error: "circuit breaker is open"
      ))
      failedProviders.add(name)
      lastError = "circuit breaker is open"
      continue

    inc attempts
    observer.emit(FallbackEvent(kind: fallbackAttempt, provider: name, attempt: attempts))
    try:
      let value = await provider.call()
      if provider.breaker != nil:
        provider.breaker[].recordSuccess()
      observer.emit(FallbackEvent(kind: fallbackSucceeded, provider: name, attempt: attempts))
      return FallbackResult[T](
        value: value,
        provider: name,
        attempts: attempts,
        failedProviders: failedProviders,
        lastError: lastError
      )
    except CatchableError as error:
      if provider.breaker != nil:
        provider.breaker[].recordFailure()
      lastError = fallbackErrorMessage(error)
      failedProviders.add(name)
      observer.emit(FallbackEvent(
        kind: fallbackFailed,
        provider: name,
        attempt: attempts,
        error: lastError
      ))
      if not shouldFallback(error):
        raise

  raise newException(FallbackError, "all fallback providers failed: " & lastError)

proc tryFallbackAsync*[T](
    providers: openArray[AsyncFallbackProvider[T]];
    shouldFallback: FallbackPredicate = defaultFallbackPredicate;
    observer: FallbackObserverProc = nil
): Future[FallbackResult[T]] =
  var copied: seq[AsyncFallbackProvider[T]] = @[]
  for provider in providers:
    copied.add(provider)
  tryFallbackAsyncSeq(copied, shouldFallback = shouldFallback, observer = observer)

proc fallbackAsync*[T](
    primary: proc(): Future[T] {.closure.};
    secondary: proc(): Future[T] {.closure.};
    shouldFallback: FallbackPredicate = defaultFallbackPredicate;
    observer: FallbackObserverProc = nil
): Future[T] {.async.} =
  let result = await tryFallbackAsync(
    [
      asyncFallbackProvider("primary", primary),
      asyncFallbackProvider("secondary", secondary)
    ],
    shouldFallback = shouldFallback,
    observer = observer
  )
  result.value

proc tryInOrderAsync*[T](
    providers: openArray[AsyncFallbackProvider[T]];
    shouldFallback: FallbackPredicate = defaultFallbackPredicate;
    observer: FallbackObserverProc = nil
): Future[FallbackResult[T]] =
  tryFallbackAsync(providers, shouldFallback = shouldFallback, observer = observer)
