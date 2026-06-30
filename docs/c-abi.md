# C ABI

FlowBrigade includes an experimental C ABI surface for small bindings in other
languages. The Nim package remains the reference implementation.

The first ABI surface is intentionally narrow:

- duration parsing and formatting
- fixed, linear, and exponential backoff delay calculation
- token bucket handles
- fixed window handles
- sliding window handles
- circuit breaker handles
- bulkhead handles

The ABI does not expose Nim strings, sequences, exceptions, refs, callbacks, or
framework adapters. Callers own output buffers. FlowBrigade owns opaque handles
created through the C API, and callers must release those handles with the
matching destroy function.

## Build

```sh
nimble cabi
```

The task builds `/tmp/libflowbrigade.so` from `src/flowbrigade_c.nim`.

Manual build:

```sh
nim c --app:lib -p:src --out:/tmp/libflowbrigade.so src/flowbrigade_c.nim
```

The C declarations are in [include/flowbrigade.h](../include/flowbrigade.h).

## Runtime Initialization

Call `NimMain()` once before calling `fb_*` functions from a non-Nim host
process. Nim exports this symbol when building the shared library.

```c
#include "flowbrigade.h"

int main(void) {
  NimMain();
  /* call fb_* functions here */
  return 0;
}
```

## Error Handling

Every fallible function returns an integer status code:

- `FB_OK`
- `FB_ERR_INVALID_ARGUMENT`
- `FB_ERR_BUFFER_TOO_SMALL`
- `FB_ERR_INTERNAL`

Nim exceptions are caught at the ABI boundary and converted into these status
codes. No exception should cross into C.

## Stability

This ABI is experimental. It is meant to support future Zig, Odin, Rust, C, and
other bindings, but it should stay smaller than the Nim API. Higher-level
features such as retry callbacks, fallback providers, storage adapters, and web
framework bridges should be wrapped by language-specific code rather than forced
through this C layer.
