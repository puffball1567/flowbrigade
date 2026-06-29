import std/unittest

import flowbrigade/ratelimit

type
  RequestShape = object
    userId: string
    route: string
    httpMethod: string

suite "rate limit key extractor":
  test "extracts compound keys":
    var extractor = initKeyExtractor[RequestShape]()
    extractor.addPart(proc(request: RequestShape): string = request.userId)
    extractor.addPart(proc(request: RequestShape): string = request.route)

    let key = extractor.extract(RequestShape(userId: "42", route: "login"))

    check key == "42:login"

  test "supports fluent part addition":
    let extractor = initKeyExtractor[RequestShape]()
      .withPart(proc(request: RequestShape): string = request.httpMethod)
      .withPart(proc(request: RequestShape): string = request.route)

    check extractor.extract(RequestShape(httpMethod: "POST", route: "login")) == "POST:login"

  test "rejects invalid extractor config":
    expect RateLimitConfigError:
      discard initKeyExtractor[RequestShape](separator = "")
    expect RateLimitConfigError:
      discard initKeyExtractor[RequestShape](maxPartLength = 0)

  test "rejects nil and missing parts":
    var extractor = initKeyExtractor[RequestShape]()

    expect RateLimitConfigError:
      extractor.addPart(nil)
    expect RateLimitConfigError:
      discard extractor.extract(RequestShape())

  test "rejects unsafe extracted values":
    var extractor = initKeyExtractor[RequestShape]()
    extractor.addPart(proc(request: RequestShape): string = request.userId)

    expect RateLimitError:
      discard extractor.extract(RequestShape(userId: " "))
    expect RateLimitError:
      discard extractor.extract(RequestShape(userId: "a:b"))
    expect RateLimitError:
      discard extractor.extract(RequestShape(userId: "a" & char(10)))
