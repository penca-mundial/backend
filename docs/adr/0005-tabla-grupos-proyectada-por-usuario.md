# 5. Tabla de grupos proyectada por usuario (blend pronósticos + oficial)

Fecha: 2026-06-07

## Estado

Aceptada.

## Contexto

Las tablas de grupos oficiales se calculan desde nuestros propios partidos
(`GroupStandingsQuery`, ADR 0002): composición desde `Match#group`, estadísticas
solo de partidos `finished`. Pre-torneo (y durante la fase de grupos) eso deja
las tablas mayormente en cero, mientras que cada usuario ya cargó pronósticos
para esos mismos partidos. Queremos mostrarle a cada usuario "cómo quedaría la
tabla si sus pronósticos se cumplen": una vista personal, complementaria a la
oficial, que el frontend pueda alternar.

## Decisión

### 1. Endpoint aditivo, autenticado, mismo shape

`GET /api/v1/tournaments/:id/standings/projected` (autenticado — la proyección
es personal por definición). El endpoint oficial
`GET /api/v1/tournaments/:id/standings` queda **intacto** (público, cache 30s).
La respuesta proyectada reusa `GroupStandingBlueprint`: mismo shape
`[{ name, standings: [{ team, played, won, drawn, lost, goals_for,
goals_against, goal_difference, points, position }] }]`, así el frontend puede
alternar oficial/proyectada sin mapper nuevo.

Sin cache: el body es por usuario (el TTL compartido del oficial no aplica) y
el costo es de dos queries (partidos con teams precargados + las predicciones
del usuario en un solo `WHERE match_id IN`).

### 2. El blend, por partido del grupo

`ProjectedGroupStandingsQuery < GroupStandingsQuery` (hereda la matemática, el
preload N+1-free y el ranking; multi-torneo y genérico en grupos/equipos igual
que el padre):

- `finished` → resultado oficial (cuenta TODO: PJ/G/E/P, GF/GC/DG, Pts).
- No `finished` y el usuario lo pronosticó → su pronóstico
  (`predicted_home_score`/`predicted_away_score`) cuenta **solo** para
  GF/GC/DG/Pts.
- No `finished` y sin pronóstico → **excluido** (no aporta nada).

Orden/posición: mismo criterio que ADR 0002 — Pts desc, DG desc, GF desc —
aplicado sobre los valores blended.

### 3. Híbrido PJ-vs-Pts deliberado

PJ/G/E/P reflejan SOLO partidos oficiales jugados; Pts/GF/GC/DG incluyen
pronósticos. Es intencional, no un bug:

- Pre-torneo: tabla con PJ=0 para todos pero posiciones/puntos completamente
  proyectados — el usuario ve su "tabla final imaginada".
- La columna PJ le dice cuánto de la proyección ya es real: PJ=0 → 100%
  pronóstico; PJ=3 (fase completa) → tabla 100% oficial.
- Convergencia automática: cuando un partido pasa a `finished`, el resultado
  oficial reemplaza al pronóstico en el blend (el pronóstico de un partido
  jugado deja de usarse). Sin estados intermedios que migrar.

La alternativa de proyectar también PJ/G/E/P (sumar el partido pronosticado
como "jugado") se descartó: miente sobre hechos (un partido no jugado no está
jugado) y rompe la lectura "cuánto de esto ya pasó".

### 4. Casos borde

- Partido `live`: no es `finished` → cuenta el pronóstico del usuario (si
  existe) hasta que el partido termine. Es la semántica más simple y la tabla
  se corrige sola al final del partido.
- `postponed`/`cancelled`: ídem — no `finished`, cuenta el pronóstico si
  existe. Aceptado como simplificación (un cancelado definitivo nunca
  converge, pero tampoco lo hace la tabla oficial con ese partido).
- Pronósticos de otros usuarios: invisibles — el query filtra por
  `user_id` + el índice único `(user_id, match_id)` garantiza a lo sumo un
  pronóstico por partido.

## Consecuencias

- El frontend puede ofrecer el toggle "tabla real / mi proyección" sin mapper
  nuevo ni endpoint extra de predicciones.
- `GroupStandingsQuery` ganó una memoización (`matches_by_group`) sin cambio de
  comportamiento; la subclase reusa composición, preload, tally y ranking — un
  solo lugar donde vive la aritmética de standings.
- Tests (lección ADR 0004): specs con data realista — registros reales de
  factories con ids numéricos — cubren blend mixto, híbrido pre-torneo,
  exclusión de partidos sin pronóstico y aislamiento por usuario.

## Relacionadas

- ADR 0002 (standings calculados, SCRUM-244) — la base que esta vista extiende.
- ADR 0004 (ids realistas en tests).
- SCRUM-292 (este ticket).
