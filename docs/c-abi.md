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
- timeout and deadline handles
- budget ledger handles
- in-memory lock store and lease handles
- throttle and debounce handles

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

## C Example

```c
#include <stdint.h>
#include <stdio.h>

#include "flowbrigade.h"

int main(void) {
  int64_t nanos = 0;

  NimMain();

  if (fb_duration_parse("1s500ms", 7, &nanos) != FB_OK) {
    fprintf(stderr, "%s\n", fb_last_error());
    return 1;
  }

  printf("%lld\n", (long long)nanos);
  return 0;
}
```

Compile against a locally built shared library:

```sh
nimble cabi
gcc -Iinclude examples/c_abi_quickstart.c -L/tmp -lflowbrigade -Wl,-rpath,/tmp -o /tmp/flowbrigade-c-abi-example
/tmp/flowbrigade-c-abi-example
```

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

`fb_last_error()` returns diagnostic text for the most recent ABI error. The
current implementation stores this text process-wide, so callers should not
treat it as thread-local state.

`fb_abi_version()` returns the integer ABI version. Bindings should check this
before assuming newer functions exist.

## Thread Safety

Opaque handles are mutable and are not internally synchronized. Do not mutate
the same handle from multiple threads without application-level locking. Create
separate handles per thread, or protect shared handles with the host language's
synchronization primitive.

## Keyed APIs

Keyed functions, such as the budget ledger API, accept string input as
`const char*` plus byte length. FlowBrigade copies the bytes during the call and
does not retain the caller's pointer. Keys are normalized by the underlying Nim
API, including trimming surrounding whitespace and rejecting empty keys.

Lock lease tokens stay inside opaque `fb_lock_lease` handles. Foreign callers
should release or inspect leases through the handle and destroy each lease handle
when it is no longer needed.

## Stability

This ABI is experimental. It is meant to support future Zig, Odin, Rust, C, and
other bindings, but it should stay smaller than the Nim API. Higher-level
features such as retry callbacks, fallback providers, storage adapters, and web
framework bridges should be wrapped by language-specific code rather than forced
through this C layer.
