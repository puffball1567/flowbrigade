import flowbrigade

type PasswordResetAttempt = object
  accountId: string
  destination: string

var auditActions: seq[StoredFixedWindowAction] = @[]
let storage = initInMemoryRateLimitStorage().asRateLimitStorage()
  .withStorageFailureMode(failClosed)

let limiter = initStoredFixedWindow(
  prefix = "password_reset",
  limit = 3,
  per = 1.hr,
  storage = storage,
  audit = proc(event: StoredFixedWindowAuditEvent) =
    auditActions.add(event.action)
)

let keyExtractor = initKeyExtractor[PasswordResetAttempt]()
  .withPart(proc(attempt: PasswordResetAttempt): string = attempt.accountId)
  .withPart(proc(attempt: PasswordResetAttempt): string = attempt.destination)

proc canSendResetEmail(attempt: PasswordResetAttempt): bool =
  let key = keyExtractor.extract(attempt)
  let decision = limiter.consume(key)
  if not decision.allowed:
    return false
  true

let attempt = PasswordResetAttempt(
  accountId: "account-42",
  destination: "email-fingerprint-9f0c"
)

doAssert canSendResetEmail(attempt)
doAssert canSendResetEmail(attempt)
doAssert canSendResetEmail(attempt)
doAssert not canSendResetEmail(attempt)
doAssert auditActions.len == 4
