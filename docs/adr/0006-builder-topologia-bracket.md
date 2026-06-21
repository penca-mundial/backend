# ADR-0006 — Builder de topología del bracket (dibujo, no fuente de verdad)

- **Estado:** Aceptada
- **Fecha:** 2026-06-21
- **Ámbito:** backend (bracket / presentación)
- **Relacionada con:** SCRUM-318, SCRUM-316 (exponer), SCRUM-317 (dibujar), ADR-0001 (ingesta KO), SCRUM-243 (cerrada)

## Contexto

El cuadro de eliminatorias necesita dibujarse como un árbol: cada cruce conectado
a su ronda siguiente, con orden vertical estable. Eso requiere tres datos que
están en el schema de `matches` pero que **nadie poblaba**: `feeds_into_match_id`,
`feeds_into_slot` y `bracket_position`.

ADR-0001 decidió **no modelar el bracket nosotros** (football-data es la verdad de
quién juega contra quién) y, en ese marco, **descartó SCRUM-243** (`PropagateWinner`)
porque habría requerido poblar `feeds_into` y el scoring de avance no lo
necesitaba. El alta de esa necesidad ahora es **distinta**: no es para scoring ni
para decidir cruces, es para **dibujar**. football-data sigue sin entregar la
topología del árbol (feed plano, sin "qué partido alimenta a cuál", sin número de
partido FIFA — recon SCRUM-316/318).

## Decisión

Se agrega `Brackets::BuildTopology`: un builder que **deriva** la topología de
datos que ya tenemos, sin calcular cruces.

1. **Edges (`feeds_into_match_id` / `feeds_into_slot`) desde `advancing_team_id`.**
   Cuando un partido de ronda N+1 nombra al equipo T, el partido de ronda N cuyo
   `advancing_team_id == T` alimenta ese slot (home/away según el lado de T).
   Determinístico, multi-torneo, **sin tabla FIFA de cruces, sin Annex C, sin
   posiciones de grupo**. football-data ya resolvió quién juega; nosotros solo
   cableamos el árbol con eso. **No contradice ADR-0001:** seguimos sin modelar
   los cruces.

2. **`bracket_position` (orden vertical).** La primera ronda KO se ancla a un
   **orden canónico curado mínimo** (`Brackets::OrderTable`, YAML por
   `external_code` en `db/seeds/data/brackets/<code>.yml`) usando las posiciones
   de grupo de los equipos de cada partido; el lado "vs mejor tercero" es
   `{ position: 3 }` sin grupo (la identidad del tercero es Annex C y **no afecta
   el orden**, así que no modelamos los 495 escenarios). El `order` del YAML es el
   orden del **árbol** (los dos R32 que alimentan el mismo R16 van adyacentes), no
   el número de partido. Las rondas siguientes derivan su posición del grafo
   `feeds_into` ya armado (`hijo = padre_home / 2`).

3. **Reconciliación visible contra el feed.** Si las posiciones de grupo computadas
   localmente (FIFA simplificado, ADR-0002) no encajan en ningún slot, o dos
   partidos reclaman el mismo, se emite `log_warn` y el partido **no se ancla** —
   nunca se mal-ancla en silencio (lección SCRUM-313). El feed sigue siendo la
   verdad; el builder valida contra él, no lo reemplaza.

4. **El builder es presentación/dibujo, NO fuente de verdad.** No decide quién
   avanza (eso es `advancing_team_id` desde `score.winner`, SCRUM-272), no crea
   partidos (eso es create-on-resolve, ADR-0001), no afecta scoring ni standings.
   Solo cablea el árbol para que el front lo dibuje.

5. **Disparo desacoplado del path sensible.** Corre en `BracketBuildJob`, encolado
   por `FixtureResyncJob` (cada 3h) **después** del sync incremental y **solo si
   `matches_created > 0`**. No toca el poll de 60s (`MatchSyncJob` /
   `SyncDueMatches` / `SyncMatch` — área del incidente SCRUM-313). Como los KO se
   crean con ambos equipos ya resueltos, todo el cableado posible se hace al
   crearse el partido siguiente, así que no hace falta enganchar al loop en vivo.
   Un fallo del builder vive en su propio job: no aborta ni afecta el sync. El
   builder es idempotente (`update-if-changed`; `feeds_into` solo se setea, nunca
   se pisa con una conjetura peor), así que re-correr es seguro.

## Consecuencias

- El front puede dibujar el árbol data-driven (SCRUM-316 expone los campos,
  SCRUM-317 dibuja) sin reimplementar la lógica del bracket en el cliente.
- Se reabre lo que SCRUM-243 dejó fuera (`feeds_into`), pero por una razón nueva
  (dibujo) y por un camino que respeta ADR-0001 (no calculamos cruces).
- La tabla de orden es **data curada por torneo** (multi-torneo, nada hardcodeado
  en la lógica). `db/seeds/data/brackets/wc.yml` es el bracket oficial 2026.
- Limitación menor: si una posición de grupo cambia después de crear los R32 sin
  que se cree ningún partido nuevo, el re-anclaje espera al próximo
  `matches_created > 0`; la reconciliación lo haría visible. Aceptable para una
  capa de dibujo.
- Hay un seed de preview (`db/seeds/brackets_demo.rb`, `bracket:demo`) y un rake
  manual (`bracket:build`) además del disparo automático.

## Alternativas consideradas

1. **Calcular los cruces desde posiciones de grupo (tabla FIFA completa + Annex C
   495).** Rechazada (y ya rechazada en ADR-0001): enorme, específica de WC2026,
   frágil en empates. El feed ya asigna los equipos; solo necesitamos el orden.
2. **Enganchar el builder al poll de 60s (`SyncMatch`/`SyncDueMatches`).**
   Rechazada: es el área del incidente SCRUM-313 y es innecesario — el cableado
   se completa al crearse el partido siguiente (FixtureResync), no al finalizar el
   anterior.
3. **Correr el builder en cada tick por ser idempotente.** Rechazada: el builder
   consulta standings + todos los KO; gatear por `matches_created > 0` evita el
   desperdicio sin perder correctitud.
