import std/strutils

import ./errors
import ./storage

type
  ## Converts validated key material into a non-reversible identifier.
  ##
  ## FlowBrigade does not ship hashing or encryption. Pass a vetted fingerprint
  ## function from your application when keys contain user identifiers or other
  ## sensitive values.
  RateLimitFingerprintProc* = proc(value: string): string {.closure.}

proc validateKeyComponent(name, value, separator: string; maxLength: int) =
  if value.len == 0:
    raise newException(RateLimitError, name & " must not be empty")
  if value.strip().len == 0:
    raise newException(RateLimitError, name & " must not be blank")
  if value.len > maxLength:
    raise newException(RateLimitError, name & " is too long")
  if separator.len > 0 and value.contains(separator):
    raise newException(RateLimitError, name & " must not contain the separator")
  for ch in value:
    if ord(ch) < 32 or ord(ch) == 127:
      raise newException(RateLimitError, name & " must not contain control characters")

proc rateLimitKey*(
    parts: openArray[string];
    separator = ":";
    maxPartLength = 128;
    maxLength = DefaultMaxRateLimitKeyLength
): string =
  ## Builds a validated compound rate-limit key.
  ##
  ## Empty, blank, overlong, control-character, and separator-containing parts
  ## are rejected. The returned key is suitable for local or external limiter
  ## storage, but it is not anonymized.
  if parts.len == 0:
    raise newException(RateLimitError, "key needs at least one part")
  if separator.len == 0:
    raise newException(RateLimitError, "separator must not be empty")
  if maxPartLength <= 0:
    raise newException(RateLimitError, "maxPartLength must be positive")
  if maxLength <= 0:
    raise newException(RateLimitError, "maxLength must be positive")

  var checked: seq[string] = @[]
  for index, part in parts:
    validateKeyComponent("key part " & $index, part, separator, maxPartLength)
    checked.add(part)

  result = checked.join(separator)
  if result.len > maxLength:
    raise newException(RateLimitError, "key is too long")

proc opaqueRateLimitKey*(
    parts: openArray[string];
    fingerprint: RateLimitFingerprintProc;
    separator = ":";
    maxPartLength = 256;
    maxLength = DefaultMaxRateLimitKeyLength
): string =
  ## Builds a validated opaque key through a caller-provided fingerprint proc.
  ##
  ## Use this when raw keys contain personal data or secrets. The fingerprint
  ## result is validated before it is returned.
  if fingerprint.isNil:
    raise newException(RateLimitError, "fingerprint proc must not be nil")
  let raw = rateLimitKey(
    parts,
    separator = separator,
    maxPartLength = maxPartLength,
    maxLength = maxLength
  )
  result = fingerprint(raw)
  validateKeyComponent("fingerprint", result, separator, maxLength)
