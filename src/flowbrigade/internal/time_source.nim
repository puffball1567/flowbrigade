import std/[monotimes, times]

type
  TimeSourceError* = object of ValueError

  TimeSourceKind = enum
    tskMonotonic, tskManual

  TimeSource* = ref object
    case kind: TimeSourceKind
    of tskMonotonic:
      startedAt: MonoTime
    of tskManual:
      current: Duration

  ManualTimeSource* = TimeSource

proc initTimeSource*(): TimeSource =
  TimeSource(kind: tskMonotonic, startedAt: getMonoTime())

proc initManualTimeSource*(start = initDuration()): ManualTimeSource =
  ManualTimeSource(kind: tskManual, current: start)

proc now*(source: TimeSource): Duration =
  case source.kind
  of tskMonotonic:
    getMonoTime() - source.startedAt
  of tskManual:
    source.current

proc advance*(source: ManualTimeSource; amount: Duration) =
  doAssert source.kind == tskManual
  if amount < initDuration():
    raise newException(TimeSourceError, "time source advance must be non-negative")
  source.current += amount
