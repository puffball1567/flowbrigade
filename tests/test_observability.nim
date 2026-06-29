import std/[json, sequtils, strutils, unittest]

import flowbrigade

suite "observability export helpers":
  test "converts metric events to generic observation records":
    let record = toObservationRecord(MetricEvent(
      name: "flowbrigade.retry.sleeping",
      value: 1.0,
      tags: @[("attempt", "2"), ("delay_seconds", "0.15")]
    ))

    check record.name == "flowbrigade.retry.sleeping"
    check record.value == 1.0
    check ("attempt", "2") in record.attributes

  test "converts metric events to JSON":
    let node = toJson(MetricEvent(
      name: "flowbrigade.ratelimit.decision",
      value: 1.0,
      tags: @[("allowed", "false"), ("remaining", "0")]
    ))

    check node["name"].getStr() == "flowbrigade.ratelimit.decision"
    check node["value"].getFloat() == 1.0
    check node["attributes"]["allowed"].getStr() == "false"
    check node["attributes"]["remaining"].getStr() == "0"

  test "formats metric events as prometheus-style lines":
    let line = toPrometheusLine(MetricEvent(
      name: "flowbrigade.retry.sleeping",
      value: 1.0,
      tags: @[("attempt", "2"), ("source.kind", "api")]
    ))

    check line == "flowbrigade_retry_sleeping{attempt=\"2\",source_kind=\"api\"} 1.0"

  test "formats multiple metric events as JSON lines":
    let lines = toJsonLines(@[
      MetricEvent(name: "flowbrigade.retry.attempt", value: 1.0, tags: @[("attempt", "1")]),
      MetricEvent(name: "flowbrigade.retry.success", value: 1.0, tags: @[("attempt", "2")])
    ])

    let parts = lines.splitLines()

    check parts.len == 2
    check parseJson(parts[0])["name"].getStr() == "flowbrigade.retry.attempt"
    check parseJson(parts[1])["attributes"]["attempt"].getStr() == "2"

  test "formats multiple observation records as prometheus-style text":
    let records = @[
      ObservationRecord(name: "flowbrigade.retry.attempt", value: 1.0, attributes: @[("attempt", "1")]),
      ObservationRecord(name: "flowbrigade.retry.success", value: 1.0, attributes: @[("attempt", "2")])
    ]

    let text = toPrometheusText(records)

    check text == "flowbrigade_retry_attempt{attempt=\"1\"} 1.0\n" &
      "flowbrigade_retry_success{attempt=\"2\"} 1.0"

  test "empty observation batches format as empty text":
    let events: seq[MetricEvent] = @[]
    let records: seq[ObservationRecord] = @[]

    check toJsonLines(events) == ""
    check toPrometheusText(records) == ""

  test "escapes prometheus-style label values":
    let line = toPrometheusLine(MetricEvent(
      name: "flowbrigade.test",
      value: 1.0,
      tags: @[("message", "quoted \"value\"\nnext")]
    ))

    check line == "flowbrigade_test{message=\"quoted \\\"value\\\"\\nnext\"} 1.0"

  test "rejects empty metric and attribute names":
    expect ObservabilityFormatError:
      discard sanitizeMetricName(" ")
    expect ObservabilityFormatError:
      discard sanitizeAttributeKey(" ")

  test "converts control reports to JSON":
    let report = analyzeControlSignals(@[
      failureSignal(),
      failureSignal(),
      successSignal(10.ms),
      successSignal(20.ms),
      successSignal(30.ms),
      successSignal(40.ms),
      successSignal(50.ms),
      successSignal(60.ms),
      successSignal(70.ms),
      successSignal(80.ms)
    ])

    let node = controlReportToJson(report)

    check node["schema"].getStr() == "flowbrigade.control_report.v1"
    check node["mode"].getStr() == "advice-only"
    check node["signalCount"].getInt() == 10
    check node["failureRate"].getFloat() == 0.2
    check node["hints"].len > 0

  test "converts control reports to metric events":
    let report = analyzeControlSignals(@[
      rateLimitedSignal(),
      rateLimitedSignal(),
      rateLimitedSignal(),
      rateLimitedSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal(),
      successSignal()
    ])

    let metrics = controlReportMetrics(report)

    check metrics.anyIt(it.name == "flowbrigade.control.rate_limit_rate" and it.value == 0.4)
    check metrics.anyIt(it.name == "flowbrigade.control.hint")
