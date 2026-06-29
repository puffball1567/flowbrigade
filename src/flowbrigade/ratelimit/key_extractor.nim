import ./errors
import ./key_builder
import ./storage

type
  KeyPartProc*[T] = proc(value: T): string {.closure.}

  KeyExtractor*[T] = object
    parts: seq[KeyPartProc[T]]
    separator: string
    maxPartLength: int
    maxLength: int

proc initKeyExtractor*[T](
    separator = ":";
    maxPartLength = 128;
    maxLength = DefaultMaxRateLimitKeyLength
): KeyExtractor[T] =
  if separator.len == 0:
    raise newException(RateLimitConfigError, "separator must not be empty")
  if maxPartLength <= 0:
    raise newException(RateLimitConfigError, "maxPartLength must be positive")
  if maxLength <= 0:
    raise newException(RateLimitConfigError, "maxLength must be positive")
  KeyExtractor[T](
    separator: separator,
    maxPartLength: maxPartLength,
    maxLength: maxLength
  )

proc addPart*[T](
    extractor: var KeyExtractor[T];
    part: KeyPartProc[T]
) =
  if part.isNil:
    raise newException(RateLimitConfigError, "key part proc must not be nil")
  extractor.parts.add(part)

proc withPart*[T](
    extractor: KeyExtractor[T];
    part: KeyPartProc[T]
): KeyExtractor[T] =
  result = extractor
  result.addPart(part)

proc extract*[T](extractor: KeyExtractor[T]; value: T): string =
  if extractor.parts.len == 0:
    raise newException(RateLimitConfigError, "key extractor needs at least one part")
  var parts: seq[string] = @[]
  for part in extractor.parts:
    parts.add(part(value))
  rateLimitKey(
    parts,
    separator = extractor.separator,
    maxPartLength = extractor.maxPartLength,
    maxLength = extractor.maxLength
  )
