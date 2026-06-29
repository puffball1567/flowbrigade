# Beitragsleitfaden

Dieses Dokument ist eine deutsche Kurzfassung von `CONTRIBUTING.md`. Bei
Abweichungen gilt die englische Version.

FlowBrigade ist eine kleine Bibliothek fuer zeitbasierte Kontrollmechanismen:
Retry, Backoff, Rate Limiting, Quotas, Fallback, Circuit Breaker, Bulkhead,
Timeout und Observability-Hilfen.

## Willkommen sind

- fehlende Tests
- Edge-Case- und Fehlerpfad-Tests
- Bugfixes mit Regressionstest
- Verbesserungen an README, Docs und Recipes
- Kompatibilitaetstests fuer Adapter

Wenn Sie einen Bug finden und ihn sicher beheben koennen, fuegen Sie bitte den
Fix und einen Regressionstest in derselben Pull Request hinzu.

## TDD-Ablauf

Fuer neues Verhalten bevorzugen wir:

1. Einen fokussierten Test in `tests/` hinzufuegen oder aktualisieren.
2. Pruefen, dass der Test aus dem erwarteten Grund fehlschlaegt.
3. Die kleinste klare Implementierung vornehmen.
4. `tests/all.nim` ausfuehren.
5. README oder Docs aktualisieren, wenn sich oeffentliches Verhalten aendert.

Zeitabhaengige Tests sollten die interne manual time source verwenden statt in
Echtzeit zu schlafen.

## Nuetzliche Befehle

```sh
nim r --nimcache:/tmp/flowbrigade-nimcache -p:src tests/all.nim
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim test
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim snippets
```

## Nicht im Scope

- oeffentliche `Clock` API
- Zeitzonen, Kalenderarithmetik, Datumsformatierung
- HTTP-framework-spezifische Middleware
- generische Cache/Storage-Abstraktionen ohne Bezug zu Rate Limiting

Schwierige Bereiche nicht umgehen: Wenn Verhalten riskant oder mehrdeutig ist,
bitte mehrere gezielte Tests hinzufuegen.
