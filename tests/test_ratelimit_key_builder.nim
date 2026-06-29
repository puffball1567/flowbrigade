import std/unittest

import flowbrigade/ratelimit

suite "rate limit key builder":
  test "builds stable compound keys":
    check rateLimitKey(["user", "42", "login"]) == "user:42:login"

  test "supports custom separators":
    check rateLimitKey(["ip", "127.0.0.1"], separator = "|") == "ip|127.0.0.1"

  test "rejects unsafe key parts":
    expect RateLimitError:
      discard rateLimitKey([])
    expect RateLimitError:
      discard rateLimitKey([""])
    expect RateLimitError:
      discard rateLimitKey(["   "])
    expect RateLimitError:
      discard rateLimitKey(["user:42"])
    expect RateLimitError:
      discard rateLimitKey(["user\L42"])
    expect RateLimitError:
      discard rateLimitKey(["abcdef"], maxPartLength = 5)
    expect RateLimitError:
      discard rateLimitKey(["abc", "def"], maxLength = 5)

  test "builds opaque keys with caller supplied fingerprint":
    let key = opaqueRateLimitKey(
      ["email", "alice@example.com"],
      proc(value: string): string = "fp-" & $value.len
    )

    check key == "fp-23"

  test "rejects unsafe fingerprints":
    expect RateLimitError:
      discard opaqueRateLimitKey(["alice"], nil)
    expect RateLimitError:
      discard opaqueRateLimitKey(["alice"], proc(value: string): string = "")
    expect RateLimitError:
      discard opaqueRateLimitKey(["alice"], proc(value: string): string = "bad:key")
    expect RateLimitError:
      discard opaqueRateLimitKey(["alice"], proc(value: string): string = "bad\Lkey")
