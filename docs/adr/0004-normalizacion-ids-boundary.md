# 4. Normalización de identidad (ids) en el boundary del API (frontend)

Fecha: 2026-06-06

## Estado
Aceptada.

## Contexto
El backend serializa los ids de usuario como number (PK integer; UserBlueprint `:id`),
pero `AuthUser.id` estaba tipado `string`. El tipo mentía. En SCRUM-145 esto causó un bug
silencioso: el match `entry.userId === currentUser.id` comparaba `"9" === 9` → siempre
`false`, así que el rank de cada penca privada caía a "—" en producción. El harness de
tests lo enmascaró usando ids string en los mocks; solo apareció con data real (numérica).

## Decisión
Normalizar los ids a string en el boundary (los mappers), no parchear downstream:
- `mapUser` (y `mapGroup`, `mapEntry`, etc.) hacen `String(id)`: el dominio expone ids
  string de forma consistente.
- Los tipos `*Response.id` reflejan la realidad del backend (`number`); los tipos de
  dominio exponen `string`.
- Cualquier comparación de ids usa la forma normalizada. No se siembran `String(x.id)`
  puntuales downstream — el boundary lo garantiza.

## Alternativas consideradas
- Parchear cada call-site con `String(...)` (lo que se hizo primero en `useGroupRank`).
  Rechazada: tapa un agujero puntual y deja la misma mina para el próximo consumidor.

## Consecuencias
- Comparaciones de ids consistentes en toda la app (highlight de rank, "tu fila", etc.).
- El tipo dice la verdad post-normalización.
- Regla a futuro: los bugs de tipo en el boundary son invisibles en screenshots y los
  enmascaran los mocks con tipos "lindos". Normalizar en el mapper y testear con data que
  imite la forma real del backend (ids numéricos).

## Relacionadas
- SCRUM-277 (fix en `mapUser`), SCRUM-145 (donde apareció el bug silencioso).
