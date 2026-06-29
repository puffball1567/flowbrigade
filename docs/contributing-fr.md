# Guide de contribution

Ce document est un résumé français de `CONTRIBUTING.md`. La version anglaise
fait autorité en cas de différence.

FlowBrigade est une petite bibliothèque centrée sur les utilitaires de contrôle
temporel: retry, backoff, rate limiting, quotas, fallback, circuit breaker,
bulkhead, timeout et observability helpers.

## Contributions bienvenues

- Ajouter des tests manquants.
- Couvrir les cas limites et les chemins d'erreur.
- Corriger des bugs avec un test de régression.
- Améliorer README, docs et recipes.
- Ajouter des tests de compatibilité pour les adapters.

Si vous trouvez un bug et pouvez le corriger proprement, merci d'inclure la
correction et un test de régression dans la même pull request.

## Approche TDD

Pour un nouveau comportement, préférez:

1. Ajouter ou modifier un test ciblé dans `tests/`.
2. Vérifier qu'il échoue pour la raison attendue.
3. Implémenter le changement le plus clair et le plus petit possible.
4. Lancer `tests/all.nim`.
5. Mettre à jour README ou docs si le comportement public change.

Les tests dépendants du temps doivent utiliser la manual time source interne
plutôt que de dormir en temps réel.

## Commandes utiles

```sh
nim r --nimcache:/tmp/flowbrigade-nimcache -p:src tests/all.nim
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim test
nimble --nimbleDir:/tmp/flowbrigade-nimble --nim:/path/to/nim snippets
```

## Hors périmètre

- API publique `Clock`
- timezone, calculs calendaires, formatage de dates
- middleware propre à un framework HTTP
- abstraction cache/storage générique sans lien avec le rate limiting

Les parties difficiles sont souvent les plus utiles. Ajoutez plusieurs tests
ciblés quand le comportement est risqué ou ambigu.
