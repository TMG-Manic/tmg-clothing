# tmg-clothing

> Character appearance editor, clothing/barber/surgeon shops, job and gang wardrobes, and the personal outfit system.

## Overview

`tmg-clothing` owns everything about how a character *looks*. It holds the authoritative in-memory
appearance table (`skinData`), applies it to the ped, persists it as the player's active skin, and
exposes an NUI editor that can be opened with different tab sets depending on what the player walked
up to — a barber gets only the hair tab, a plastic surgeon only the face tab, a clothing store the
clothing and accessory tabs, and a job wardrobe the room's preset outfits alongside the player's own.

The lifecycle is: on `TMGCore:Client:OnPlayerLoaded` the client fires `tmg-clothes:loadPlayerSkin`;
the server looks up the player's `playerskins` document and either sends the saved model + JSON skin
back via `tmg-clothes:loadSkin`, or sends the "first character" flag when nothing exists. The client
streams the model, then hands the decoded table to `tmg-clothing:client:loadPlayerClothing`, which
clears all components/props and re-applies every slot before replacing `skinData` wholesale.

Editing works entirely on the live ped. Opening the menu snapshots `skinData` as a JSON string in
`previousSkinData`, freezes the ped, and spins up a scripted preview camera. Every arrow click,
slider drag or typed value posts `updateSkin`/`updateSkinOnInput`, which routes through
`ChangeVariation()` — one big dispatch on `clothingType` that calls the right native and records the
new value back into `skinData`. Nothing is written to the database until the player presses Confirm
(`saveClothing` → `SaveSkin` → `tmg-clothing:saveSkin`). Pressing Cancel posts `resetOutfit`, which
re-applies the snapshot and discards the edits.

Outfits are a separate, additive layer. `tmg-clothing:client:loadOutfit` applies only the slots
present in the outfit table, so face and hair survive an outfit change. Saved outfits live in
`player_outfits`, one document per outfit, each minted with a generated `outfitId` on save. Job and
gang wardrobe presets are not stored in the database at all — they are read straight out of
`Config.Outfits` keyed by job → gender → grade level.

Interaction points are built by `loadStores()` after the player loads. With `Config.UseTarget` it
registers `tmg-target` box zones; otherwise it builds PolyZone `ComboZone`s plus a polling thread
that watches for `[E]` while inside one.

## Dependencies

| Resource | Required | Used for |
| :--- | :--- | :--- |
| `tmg-core` | Yes | `GetCoreObject`, `GetPlayerData`, `TriggerCallback`/`CreateCallback`, `Notify`, `DrawText`/`HideText`, `Shared.SplitStr`, `Shared.TMGJobsStatus`, `Lang`/`Locale` |
| `tmgnosql` | Yes | `playerskins` and `player_outfits` persistence |
| `PolyZone` | Yes | `@PolyZone/client.lua`, `BoxZone.lua`, `ComboZone.lua` are loaded in `client_scripts` unconditionally |
| `tmg-target` | Conditional | `AddBoxZone` — only called when `Config.UseTarget` is true |

`fxmanifest.lua` declares `dependency 'tmg-core'` only. PolyZone is a hard load-time dependency via
`@`-prefixed scripts; `tmg-target` is a soft runtime one but is **not** guarded by a
`GetResourceState` check — if `Config.UseTarget` is true and `tmg-target` is not started, the zone
registration loop errors.

### Resources that drive this one

| Resource | How |
| :--- | :--- |
| `tmg-multicharacter` | `tmg-clothing:client:loadPlayerClothing` to dress the character-select ped |
| `tmg-interior` | `tmg-clothes:client:CreateFirstCharacter` for new characters |
| `tmg-apartments`, `tmg-houses`, `tmg-management` | `tmg-clothing:client:openOutfitMenu` for in-property wardrobes |
| `tmg-policejob` (tracker), `tmg-prison`, `tmg-smallresources` (parachute) | `tmg-clothing:client:loadOutfit` to force a uniform/prop set |
| `tmg-adminmenu` | `tmg-clothing:client:openMenu` on a target player |

## Configuration

| Key | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `Config.UseTarget` | `boolean` | `GetConvar('UseTarget', 'false') == 'true'` | Switches all interaction zones between `tmg-target` box zones and PolyZone + `[E]` prompts. |
| `Config.WomanPlayerModels` | `string[]` | ~140 models | Ped models offered when `charinfo.gender == 1`. Index 1 is `mp_f_freemode_01`. |
| `Config.ManPlayerModels` | `string[]` | ~355 models | Ped models offered when `charinfo.gender == 0`. Index 1 is `mp_m_freemode_01`. |
| `Config.LoadedManModels` | `table` | `{}` | Declared and never read or written. |
| `Config.LoadedWomanModels` | `table` | `{}` | Declared and never read or written. |
| `Config.Stores` | `table` | 22 entries | `{ shopType, coords, width, length }`. `shopType` is `'clothing'` (15), `'barber'` (7) or `'surgeon'` (0 configured, but supported). Drives both the blips and the zones. |
| `Config.OutfitChangers` | `table` | 15 entries | `{ shopType = 'outfit', coords, width, length }`. Opens the personal-outfits-only menu. No blips. |
| `Config.ClothingRooms` | `table` | 7 entries | `{ requiredJob, isGang, coords, width, length, cameraLocation }`. `cameraLocation` is a `vector4` (heading in `w`) used to override the preview camera. |
| `Config.Outfits` | `table` | keyed by job | `Config.Outfits[job][gender][gradeLevel]` → list of `{ outfitLabel, outfitData }`. `gender` is the string `'male'`/`'female'`; `gradeLevel` is numeric. |

`width`, `length`, `minZ` and `maxZ` describe the zone box. `minZ`/`maxZ` are derived from
`coords.z ± 1` (stores, outfit changers) or `± 2` (clothing rooms) in code, not read from config.

`Config.Menus` is referenced by the `getCatergoryItems` NUI callback but **is not defined anywhere**
— see *Known limitations*.

## Exports

### Client

```lua
exports['tmg-clothing']:reloadSkin(health)
```
| Param | Type | Description |
| :--- | :--- | :--- |
| `health` | `number` | Health value to restore after the ped is rebuilt |

Rebuilds the ped from `charinfo.gender` (1 = female), re-requests the saved skin from the server,
restores max health, then sets `health`. Takes roughly two seconds due to two hard-coded settle waits.
**Returns:** nothing.

```lua
exports['tmg-clothing']:IsCreatingCharacter()
```
**Returns:** `boolean` — true while the appearance menu is open. Set true in `openMenu`, cleared in
the `close` NUI callback.

```lua
exports['tmg-clothing']:getOutfits(gradeLevel, data)
```
| Param | Type | Description |
| :--- | :--- | :--- |
| `gradeLevel` | `number` | The player's job or gang grade level |
| `data` | `table` | A `Config.Outfits[job]` entry — indexed internally as `data[gender][gradeLevel]` |

Opens the wardrobe menu with four tabs: room presets, the player's own outfits (fetched via the
`tmg-clothing:server:getOutfits` callback), clothing, and accessories. **Returns:** nothing.

## Events

### Server events (client → server)

#### `tmg-clothing:saveSkin`
**Params:** `(model, skin)` — `model` is the ped model hash, `skin` is the client's
`json.encode(skinData)` string.
**Validation:** the caller must be a loaded player and both arguments must be non-nil. The skin
contents are **not** validated, parsed or bounded server-side; whatever the client sends is stored
verbatim. Upserts into `playerskins` on `citizenid` with `active = 1`.

#### `tmg-clothes:loadPlayerSkin`
**Params:** none. Fetches the caller's `playerskins` document where `active == 1` and replies with
`tmg-clothes:loadSkin`. If no document exists it replies with the first-character flag set.

#### `tmg-clothes:saveOutfit`
**Params:** `(outfitName, model, skinData)`.
**Validation:** the caller must be a loaded player and `model`/`skinData` must be non-nil.
`outfitName` is **not** length-limited or sanitised, and there is no cap on how many outfits one
citizen may create. Mints `outfitId` as `string.format("outfit-%d-%d", math.random(1,10),
math.random(1111,9999))`, inserts the document, then pushes the refreshed list back via
`tmg-clothing:client:reloadOutfits`.

#### `tmg-clothing:server:removeOutfit`
**Params:** `(outfitName, outfitId)`. Deletes on `{ citizenid, outfitId }`, so a player can only
delete their own outfits. `outfitName` is accepted but unused in the query.

### Client events (server → client, or local)

#### `tmg-clothes:loadSkin`
**Params:** `(_, model, data)`. The leading first-character flag is ignored. If `model` is absent the
client falls back to the gender-appropriate freemode model. Streams the model, applies it, then hands
the decoded `data` to `loadPlayerClothing` — but only if the server actually sent a skin.

#### `tmg-clothing:client:loadPlayerClothing`
**Params:** `(data, ped)`. `ped` defaults to the local ped, which is how `tmg-multicharacter` dresses
its preview peds. Clears components 0–11 and props 0–7, then applies face blend, every clothing
component, all overlays, props, eye colour, moles and all 20 face features. Finally replaces
`skinData` with `data`.

#### `tmg-clothing:client:loadOutfit`
**Params:** `(oData)` where `oData.outfitData` is either a table or a JSON string, plus an optional
`oData.outfitName` used for the confirmation notification. Only writes the slots present in the
outfit, so face/hair are preserved. If `metadata.tracker` is set, component 7 is forced to drawable
13 (the ankle monitor) regardless of what the outfit says. **Applies to the ped only — nothing is
persisted until the player confirms in the menu.**

#### `tmg-clothing:client:openMenu`
Opens the full editor (features / hair / clothing / accessories) with the default camera.

#### `tmg-clothing:client:openOutfitMenu`
Opens a single-tab menu showing only the player's own saved outfits.

#### `tmg-clothes:client:CreateFirstCharacter`
Opens the full editor, applies the gender-matched freemode model via `ChangeToSkinNoUpdate`, and
tells the NUI to reset every slider to its default.

#### `tmg-clothing:client:reloadOutfits`
**Params:** `(myOutfits)`. Forwards the refreshed outfit list to the NUI as `reloadMyOutfits`.

#### `tmg-clothing:client:adjustfacewear`
**Params:** `(type)` — `1` hat, `2` glasses, `3` earpiece, `4` mask, `5` backpack. Plays an
appropriate anim and toggles the item off/on, stashing the removed prop or component in the
module-level `faceProps` table so the next call can restore it. No-op while `metadata.ishandcuffed`.
Nothing inside this resource triggers it.

#### Framework events
`TMGCore:Client:OnPlayerLoaded` (load skin, cache `PlayerData`, build zones),
`TMGCore:Client:OnJobUpdate`, `TMGCore:Client:OnGangUpdate`, `TMGCore:Client:UpdateObject`.

### Events this resource fires for others

| Event | When |
| :--- | :--- |
| `tmg-clothing:client:onMenuClose` | Fired locally from the `close` NUI callback, after focus is released and the camera torn down |

## Callbacks

### `tmg-clothing:server:getOutfits`
```lua
TMGCore.Functions.TriggerCallback('tmg-clothing:server:getOutfits', function(outfits) end)
```
Returns every `player_outfits` document for the caller's `citizenid`, or `{}` if the player is not
loaded or has none.

## Commands

| Command | Args | Permission | Description |
| :--- | :--- | :--- | :--- |
| `/refreshskin` | — | none | Client command. Rebuilds the ped from the saved skin, preserving current health. Useful after a model desync. |

## Data model

### `playerskins`

One document per character. Upserted on `{ citizenid }` by `tmg-clothing:saveSkin`.

```jsonc
{
  "citizenid": "ABC12345",   // owner
  "model": 1885233650,        // ped model hash (GetEntityModel result, sent as a number)
  "skin": "{\"face\":{...}}", // JSON *string* of the full skinData table
  "active": 1                 // always 1; the load query filters on active == 1
}
```

`skin` is stored as an encoded string, not a nested document, so it is opaque to queries.

### `player_outfits`

One document per saved outfit. Inserted (never updated) by `tmg-clothes:saveOutfit`.

```jsonc
{
  "citizenid": "ABC12345",       // owner
  "outfitname": "Work Clothes",  // player-supplied label, lowercase field name
  "model": 1885233650,           // ped model hash at save time
  "skin": { /* skinData table */ }, // stored as a nested document, not a string
  "outfitId": "outfit-7-4821"    // generated; the key used for deletion
}
```

**`outfitId` is the lookup key, not Mongo's `_id`.** It is minted as
`outfit-<1..10>-<1111..9999>`, giving roughly 80,000 possible values — collisions between two
players' outfits are possible but harmless because deletion always filters on `citizenid` as well.
Every save mints a fresh id, so re-saving the same outfit name creates a duplicate document rather
than replacing the original.

Note the field-name asymmetry between the two collections: `playerskins.skin` is a string,
`player_outfits.skin` is a document. The NUI passes `outfitData.skin` straight into `selectOutfit`,
and `loadOutfit` handles both shapes by `json.decode`-ing anything that is not a table.

No `EnsureIndex` calls are made by this resource.

## Appearance data model

### `skinData`

The single source of truth on the client. Each slot is one of two shapes:

```lua
["torso2"]  = { item = 0, texture = 0, defaultItem = 0, defaultTexture = 0 }
["facemix"] = { skinMix = 0, shapeMix = 0, defaultSkinMix = 0.0, defaultShapeMix = 0.0 }
```

`defaultItem`/`defaultTexture` are the values restored by `ChangeToSkinNoUpdate` on a model swap and
by the NUI's `ResetValues`; they also act as the **minimum** the NUI arrows/sliders will decrement to.
Slots that default to `-1` (`eyebrows`, `beard`, `blush`, `lipstick`, `makeup`, `ageing`, `hat`,
`ear`, `watch`, `bracelet`, `eye_color`, `moles`) can therefore be cleared; slots that default to `0`
cannot go below `0`.

### `clothingCategories`

Maps every slot to the native family that drives it and the component/overlay/prop index to pass.

| `type` | Slots | Index meaning |
| :--- | :--- | :--- |
| `variation` | `arms` 3, `t-shirt` 8, `torso2` 11, `pants` 4, `vest` 9, `shoes` 6, `bag` 5, `accessory` 7, `decals` 10 | ped component id (`SetPedComponentVariation`) |
| `mask` | `mask` 1 | ped component id |
| `hair` | `hair` 2 | ped component id; texture drives `SetPedHairColor` |
| `overlay` | `eyebrows` 2, `beard` 1, `blush` 5, `lipstick` 8, `makeup` 4 | head overlay id (`SetPedHeadOverlay` + `…Color`) |
| `ageing` | `ageing` 3 | head overlay id, colour-less |
| `prop` | `hat` 0, `glass` 1, `ear` 2, `watch` 6, `bracelet` 7 | ped prop slot (`SetPedPropIndex` / `ClearPedProp`) |
| `face` | `face`, `face2`, `facemix` | all three feed `SetPedHeadBlendData` |
| `eye_color` | `eye_color` | `SetPedEyeColor` |
| `moles` | `moles` | head overlay 9 |
| `nose` / `cheek` / `chin` | the 20 morph sliders | the `id` here is decorative; `ChangeVariation` uses a fixed `SetPedFaceFeature` index per slot name |

Component index summary, for reference when writing outfit tables:
`0` head, `1` mask, `2` hair, `3` arms/torso, `4` legs/pants, `5` bag, `6` shoes, `7` accessory
(neck/chains, and the tracker), `8` undershirt, `9` vest/armour, `10` decals/badges, `11` jacket/top.
Prop slots: `0` hat, `1` glasses, `2` ear, `6` watch, `7` bracelet.

### Face morph handling

The 20 morph slots (`nose_0`–`nose_5`, `eyebrown_high`, `eyebrown_forward`, `cheek_1`–`cheek_3`,
`eye_opening`, `lips_thickness`, `jaw_bone_width`, `jaw_bone_back_lenght`, `chimp_bone_lowering`,
`chimp_bone_lenght`, `chimp_bone_width`, `chimp_hole`, `neck_thikness`) are stored as integers and
**divided by 10** immediately before `SetPedFaceFeature`. `moles` texture is likewise divided by 10
before it reaches the overlay opacity argument. `GetMaxValues` reports a max of `30` for these, so
the usable range in the UI is `0`–`3.0` after scaling. (The field names `chimp_*` and `*_lenght`,
`neck_thikness` are spelled that way in the code; they are the literal keys you must use in an
outfit table.)

### `GetMaxValues`

Recomputed against the *current* ped on every `ChangeVariation` call and on menu open, then pushed to
the NUI as `updateMax`. Drawable and prop counts come from the natives; face/`face2` are hard-capped
at item 45 / texture 15, `facemix` at 10, hair and overlay textures at 45, eye colour at 31, and the
morph families at 30. The NUI uses these to clamp its arrows and set input `max` attributes.

## NUI

`ui_page` is `html/index.html`; `html/script.js` is the controller.

### Messages sent by Lua (`SendNUIMessage`)

| `action` | Payload | Effect |
| :--- | :--- | :--- |
| `open` | `menus`, `currentClothing`, `hasTracker`, `translations` | `TMGClothing.Open` — builds the tab header from `menus`, populates outfit lists, and seeds every input from `currentClothing` |
| `updateMax` | `maxValues` | `TMGClothing.SetMaxValues` — writes `data-maxItem`/`data-maxTexture` and input `max`/`min` per category |
| `reloadMyOutfits` | `outfits` | `TMGClothing.ReloadOutfits` — re-renders the personal outfit list |
| `ResetValues` | — | `TMGClothing.ResetValues` — resets every input to its slot's `defaultItem`/`defaultTexture` |

The page also has `close` and `toggleChange` cases in its message switch, but **the Lua side never
sends either**. Closing is always initiated from the page.

The `translations` payload is built by filtering `Lang.phrases` down to keys prefixed `ui.`, stripping
that prefix, and sending the rest. The page looks them up by bare key via `data-tkey` attributes.

### Callbacks the page posts back (`RegisterNUICallback`)

| Name | Body | Lua behaviour |
| :--- | :--- | :--- |
| `updateSkin` | `{ clothingType, articleNumber, type }` | `ChangeVariation` — arrow clicks and slider drags |
| `updateSkinOnInput` | same | Identical handler — typed-in values. Both names share one implementation. |
| `setCurrentPed` | `{ ped: <index> }` | Swaps to `Config.ManPlayerModels[ped]` / `Config.WomanPlayerModels[ped]` per gender, resets every slot to defaults, and returns the model name so the page can display it |
| `selectOutfit` | `{ outfitData, outfitName, outfitId? }` | Fires `tmg-clothing:client:loadOutfit` as a live preview |
| `saveOutfit` | `{ outfitName }` | Sends the current `skinData` to `tmg-clothes:saveOutfit` |
| `removeOutfit` | `{ outfitData, outfitName, outfitId }` | Sends `tmg-clothing:server:removeOutfit` and notifies |
| `saveClothing` | — | `SaveSkin()` — commits to `playerskins` |
| `resetOutfit` | — | Re-applies the `previousSkinData` snapshot and restores `skinData` |
| `close` | — | Releases focus, tears down the camera, unfreezes the ped, fires `tmg-clothing:client:onMenuClose` |
| `rotateLeft` / `rotateRight` | — | Orbits the camera ±2.5° around the ped. Bound to `A` and `D` in the page. |
| `rotateCam` | `{ type: 'left'\|'right' }` | Turns the **ped** ±10° and re-aims the camera |
| `setupCam` | `{ value: 0\|1\|2\|3 }` | Camera preset: `1` head, `2` torso, `3` legs, anything else full body |
| `TrackerError` | — | Notifies that the ankle monitor cannot be removed |
| `getCatergoryItems` | `{ category }` | Returns `Config.Menus[category]` — **never posted to by the shipped page, and `Config.Menus` does not exist** |

The tracker gate is enforced in `html/script.js`: any attempt to change the `accessory` category
while `hasTracker` posts `TrackerError` and aborts. Drawable 13 is also skipped over by the
arrow/slider handlers so it can never be selected manually.

## Security & reliability notes

- **The client is authoritative over appearance.** `tmg-clothing:saveSkin` accepts and stores the
  submitted skin string without parsing or bounding it, and `tmg-clothes:saveOutfit` does the same
  for outfit documents. A modified client can persist any component/prop combination, including ones
  not offered by the UI. This is normal for a live-ped appearance editor but should not be mistaken
  for validation.
- **The ankle-monitor lock is client-side only.** `hasTracker` is pushed to the NUI and enforced in
  JavaScript; `loadOutfit` re-forces component 7 to drawable 13 on the client. Nothing server-side
  rejects a skin that omits it.
- **Job/gang wardrobe gating is client-side.** Zone visibility checks `PlayerData.job.name` /
  `PlayerData.gang.name` against `requiredJob`, and grade level selects the preset list. With
  `Config.UseTarget`, `tmg-target` additionally receives `job = v.requiredJob` on the option. Neither
  path involves the server, and the presets themselves are shared config the client already holds.
- Outfit **deletion** is properly scoped — the query always includes the caller's `citizenid`.
- Rate limiting: none anywhere in this resource. `saveOutfit`, `removeOutfit` and `saveSkin` can each
  be called as fast as a client can trigger them, and each save inserts a new document.
- `loadAnimDict` in `client/main.lua` loops without a timeout. If a dictionary never streams in (bad
  name, missing asset), `adjustfacewear` hangs its coroutine indefinitely.

## Known limitations

- **`Config.Menus` does not exist.** The `getCatergoryItems` NUI callback returns `Config.Menus[...]`,
  which is a nil index on a nil table. The shipped `html/script.js` never posts to it, so it is inert
  — but any page change that starts using it will error.
- **`Config.LoadedManModels` / `Config.LoadedWomanModels`** are declared empty and never touched.
- **No `surgeon` store is configured.** The `shopType == 'surgeon'` branch exists in the blip loop,
  the target/zone builder and the `[E]` thread, but `Config.Stores` contains only `clothing` and
  `barber` entries, so the plastic-surgeon menu is unreachable from a store.
- **`TMGClothing.SetMaxValues(data.maxValues)` inside `TMGClothing.Open` is a no-op.** The `open`
  message does not carry `maxValues`; the values arrive from the separate `updateMax` message that
  `openMenu` sends first (via `GetMaxValues()`), so the UI is correct in practice, but that call
  itself does nothing.
- **`close` and `toggleChange` NUI messages are unreachable.** Both are handled in the page and never
  sent by Lua. There is consequently no way for another resource to force the menu shut.
- **`tmg-clothing:client:adjustfacewear` has no caller** anywhere in the repo. The `faceProps` table
  it maintains is also global to the module rather than per-invocation, so interleaved calls for
  different item types can clobber each other's stashed state.
- **`removeWear` is a single module-level flip-flop**, shared across all five `adjustfacewear` types.
  Toggling a hat off then glasses off leaves the flag desynchronised from what is actually worn.
- **The non-target path's clothing-room zone build is conditional on data that may not be loaded.**
  `loadStores()` guards the room `ComboZone` behind `PlayerData.gang and PlayerData.gang.name or
  (not TMGCore.Shared.TMGJobsStatus and PlayerData.job.name)`. If the player has no gang and
  `TMGJobsStatus` is true, no room zones are created at all — and the `Config.UseTarget` branch has a
  matching `break` that stops registering rooms entirely under the same condition.
- **`Config.OutfitChangers` entries carry `shopType = 'outfit'`**, and the non-target `ComboZone`
  names zones by `v.shopType`. All 15 outfit changers therefore share the zone name `outfit`, as do
  all clothing stores (`clothing`) and barbers (`barber`). The `[E]` thread only needs the type, so
  this works, but the zones are not individually identifiable.
- **Outfits are unbounded and unversioned.** No limit on count, no name length cap, no uniqueness
  check, and every save creates a new document with a new `outfitId` rather than updating an existing
  one.
- **The `outfitId` generator is weak** (`math.random(1,10)` × `math.random(1111,9999)`) and is not
  seeded per-save. Collisions across the whole collection are likely at scale; they are only harmless
  because deletes are scoped by `citizenid`.
- **`ChangeToSkinNoUpdate` blocks on `HasModelLoaded` with no timeout**, inside its own thread. An
  invalid model name from `Config.ManPlayerModels`/`WomanPlayerModels` spins forever.
- **`reloadSkin` uses two fixed 1000 ms waits** rather than waiting on actual model/skin readiness, so
  it is both slower than necessary and not guaranteed to be long enough on a loaded server.
- **Locale coverage is partial.** `locales/` ships `en`, `da`, `es`, `nl`, `pt-br` only, and
  `ui.select_outfit` in `en.lua` is left as untranslated Portuguese text.
