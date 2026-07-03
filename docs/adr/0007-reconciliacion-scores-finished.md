# ADR-0007 — Reconciliación de scores de partidos finished (el feed puede equivocarse)

- **Estado:** Implementada (2026-07-02)
- **Fecha:** 2026-06-21
- **Ámbito:** backend (football-data sync / integridad de datos)
- **Relacionada con:** SCRUM-321, ADR-0001 (ingesta KO), SCRUM-313 (guard anti-regresión), SCRUM-272 (score 90' + advancing_team)

## Implementación (2026-07-02)

Decisiones 1-4 implementadas, con enfoque **event-driven** (no recurrente): cuando un partido
pasa a `finished`, `SyncMatch` encola `MatchReconcileJob` a offsets escalonados (5 min, 15 min,
30 min, 1 h, 2 h, 4 h). Cada job corre `FootballData::ReconcileFinishedMatch`, que re-lee el
feed y corrige el score de 90' y/o el `advancing_team_id` cuando difieren, re-scoreando
(idempotente). Así solo se ejecuta cuando efectivamente hubo un partido — nada corre en un día
sin partidos — y converge apenas el feed se asienta (un ganador de penales reportado tarde, o un
score cambiado post-cierre: gol anulado, VAR, corrección tardía del feed).

Vive aparte del path live (decisión 2): un fallo de la reconciliación no afecta el sync ni el
scoring en vivo. El flag `manual_override` en `matches` (decisión 3) protege una corrección
manual verificada de ser pisada por el feed — `ReconcileFinishedMatch` saltea los partidos
marcados. Los `ranking_snapshots` ya capturados siguen sin recalcularse (queda como estaba).
Este mecanismo general **reemplaza** el reconcile específico de shootouts (`ShootoutReconcileJob`),
que resolvía solo el avance: el general cubre avance **y** score en un único camino.

## Contexto

El 21-jun, en producción, el partido España vs Arabia Saudita (Match id 37, external_id 537371) figuraba **5-0** en la penca cuando el resultado real fue **4-0**. Esto afectó el scoring de usuarios reales (predicciones de ese partido evaluadas contra el marcador equivocado).

Hechos confirmados (auditoría 21-jun):

- **El error vino del feed, no de nuestro sync.** `football-data.org` REPORTÓ 5-0 (y al día de hoy sigue reportando 5-0). `FootballData::SyncMatch` copió fielmente el dato. No hubo bug en el sync.
- **El guard de SCRUM-313 NO fue el culpable.** Ese guard (`guarded_status`) solo rechaza un payload entrante con status `scheduled` que pisaría un `live`/`finished` (la regresión del live-sync). Un payload `finished`→`finished` con score corregido NO se bloquea: `apply` setea `home_score`/`away_score` incondicionalmente. El guard nunca intervino acá.
- **Causa estructural — ningún path re-sincroniza un partido `finished`.** `DueMatchSyncQuery` (el poll de 60s) selecciona solo `live`, `started` y `scheduled` futuros stale; los `finished` quedan fuera para siempre ("Everything else … is left alone"). `SyncFixtures` incremental (cada 3h) solo refresca `kickoff_at`, nunca scores (ADR-0001). ⇒ si el feed corrige un marcador **después** del cierre, jamás lo volvemos a leer. El score queda congelado.
- Se auditaron los 37 partidos `finished`: éste fue el **único** discrepante.

Corrección manual aplicada en prod: `Match.update!(home_score: 4, away_score: 0)` + `Scoring::ComputeMatchScores.call(match:)` (idempotente) → puntos del usuario afectado 66 → 69. El leaderboard y las tablas de grupos se auto-corrigen (se calculan en vivo desde los scores; solo TTL de cache).

El problema de fondo: **football-data es nuestra fuente de verdad, pero puede equivocarse**, y hoy la única forma de corregir un score finalizado es intervención manual. Eso no escala ni es confiable para un torneo en vivo.

## Decisión

1. **Mecanismo de reconciliación de finished recientes, automático.** Un proceso de baja frecuencia re-lee del feed los partidos `finished` dentro de una ventana corta post-cierre, compara contra nuestro score, y ante una discrepancia aplica la corrección **y re-scorea** (`ComputeMatchScores`). Idempotente. El detalle (job nuevo dedicado vs. ventana de "recién finalizados" en el poll; tamaño de la ventana) se decide en el recon de **SCRUM-321**.

2. **No se toca el poll de 60s.** La reconciliación vive aparte del path live (`SyncMatch`/`SyncDueMatches`/`DueMatchSyncQuery`) — el área del incidente SCRUM-313 — para no reintroducir riesgo ahí. Un fallo de la reconciliación no debe afectar el sync ni el scoring en vivo.

3. **Protección de correcciones manuales contra overwrite del feed (`manual_override`).** Como el feed sigue diciendo 5-0, un re-sync/bootstrap futuro pisaría la corrección manual. Se evalúa (recon SCRUM-321) un flag `manual_override` en `matches`: cuando un score se corrige a mano, el sync/reconciliación **no** lo vuelve a pisar con el valor del feed. Esto reconcilia "el feed es la verdad" con "un humano verificó que el feed está mal acá".

4. **El feed es la fuente de verdad por defecto, pero falible.** El sistema asume el dato del feed salvo (a) que la reconciliación lo corrija contra una lectura más fresca del propio feed, o (b) que un override manual lo marque como verificado-distinto. La verdad del feed deja de ser incuestionable: hay un mecanismo de corrección que no depende de que alguien mire los rankings y note el error.

## Consecuencias

- Un score corregido por el feed post-cierre se propaga solo (sin intervención manual), con re-scoring idempotente.
- Las correcciones manuales sobreviven a re-syncs (vía `manual_override`), evitando el "parche frágil" del incidente actual.
- `ranking_snapshots` ya capturados con el score viejo **no** se recalculan automáticamente (historial de deltas today/week). En este incidente el impacto fue menor (3 pts); SCRUM-321 decide si se recalculan/borran los snapshots afectados.
- Reportar el error a football-data queda como acción operativa fuera del código.
- Costo: lecturas extra al feed (acotadas por la ventana + el rate limit de 10 req/min del free tier); por eso la ventana es **corta** y de baja frecuencia.

## Alternativas consideradas

1. **Solo corrección manual (status quo).** Rechazada: no escala, depende de que alguien note la discrepancia mirando rankings, y el parche es frágil (un bootstrap lo pisa).
2. **Re-`football_data:bootstrap` completo.** Rechazada como mecanismo recurrente: re-sincroniza todo (teams/players/104 partidos), corrige el score pero **no** re-scorea (no dispara `MatchScoringJob`), y pisaría correcciones manuales. Sirve solo como herramienta puntual, no como fix.
3. **Incluir los `finished` en el poll de 60s permanentemente.** Rechazada: agranda el área del incidente SCRUM-313 y gasta cuota de API en partidos que casi nunca cambian. La ventana corta post-cierre captura el 99% de las correcciones reales sin re-pollear finales de hace semanas.

## Pendiente

- Recon e implementación en **SCRUM-321** (approach, ventana, flag `manual_override`, decisión sobre snapshots).
