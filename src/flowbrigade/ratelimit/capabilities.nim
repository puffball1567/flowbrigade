import std/sets

import ./errors

type
  RateLimitCapability* = enum
    rlcInspect,
    rlcAtomicConsume,
    rlcClear,
    rlcTtl,
    rlcReservation,
    rlcDistributed

  RateLimitCapabilities* = object
    items*: HashSet[RateLimitCapability]

proc initRateLimitCapabilities*(
    capabilities: openArray[RateLimitCapability]
): RateLimitCapabilities =
  result = RateLimitCapabilities(items: initHashSet[RateLimitCapability]())
  for capability in capabilities:
    result.items.incl(capability)

proc supports*(
    capabilities: RateLimitCapabilities;
    capability: RateLimitCapability
): bool =
  capability in capabilities.items

proc requireCapability*(
    capabilities: RateLimitCapabilities;
    capability: RateLimitCapability
) =
  if not capabilities.supports(capability):
    raise newException(RateLimitConfigError, "rate-limit capability is required: " & $capability)

proc requireCapabilities*(
    capabilities: RateLimitCapabilities;
    required: openArray[RateLimitCapability]
) =
  for capability in required:
    capabilities.requireCapability(capability)

proc inMemoryRateLimitCapabilities*(): RateLimitCapabilities =
  initRateLimitCapabilities([
    rlcInspect,
    rlcAtomicConsume,
    rlcClear,
    rlcTtl
  ])

proc distributedFixedWindowCapabilities*(): RateLimitCapabilities =
  initRateLimitCapabilities([
    rlcInspect,
    rlcAtomicConsume,
    rlcClear,
    rlcTtl,
    rlcDistributed
  ])
