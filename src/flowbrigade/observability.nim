import std/[json, strutils, times]

import ./control_diagnostics
import ./metrics

type
  ObservabilityFormatError* = object of ValueError

  ObservationAttribute* = tuple[key: string, value: string]

  ObservationRecord* = object
    name*: string
    value*: float
    attributes*: seq[ObservationAttribute]

proc sanitizeMetricName*(name: string): string =
  let trimmed = name.strip()
  if trimmed.len == 0:
    raise newException(ObservabilityFormatError, "metric name must not be empty")
  for ch in trimmed:
    if ch in {'a'..'z', 'A'..'Z', '0'..'9', '_', ':'}:
      result.add(ch)
    elif ch in {'.', '-'}:
      result.add('_')
    else:
      result.add('_')
  if result[0] in {'0'..'9'}:
    result = "_" & result

proc sanitizeAttributeKey*(key: string): string =
  let trimmed = key.strip()
  if trimmed.len == 0:
    raise newException(ObservabilityFormatError, "attribute key must not be empty")
  for ch in trimmed:
    if ch in {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
      result.add(ch)
    elif ch in {'.', '-'}:
      result.add('_')
    else:
      result.add('_')
  if result[0] in {'0'..'9'}:
    result = "_" & result

proc escapeLabelValue(value: string): string =
  for ch in value:
    case ch
    of '\\':
      result.add("\\\\")
    of '"':
      result.add("\\\"")
    of '\n':
      result.add("\\n")
    else:
      result.add(ch)

proc toObservationRecord*(event: MetricEvent): ObservationRecord =
  result = ObservationRecord(
    name: event.name,
    value: event.value,
    attributes: @[]
  )
  for tag in event.tags:
    result.attributes.add((tag.key, tag.value))

proc toJson*(record: ObservationRecord): JsonNode =
  result = %*{
    "name": record.name,
    "value": record.value,
    "attributes": newJObject()
  }
  for attribute in record.attributes:
    result["attributes"][attribute.key] = %attribute.value

proc toJson*(event: MetricEvent): JsonNode =
  event.toObservationRecord().toJson()

proc toJsonLine*(record: ObservationRecord): string =
  $record.toJson()

proc toJsonLine*(event: MetricEvent): string =
  event.toObservationRecord().toJsonLine()

proc toJsonLines*(records: openArray[ObservationRecord]): string =
  var lines: seq[string] = @[]
  for record in records:
    lines.add(record.toJsonLine())
  lines.join("\n")

proc toJsonLines*(events: openArray[MetricEvent]): string =
  var lines: seq[string] = @[]
  for event in events:
    lines.add(event.toJsonLine())
  lines.join("\n")

proc toPrometheusLine*(record: ObservationRecord): string =
  result = sanitizeMetricName(record.name)
  if record.attributes.len > 0:
    var labels: seq[string] = @[]
    for attribute in record.attributes:
      labels.add(sanitizeAttributeKey(attribute.key) & "=\"" & escapeLabelValue(attribute.value) & "\"")
    result.add("{" & labels.join(",") & "}")
  result.add(" " & $record.value)

proc toPrometheusLine*(event: MetricEvent): string =
  event.toObservationRecord().toPrometheusLine()

proc toPrometheusText*(records: openArray[ObservationRecord]): string =
  var lines: seq[string] = @[]
  for record in records:
    lines.add(record.toPrometheusLine())
  lines.join("\n")

proc toPrometheusText*(events: openArray[MetricEvent]): string =
  var lines: seq[string] = @[]
  for event in events:
    lines.add(event.toPrometheusLine())
  lines.join("\n")

proc controlReportToJson*(report: ControlReport): JsonNode =
  result = %*{
    "schema": "flowbrigade.control_report.v1",
    "mode": report.mode,
    "signalCount": report.signalCount,
    "successRate": report.successRate,
    "failureRate": report.failureRate,
    "timeoutRate": report.timeoutRate,
    "rateLimitRate": report.rateLimitRate,
    "circuitOpenRate": report.circuitOpenRate,
    "bulkheadFullRate": report.bulkheadFullRate,
    "averageLatencySeconds": float(report.averageLatency.inNanoseconds) / 1_000_000_000.0,
    "hints": newJArray()
  }
  for hint in report.hints:
    result["hints"].add(%*{
      "kind": $hint.kind,
      "confidence": hint.confidence,
      "reason": hint.reason
    })

proc controlReportToJsonLine*(report: ControlReport): string =
  $controlReportToJson(report)

proc controlReportMetrics*(report: ControlReport): seq[MetricEvent] =
  result = @[
    MetricEvent(name: "flowbrigade.control.signals", value: report.signalCount.float),
    MetricEvent(name: "flowbrigade.control.success_rate", value: report.successRate),
    MetricEvent(name: "flowbrigade.control.failure_rate", value: report.failureRate),
    MetricEvent(name: "flowbrigade.control.timeout_rate", value: report.timeoutRate),
    MetricEvent(name: "flowbrigade.control.rate_limit_rate", value: report.rateLimitRate),
    MetricEvent(name: "flowbrigade.control.circuit_open_rate", value: report.circuitOpenRate),
    MetricEvent(name: "flowbrigade.control.bulkhead_full_rate", value: report.bulkheadFullRate)
  ]
  for hint in report.hints:
    result.add MetricEvent(
      name: "flowbrigade.control.hint",
      value: hint.confidence,
      tags: @[("kind", $hint.kind), ("mode", report.mode)]
    )
