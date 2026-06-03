# ADR-0001 — Ingesta de partidos de eliminación (knockout): crear al resolverse

- **Estado:** Aceptada
- **Fecha:** 2026-06-03
- **Ámbito:** backend (football-data sync)
- **Relacionada con:** SCRUM-272 (en main), SCRUM-243 (cerrada), SCRUM-139

## Contexto

Penca Mundial necesita mostrar y permitir pronosticar los partidos de eliminación directa (mata-mata) a medida que se van definiendo durante el torneo.

Hechos confirmados (recon, 2026-06-03):

- El feed de football-data (`GET /v4/competitions/WC/matches`) ya entrega las **104 fechas**, incluidas las **32 de eliminación**, con `utcDate` + `stage` + `status`, pero con `homeTeam`/`awayTeam` en **`null`** hasta que el bracket se resuelve. football-data calcula los cruces (incluida la asignación de mejores terceros) y va completando los equipos solo.
- Restricción del modelo: `matches.home_team_id` / `away_team_id` son **NOT NULL** + `belongs_to` requerido + check `home_team_id <> away_team_id`. Un partido **no puede persistirse sin ambos equipos**.
- Único creador de `Match`: `FootballData::SyncFixtures`, que hoy **saltea** los KO con equipos TBD y corre **sólo por rake manual** (`football_data:bootstrap`). No hay re-sync recurrente. → Hueco: los partidos de KO **no entran solos** a la DB durante el torneo.
- El scoring de avance **ya no depende** de poblar el bracket: `advancing_team_id` se setea desde `score.winner` en `SyncMatch`/`SyncFixtures` (SCRUM-272, en main).
- Las vistas degradan con gracia sin filas de KO (empty-state "se publicarán cuando se confirmen los cruces").

## Decisión

1. **No calculamos cruces ni modelamos el bracket nosotros.** football-data es la fuente de verdad de quién juega contra quién; sólo lo ingerimos.
2. **Ingesta "create-on-resolve".** Un **re-sync recurrente** crea cada partido de KO en cuanto el feed le pone **ambos** equipos. **No** almacenamos los cascarones con equipos "por definir"; **no** se tocan las FK del modelo (no se hacen nullable).
3. **El re-sync recurrente va acotado.** Crea partidos nuevos; para los que **ya existen NO pisa** `status` / `home_score` / `away_score` / `advancing_team_id` / `minute` / `events_log` — eso es dominio exclusivo del poller por-partido (`SyncMatch`), para no romper el disparador `newly_finished` del scoring.
4. **Se descarta SCRUM-243 (`Matches::PropagateWinner`)** por redundante: el feed completa los equipos de la próxima ronda; nosotros sólo los ingerimos. Además, 243 habría requerido poblar `feeds_into` (otro hueco), y el scoring de avance ya no la necesita (272).

## Consecuencias

- El cuadro y la pestaña Eliminación se **llenan ronda a ronda** (octavos al terminar dieciseisavos, cuartos al terminar octavos, etc.). Durante la fase de grupos las vistas muestran el empty-state; **no** se muestra el esqueleto vacío del cuadro desde el día 1.
- El **producto funcional es idéntico** al de "almacenar todo desde el día 1": se puede pronosticar cada ronda apenas se definen los equipos.
- Se **evita** la migración (FK nullable) y el manejo de "por definir" en serializers / pronósticos / vistas → menor superficie de cambio y de riesgo a días del lanzamiento. El **scoring queda intacto** (sólo corre sobre partidos `finished`, que para entonces ya tienen equipos).
- **Dependencia explícita:** confiamos en que football-data complete los equipos de KO en el feed — el mismo supuesto sobre el que ya se construyó la vista del cuadro (SCRUM-247). El re-sync recurrente ingiere lo que el feed provea, **sin intervención manual** durante el torneo.

## Alternativas consideradas

1. **Almacenar el cuadro completo desde el día 1** (FK de equipo nullable o equipo sentinel "TBD"). *Rechazada:* el único beneficio sobre create-on-resolve es mostrar un esqueleto **no interactivo** durante los grupos; cuesta una migración + manejo de `null` en varias capas, a días del lanzamiento. Lo que se pronostica es lo mismo.
2. **Calcular los cruces nosotros** desde las posiciones de grupo. *Rechazada:* enorme, específico del Mundial 2026 (tabla de mejores terceros), frágil, y contra la regla multi-torneo. El proveedor ya lo hace.
3. **SCRUM-243 `PropagateWinner`** (propagar el ganador al siguiente slot vía `feeds_into`). *Rechazada / cerrada:* redundante con la ingesta del feed; el scoring de avance ya no la necesita (272).

## Decisiones relacionadas (mismo cluster de datos KO / torneo)

- **SCRUM-272** (en main): `home_score`/`away_score` = resultado de los 90' (`regularTime || fullTime`); `advancing_team_id` desde `score.winner`.
- **SCRUM-139** (próximo): resultados reales del torneo — podio derivado de los partidos `final` + `third_place`; goleador desde el endpoint de *scorers* de football-data.