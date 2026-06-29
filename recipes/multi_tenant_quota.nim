import flowbrigade

type
  Plan = enum
    freePlan, paidPlan

  TenantRequest = object
    tenantId: string
    userId: string
    plan: Plan

proc quotaFor(plan: Plan): BudgetConfig =
  case plan
  of freePlan:
    dailyQuotaConfig(3)
  of paidPlan:
    monthlyQuotaConfig(1000)

let tenantKey = initKeyExtractor[TenantRequest]()
  .withPart(proc(request: TenantRequest): string = "tenant")
  .withPart(proc(request: TenantRequest): string = request.tenantId)

let userKey = initKeyExtractor[TenantRequest]()
  .withPart(proc(request: TenantRequest): string = "tenant")
  .withPart(proc(request: TenantRequest): string = request.tenantId)
  .withPart(proc(request: TenantRequest): string = "user")
  .withPart(proc(request: TenantRequest): string = request.userId)

proc consumeTenantQuota(
    tenantBudget: var BudgetLedger;
    userBudget: var BudgetLedger;
    request: TenantRequest;
    cost = 1
): BudgetResult =
  let tenantDecision = tenantBudget.consume(tenantKey.extract(request), cost)
  if not tenantDecision.allowed:
    return tenantDecision
  userBudget.consume(userKey.extract(request), cost)

var freeTenantBudget = initBudgetLedger(quotaFor(freePlan))
var freeUserBudget = initBudgetLedger(limit = 2, per = 1.day)

let request = TenantRequest(
  tenantId: "tenant-1",
  userId: "user-1",
  plan: freePlan
)

let first = consumeTenantQuota(freeTenantBudget, freeUserBudget, request)
let second = consumeTenantQuota(freeTenantBudget, freeUserBudget, request)
let third = consumeTenantQuota(freeTenantBudget, freeUserBudget, request)

doAssert first.allowed
doAssert second.allowed
doAssert not third.allowed

var paidTenantBudget = initBudgetLedger(quotaFor(paidPlan))
var paidUserBudget = initBudgetLedger(limit = 100, per = 30.day)

let paidRequest = TenantRequest(
  tenantId: "tenant-1",
  userId: "user-1",
  plan: paidPlan
)

doAssert consumeTenantQuota(paidTenantBudget, paidUserBudget, paidRequest, cost = 250).allowed
