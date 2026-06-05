# 2. Standings de fase de grupos calculados desde los partidos

Fecha: 2026-06-04

## Estado

Aceptada.

## Contexto

La pestaña "Grupos" del fixture mostraba un estado vacío ("Próximamente") en lugar de las tablas de posiciones de la fase de grupos. La investigación reveló **dos problemas distintos**, uno síntoma del otro:

1. **El frontend consumía el endpoint equivocado.** El tab Grupos (SCRUM-246) lee `GET /api/v1/standings?tournament_id=` (SCRUM-262), que devuelve filas `Standing` **espejadas** desde el endpoint `/standings` de football-data.org. Ese endpoint está **vacío pre-torneo** (sin partidos jugados, el proveedor no publica tablas), y el job que lo sincroniza sólo corre para torneos "activos" (el Mundial no lo es hasta el 11-jun) y sólo en producción. Resultado: `Standing.count == 0` → `{ "groups": {} }` → tab vacío.

2. **Torneos duplicados (bug de fondo, SCRUM-274).** `SyncFixtures` pisaba el `name` del torneo con el de la API y no lo reconciliaba por código; un `db:seed` posterior, que buscaba por `name`, no lo encontraba y creaba un segundo torneo. Quedaban dos filas: una con los datos reales (equipos/partidos/jugadores) y `external_code = nil`, y otra con `external_code = "WC"` vacía. Esto rompía el sync de standings de punta a punta: el torneo con datos quedaba excluido del scope `active.where.not(external_code: nil)`, y `CurrentTournamentQuery` devolvía el sin-código.

Además se confirmó que **SCRUM-244 figuraba "Done" pero nunca se había implementado**: el endpoint calculado no existía en el código; sólo existía el camino espejado de 262.

El requerimiento de fondo: las tablas de grupos tienen que ser **sólidas antes del lanzamiento y no depender de un feed externo que puede no entregar**. football-data.org no publica las tablas del Mundial pre-torneo (y no está verificado que las publique siquiera durante), así que atar un feature central a eso es un riesgo que no queremos correr.

## Decisión

### 1. Las tablas de grupos se CALCULAN desde nuestros partidos, no se espejan del feed

Tenemos todo lo necesario en datos propios:

- **Composición** de cada grupo (qué equipos en A..L): sale de `Match#group`, que `SyncFixtures` puebla desde el endpoint de **partidos** —la dependencia central y confiable de toda la app—. Está disponible desde el bootstrap, antes de que se juegue nada.
- **Estadísticas** (PJ/G/E/P/GF/GC/DG/Pts): son pura aritmética sobre los **resultados** de esos mismos partidos de grupo terminados, que sincroniza el poller.

Ambas salen de los **partidos**. El endpoint `/standings` del proveedor sólo agregaría el orden con desempates oficiales — que para MVP no hace falta, porque el avance real lo define el bracket (el feed llena los equipos de la ronda siguiente), no esta tabla.

Implementado en SCRUM-244:

- `GroupStandingsQuery(tournament:)` → por grupo, calcula la tabla desde los `Match` finished de `group_stage`. Grupo sin jugar → sus equipos en 0 (la composición existe igual). Orden: Pts desc, DG desc, GF desc (FIFA simplificado, suficiente para MVP). N+1-free (preload de teams).
- `GET /api/v1/tournaments/:id/standings` → controller thin + `GroupStandingBlueprint`. Response: `[{ name, standings: [{ team, played, won, drawn, lost, goals_for, goals_against, goal_difference, points, position }] }]`.
- **Cache de TTL corto (30s)** para deduplicar el polling del front, en vez de invalidación explícita: los standings cambian sólo cuando termina un partido y 30s de staleness es irrelevante; así no se acopla un hook a `SyncMatch`.
- **Público** (sin auth), igual que el resto de los reads (`matches`, `teams`, `players`, `tournaments`, `standings`).

**Composición fija, tabla viva:** la composición no se "congela" en el bootstrap; la tabla se deriva de los partidos en cada lectura (cacheada 30s). Pre-torneo muestra los 12 grupos con sus equipos en 0; durante el torneo, las stats en vivo.

### 2. El endpoint espejado (262) y el modelo `Standing` quedan como están — opcionales

No se borran ni se tocan. Quedan disponibles como enriquecimiento futuro (p. ej. preferir el orden con desempates oficiales del proveedor cuando esté presente). El frontend se re-apunta del endpoint espejado (262) al calculado (244) en un ticket de frontend aparte.

### 3. Identidad del torneo por `external_code` (SCRUM-274)

El `Tournament` se reconcilia **siempre por `external_code`** (el código de competición, "WC"), nunca por `name` — espejando el patrón de teams-by-code3 (SCRUM-256):

- El `name` curado ("FIFA World Cup 2026") lo posee `db:seed`; `SyncFixtures` nunca lo pisa (sólo lo usa como fallback al crear una fila nueva).
- `db:seed` y el bootstrap convergen en una sola fila en **cualquier orden** de ejecución.
- Índice único **parcial** sobre `tournaments.external_code` (`WHERE external_code IS NOT NULL`) + validación de unicidad: el invariante "un torneo por código" vive en el schema, no sólo en la convención.

## Consecuencias

- Las tablas de grupos **no dependen** del endpoint `/standings` del proveedor ni de que el torneo esté "activo". Funcionan desde el bootstrap (grupos en 0) y se actualizan solas con el poller.
- Lo único que se "pierde" frente al feed es el desempate oficial exacto en empates raros — cosmético, porque la clasificación real la define el bracket.
- Ante una caída transitoria del proveedor, la tabla se degrada y se recupera sola (el poller es idempotente y se pone al día); no se pierde data.
- Un **segundo proveedor de datos NO es necesario pre-lanzamiento**: el riesgo más agudo (standings) se elimina calculando localmente. Un fallback real es un mini-proyecto (capa de normalización + matching de entidades cross-proveedor, que es frágil porque no hay ids universales de partido/jugador) y queda como hardening post-lanzamiento, manteniendo limpio el límite del `Client`.
- `SCRUM-244` se reabrió e implementó de verdad. `SCRUM-262` / `Standing` quedan vivos pero sin consumidores hasta nuevo aviso.

## Pendiente

- Re-apuntar el frontend (tab Grupos) de `GET /api/v1/standings` (262) a `GET /api/v1/tournaments/:id/standings` (244). Ticket de frontend aparte; el shape de respuesta es `[{ name, standings[] }]`.

## Relacionadas

- ADR 0001 — Ingesta de partidos de knockout.
- SCRUM-274 (identidad de torneo por external_code), SCRUM-256 (teams-by-code3), SCRUM-244 (endpoint calculado), SCRUM-262 (endpoint espejado), SCRUM-246 (tab Grupos).