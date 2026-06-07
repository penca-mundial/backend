# 3. Invite-link y preservación de returnTo a través de autenticación

Fecha: 2026-06-06

## Estado
Aceptada.

## Contexto
Las pencas privadas se comparten con un código de invitación. El link
(`/app/groups/join?code=X`) apunta a una ruta detrás de `ProtectedRoute`, así que un
invitado deslogueado/no-registrado primero pasa por login/registro. Antes de SCRUM-283,
`ProtectedRoute` hacía `<Navigate to="/login" replace />` pelado: el destino se perdía y
el invitado caía en `/app/home`, no en la penca → el loop de invitación (núcleo del
producto) estaba roto para usuarios nuevos.

Además, "Compartir código" decidía share-vs-copy por la existencia de `navigator.share`.
Safari de desktop SÍ lo expone, así que en desktop abría el share sheet nativo de macOS
en vez de copiar — inesperado para una web en desktop.

## Decisión
1. Preservar el destino (`returnTo`) a través de auth, front-only:
   - `ProtectedRoute` redirige a `/login?returnTo=<pathname+search>`.
   - `returnTo.ts`: `isSafeReturnTo` (solo paths internos `/app/...`, anti open-redirect),
     lectura del query y stash/restore en `sessionStorage` (per-tab/origin).
   - Google OAuth (front→back→Google→back→front, misma pestaña): stash del `returnTo` en
     `sessionStorage` antes del POST, restore en el callback. NO requiere backend ni el
     `state` del OAuth.
   - El `returnTo` sobrevive el onboarding (elección de username del usuario nuevo de
     Google): el callback no lo consume si falta username; lo consume `ChooseUsernameForm`
     al terminar.
   - `PublicOnlyRoute` honra `?returnTo=` (arregla la carrera del refetch de sesión que
     mandaba a `/app/home`). Los links login↔signup propagan el `returnTo`.
2. "Compartir" decide por tipo de dispositivo, no por `navigator.share`:
   - Touch / `(pointer: coarse)`: `navigator.share` con el link (sheet nativo → WhatsApp/
     Telegram).
   - Desktop (pointer fino): SIEMPRE copia el LINK de invitación + toast, aunque
     `navigator.share` exista.

## Alternativas consideradas
- Llevar el `returnTo` por el `state` del OAuth (tocando backend). Rechazada para MVP: el
  callback vuelve al mismo origin/pestaña, así que `sessionStorage` alcanza sin acoplar
  backend.

## Consecuencias
- El loop de invitación funciona end-to-end para login y Google OAuth: el invitado cae en
  `/app/groups/join?code=X` con el código prefilled y se une. Sin cambios de backend.
- Gap conocido: el signup por email pierde el `returnTo` en la confirmación por mail (otra
  pestaña/sesión). Cubrirlo requiere que el redirect de confirmación del backend lleve el
  `returnTo` — diferido (Google + login cubren el grueso).

## Relacionadas
- SCRUM-283 (invite-link + returnTo), SCRUM-147 (JoinGroupPage / `?code=` autofill),
  SCRUM-148 (header "Compartir código").
