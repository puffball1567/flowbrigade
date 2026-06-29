import std/locks

import ./policy
import ./ratelimit

type
  ThreadSafeLimiterRegistry* = ref object
    lock: Lock
    registry: LimiterRegistry

  ThreadSafeFlowPolicy* = ref object
    lock: Lock
    policy: FlowPolicy

proc initThreadSafeLimiterRegistry*(registry: LimiterRegistry): ThreadSafeLimiterRegistry =
  ## Wraps a limiter registry with a process-local mutex.
  ##
  ## This is intended for multi-threaded in-process servers. It does not make
  ## limits shared across processes; use a storage adapter such as Redis for
  ## that deployment shape.
  new(result)
  result.registry = registry
  initLock(result.lock)

proc initThreadSafeFlowPolicy*(policy: FlowPolicy): ThreadSafeFlowPolicy =
  ## Wraps a FlowPolicy with a process-local mutex.
  ##
  ## Use this when a multi-threaded server shares one in-memory FlowPolicy
  ## across request handler threads.
  new(result)
  result.policy = policy
  initLock(result.lock)

proc validateRegistry(registry: ThreadSafeLimiterRegistry) =
  if registry.isNil:
    raise newException(RateLimitConfigError, "thread-safe registry must not be nil")

proc validatePolicy(policy: ThreadSafeFlowPolicy) =
  if policy.isNil:
    raise newException(FlowPolicyConfigError, "thread-safe policy must not be nil")

proc inspect*(
    registry: ThreadSafeLimiterRegistry;
    name: string;
    key = "global";
    cost = 1
): RateLimitResult =
  registry.validateRegistry()
  withLock registry.lock:
    result = registry.registry.inspect(name, key, cost)

proc consume*(
    registry: ThreadSafeLimiterRegistry;
    name: string;
    key = "global";
    cost = 1
): RateLimitResult =
  registry.validateRegistry()
  withLock registry.lock:
    result = registry.registry.consume(name, key, cost)

proc allow*(
    registry: ThreadSafeLimiterRegistry;
    name: string;
    key = "global";
    cost = 1
): bool =
  registry.consume(name, key, cost).allowed

proc clear*(
    registry: ThreadSafeLimiterRegistry;
    name: string;
    key = "global"
): bool =
  registry.validateRegistry()
  withLock registry.lock:
    result = registry.registry.clear(name, key)

proc inspect*(policy: ThreadSafeFlowPolicy; key: string; cost = 1): RateLimitResult =
  policy.validatePolicy()
  withLock policy.lock:
    result = policy.policy.inspect(key, cost)

proc consume*(policy: ThreadSafeFlowPolicy; key: string; cost = 1): RateLimitResult =
  policy.validatePolicy()
  withLock policy.lock:
    result = policy.policy.consume(key, cost)

proc allow*(policy: ThreadSafeFlowPolicy; key: string; cost = 1): bool =
  policy.consume(key, cost).allowed
