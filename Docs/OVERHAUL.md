# FableForge presentation and runtime polish

## Implemented

- A consistent ink, parchment and brass treatment across the start menu, character creation, journal, inventory, chest, action bars and party HUD.
- Branded start screen, creation step headings, explicit typography, selected states, scrolling lists and scale-to-fit menu surfaces.
- Cached, transparent 128px icons for the 14 existing items, plus skill motifs. Authored icons still take priority. Inventory, equipment, chest, skills, action bars and drag previews share the fallback artwork.
- Cooldown changes update timer overlays instead of rebuilding each slot's complete appearance every frame. Idle slots no longer repeatedly invalidate their appearance.
- Inventory-only changes preserve equipped mesh components. Weapon bounds no longer inherit the smaller body bounds. Body hiding uses material IDs correctly. Incompatible body armor and unmapped armor retain the visible base body instead of producing rigid pieces or cubes.
- Bounded, substepped camera lag; doors tick only while moving; Take All saves and notifies once per transfer.
- Failed inventory writes roll back the profile and reload the journal's displayed state. Loot remains in the chest when saving fails.
- Closed-chest focus and modal click-through fixes; Escape closes gameplay panels.
- Temporal anti-aliasing enabled to reduce shimmering edges.
- Medieval navigation volume fitted to landscape bounds with padding. Original coverage was 40 km square; corrected coverage is 1.028 km square. The art, landscape and scene composition remain intact.

## Tooling

Epic's bundled Python Editor Script Plugin and Editor Scripting Utilities are enabled for editor builds. Blender 5.0.1's local Python interface is verified. No remote scripting server was enabled. See `Tools/Unreal/README.md` for the asset audit command.

`Tools/Unreal/fix_navigation_bounds.py` defaults to a dry run. Its explicit `--apply` mode backs up the map before saving. The original map is preserved in `Saved/OverhaulBackups/20260921T011348Z/`.

## Validation

- UE 5.7.3 Mac Development Editor compilation succeeded.
- `FableForge.UI.ItemIcons.CoverageAndCaching` passed: all 14 item silhouettes are visible and distinct, dimensions/transparency are correct, and cached lookups reuse textures.
- `FableForge.Character.ModularArmorHierarchy` passed: compatible subsets, invalid/missing bones, mismatched parents, empty meshes and the shared-skeleton false positive are covered.
- Unreal Python asset audit completed successfully, confirming both scripting facilities work.
- A fresh gameplay launch after the navigation correction no longer reported oversized navigation bounds.
- Start → heritage → identity → save slot → gameplay was exercised with an isolated test character; journal icons were visually inspected. Real saves under the project's `Saved/SaveGames` were not used by the QA session.

## Remaining limits

This is not a claim that the whole game is finished or that every hardware target has been profiled. Full traversal, mouse drag/drop, packaged builds, sustained frame-time measurement and all physics interactions still need broader playtesting.

The existing animation blueprint reports a rig hierarchy mismatch: the playable mesh uses `root_001`, while the mannequin control rigs expect `root`. Those binary character/armor assets were being repaired separately during this work; this pass did not overwrite them. A coordinated rig/animation repair is still needed to eliminate that warning.

Missing map built-data is also reported on load. The map uses dynamic lighting, but a packaged build and lighting validation remain necessary. Chest contents regenerating on map reload is an existing persistence limitation outside this polish pass.

## Storybook redesign

The front end now uses an opaque leather cover and two-page parchment spreads, with Crimson Text serif typography, gold tooling, layered page edges, a shaded gutter and a ribbon bookmark. Heritage and identity are presented as chapters; character selection and save slots share the same book. The inventory and skills journal use the parchment surface and paper-colored slots.

Main-world rendering is disabled while the front-end book is open and restored after successfully entering a character slot. The character creation portrait remains an independent preview viewport.

Validation: Development Editor build succeeded; the cover, heritage, identity, save-slot selection, entry into the village, and inventory journal were visually checked in an isolated `/tmp/FableForgeBookQA` session. Captures are in `Saved/BookScreenshots/`. Existing real saves were not used. This pass does not add page-turn animation or new character customization options.

### Layout and preview follow-up

Simplified menu labels to New Game, Continue, Choose Race, Create Character and Save Slot; removed narrative filler. Reduced action button padding so controls remain inside the book margins. Inventory headings and help text now use plain language.

The character preview plays the existing compatible MM_Idle animation instead of the reference pose. The camera is pulled back slightly and recentered; the key light stays fixed in world space while the model rotates, with gentler directional light and more ambient fill. These changes affect the preview only.

Validation: UE 5.7.3 Development Editor build succeeded. Simplified menu layout and animated preview were checked in the isolated layout QA game session.

### Button styling and race layout

Race selection uses a two-column grid with every current race visible. Main menu actions have explicit heights. Shared button brushes now use cached, nine-sliced artwork with double gold borders, clipped corners and corner diamonds; hover and pressed states remain distinct. Text input retains its plain inset appearance. Cover content is centered on the tooled front panel (excluding the spine).

Validation: Development Editor build succeeded; cover alignment and all six visible race choices were verified at 1280×800 in-game. Screenshots: `Saved/BookScreenshots/cover-ornate.png` and `race-grid.png`.

### Material depth and HUD

Added generated leather cover, parchment spread, and perspective journal icon artwork under `Content/Slate/Textures`. Menu textures are cached and loaded once; procedural book surfaces remain as fallback. Shared buttons use shaded bevels and subtle grain. Minimum action heights and larger text padding prevent border crowding, and page content is inset from the binding. Inventory cells are sized to the narrower writable areas.

The HUD now has layered brass/leather framing, a larger portrait, labeled inset health/mana bars and an understated experience bar. Portrait framing and exposure were adjusted. The bottom-right Character control uses the perspective book artwork, with a Character (I) tooltip and existing action binding. These are rendered UI assets rather than interactive 3D book meshes.

Validation: Mac Development Editor build and whitespace checks passed. Live checks covered full health/mana fills, portrait framing, book-icon keyboard activation, loading a save, and page/button margins. The isolated QA save directory was used.

Follow-up: removed page filigree/ribbon and the redundant Character heading; raised journal tabs and content, with larger cells restored inside the available page area. Equipment hand labels wrap instead of overlapping.

HUD follow-up: compact 310-unit card with ornate brass/leather artwork, smaller framed portrait and compact bars; bottom action bar gains carved frame and individually recessed dark slots.

### Shared body and appearance controls

Added a separate Appearance page with eight live body/face morph controls and bounded height. Race/gender defaults and ranges live in `Source/FableForge/RPG/UI/FableAppearancePresets.h`. The profile and per-slot save store the chosen values; old saves receive neutral defaults. The character and modular armor receive morph weights after equipment rebuilds. Height scales the character uniformly; this is not arbitrary bone editing or a complete anatomical gender transformation.

The original body and shirt are preserved. Authored sibling assets are `basecharacter_v2` and `FittedTunic/peasant_tunic_v2`, sharing the existing 89-bone skeleton. The tunic follows four body morphs and uses dark blue linen with separate brown trim. Editable Blender/FBX sources and validation notes live under `ArtSource/Characters`. The v2 skin material keeps the original color texture with controlled roughness/specular; it does not add new skin texture detail. A localized groin weight correction reduces measured run-pose stretching; it does not eliminate every animation deformation.

HUD follow-up replaces map-dependent portrait capture with an independently lit preview world, centers the name, restores spacing and anchors the card at the upper-left. Eight missing item props now have authored Blender models and table references; icons are rendered from actual table meshes.

Validation: Mac Development Editor build passed. All four FableForge automation tests passed (appearance asset compatibility, save round-trip, armor hierarchy, icon caching/coverage). Live QA verified all nine controls fit, height changes the preview, the resulting test save contains height 1.05 and all eight morph keys, character creation reaches gameplay, and corrected skin textures display in-game. FBX import now asserts material-section mapping [0,1,2]; this caught and fixed an initially gray body. Actual item renders cover 12/12 current table items. Full animation/clothing combinations and packaged distribution remain unverified.

Final visual check: dark blue fitted tunic and studio HUD portrait verified in the village; capture `Saved/BookScreenshots/hud-body-tunic.png`. Trim section material was explicitly restored after FBX reimport. Keyboard automation could not reliably sustain gameplay movement, so running validation is limited to the sampled Blender poses; no claim of complete in-game clipping elimination.

### Expanded character creator (September 20, 2026)

Replaced the limited appearance page with eight sections: Body, Face, Eyes, Nose, Mouth, Ears, Skin, and Hair. There are 24 authored morph controls plus height, six scalp choices including bald, an optional beard, color presets, and RGB controls for skin, eyes, and hair. Face sections use a close-up camera; the preview also supports full-body framing and rotation. All current controls fit without scrolling in the 1400×900 book design. Shared action labels stay on one line. Revisiting the same race or gender preserves edits.

Female selection now loads an authored female mesh from the user's CC0 Quaternius Universal Base Characters pack, rebound to the same 89-bone animation skeleton as the male. Both use separate v2 assets and the original sources remain preserved. Both bodies carry 25 morph targets (the legacy FemaleBody morph is skipped on the authored female). Body-fat, frame, waist, hips, and shoulder ranges were expanded after live review. Facial deltas are restricted to the head; eye size and spacing include the eyeballs. A female neck seam split during smoothing was welded without discarding UV loops. The two fitted tunics carry nine matching body shapes.

Gray skin was traced to material morph-target usage as well as first-use shader compilation. Body materials now support morph targets and use the source albedo, normal and roughness textures. The editor preview finishes pending asset compilation before displaying a newly selected mesh. Hair variants fit each body and follow the head bone. Appearance values are saved in profiles and slots, applied to the gameplay mesh, and reused by the HUD portrait.

Validation: Development Editor build succeeded. The four FableForge automation tests cover body/skeleton/material compatibility, appearance save round-trip, modular armor hierarchy, and item icons. Live isolated QA exercised female selection, body fat, jaw and eye changes, hairstyle and color changes, skin presets, character creation, gameplay entry and restart/load. Existing user saves were not used. Source geometry checks cover individual morph endpoints and sampled jog poses. Final captures are under `Saved/CreatorScreenshots/` and test output is under `Saved/CreatorTestReport/`.

This is a substantially expanded stylized creator, not a finished photorealistic AAA character system. The source characters and hair remain stylized assets. Scars, tattoos, makeup, facial animation, arbitrary bone editing, and exhaustive clothing/animation combinations are not implemented or certified by this pass. A packaged Mac distribution was not built.

### Full-window pages and interactive preview

Open front-end books now fill the game window, with inset page margins. Identity choices are side by side; Back and the next/create action share a bottom row. Reset section stays with its controls. The cover retains its proportions and scales to the available height.

The character preview supports left-drag rotation, wheel zoom, a keyboard-accessible zoom slider, and a reset-view action (also double-click). Left/right keys rotate when the preview has keyboard focus. Zoom moves continuously between full-body and head framing; Face/Full body and rotation buttons were removed. Switching appearance sections preserves the view.

Rebuilt pages now receive fresh widget instances. Reusing explicit object names across page rebuilds could release the new viewport's Slate resources while its old rendered surface remained visible, leaving camera updates disconnected. The preview and slider widgets no longer replace retired widget objects in place.

Validation for the interaction follow-up: Mac Development Editor build and whitespace checks passed. Live QA verified full-window margins, continuous zoom limits, rotation, and retained camera state after switching tabs. Native pointer handlers were exercised with the editor QA commands; desktop mouse injection was unreliable in this session, so a physical mouse/trackpad pass remains useful. Screenshot: `Saved/CreatorScreenshots/fullscreen-interactive-creator.png`. The last four-test appearance suite passed before this UI-only follow-up.

### Race identities and appearance selectors

The six races now have distinct defaults and enforced customization ranges for height, frame, muscle, face and ears. Orcs start taller and broader with heavier jaws and pointed ears; elves are slender with longer pointed ears; dwarves are short and broad; halflings are short and softer. Tieflings have their own proportions and red, purple and ash skin palette. Each race exposes only its allowed skin swatches. These policies apply to both genders and are validated when creating and saving profiles. Existing human saves retain their prior valid appearance values.

Race selection now includes the interactive 3D preview. Appearance uses Body, Face and Style tabs; Face has an arrow selector for its feature groups. Style uses wrapping previous/next selectors for skin tone, hairstyle, facial hair, hair color and eye color, with names, counts and color chips. Styles and color catalogs live in Content/Data/AppearanceStyles.json; see APPEARANCE_CATALOG.md for expansion. The current catalog includes six hair choices (including bald) and two facial-hair choices (including none). Race changes preserve hairstyle and eye/hair colors while resetting racial anatomy and skin. No new tusk, horn or bespoke race mesh assets were added.

Short hair was refitted to both source scalps with denser topology and approximately 3 mm clearance, correcting the existing cropped-cap intersections. Source proofs are in ArtSource/Characters/Hair/Validation.

Validation: Mac Development Editor build succeeded and all five FableForge automation tests passed, including RaceAppearancePolicy across all six races and both genders, invalid values, palette restrictions and save round-trip. Live isolated QA checked race differences, female selection, style cycling, color updates and preview zoom. Test report: Saved/RaceCreatorTestReport.

### Page containment and balanced body proportions

The open book now uses a shared 1440×900 design canvas for the artwork and its contents, scaled together to the available window. Page content is inset farther from the edges and spine. Style selectors have bounded row heights, smaller values and arrows; compact buttons use explicit heights instead of allowing the texture's desired size to enlarge them. Body and Style pages were visually checked at 1280×720 with the full footer and reset controls contained on the paper.

BodyBuild and Muscle previously added disproportionate torso depth while barely enlarging limbs. The revised shared morph contract reduces torso depth and distributes muscle around upper-arm, forearm, thigh and calf axes, with smooth attenuation at the armpits and groin. Orc defaults and allowed frame ranges were rebalanced. Male and female body assets and fitted tunic shapes are regenerated from this shared contract. Source front/side comparisons and combined-limit geometry results are in ArtSource/Characters/BodyV2/orc-*.jpg and orc-proportion-validation.json.

Final validation for this correction: Mac Development Editor build succeeded; all five FableForge automation tests passed after importing both revised bodies and tunics (Saved/ProportionTestReport). Live Unreal inspection verified male/female side profiles, race selection, Body and Style page containment at 1280×720 and 1440×900. Both genders passed morph endpoint and combined-upper-limit triangle-orientation checks; run poses and fitted tunics were visually inspected. This is sampled animation/fit validation, not certification of every possible equipment and animation combination.

### Stable creator and journal interactions

Creator color/style cycling and resets now update existing text, swatches, buttons, morphs and materials. Race/gender choices retain the current page and viewport; appearance section changes replace only the controls column. The preview world, character and camera are no longer destroyed for ordinary selections. Re-selecting the current appearance section is a no-op.

Inventory filtering and item moves retain existing cells, slot widgets and scroll container. The All filter preserves physical bag positions instead of packing moved items back toward the start. Skill filtering retains list rows; skill selection refreshes only passive details. Re-selecting current main/category tabs is a no-op, and reopening inventory refreshes its existing presentation.

Validation: Development Editor build succeeded. All six FableForge automation tests passed, including JournalPreservesInteractiveWidgets (filter actions, Slate scroll identity/offset, stable destination cells, selected-tab behavior and skill callbacks). Eleven live creator stability checks passed for skin/hair/beard/color selections and appearance/feature switches, retaining the same viewport/world/camera. Reports: Saved/StabilityTestReport and Saved/StabilityQA.log.

### Halfling height and dwarf head proportions

Halfling height now ranges from .82 to .94 of the shared base, with male/female defaults .88/.85 (approximately 156/150 cm using the creator's height reference). Dwarf height stays unchanged. Both bodies have a HeadSize morph with a smooth neck transition: dwarves default to .67, producing a 20.1% larger head, with a .40–1 adjustment range under Face. Other races default to zero. Eyes and brows follow the shape; hair and beard attachments scale around the matching head pivot in creator, gameplay and portrait views. Existing profiles receive the new racial default when missing the control, while saved halfling heights are clamped to the raised range.

Validation: Development Editor build and all six automation tests passed, including new head morph availability and hair pivot/scalp transform assertions on both skeleton-compatible bodies. Live Unreal checks confirmed dwarf hair/beard fit and the male halfling's 156 cm default. Both genders passed authored head-shape endpoint and dwarf combined-limit checks. Test output: Saved/RaceScaleTestReport.

### Transparent preview, vertical pan and body-first flow

New Game now opens name/body-type selection, then race selection, then appearance. Body type uses two transparent silhouette buttons rendered from the actual neutral male/female Blender meshes; source script is ArtSource/Characters/BodyV2/render_body_type_icons.py. Back navigation follows the new order and preserves selections.

Horizontal dragging rotates the preview; vertical dragging pans the camera along the character. Pan sensitivity scales with zoom and focus is bounded to the body. Reset view and double-click restore rotation, zoom and pan. The grey viewport border/background is removed. UFableTransparentViewport preserves Unreal's native preview scene while compositing its alpha over the book page. Renderer alpha propagation is enabled; straight-alpha blending prevents transparent scene RGB from tinting the parchment.

Validation: Development Editor build succeeded; all six automation tests passed before the final compositor-only straight-alpha adjustment. Final live rendering verified character visibility over continuous parchment without the prior background rectangle/halo, and correctly sized silhouette buttons. The body-type→race→appearance path retained the selected female mesh. Native vertical-drag QA at zoom .85 moved camera Z from67.449 to7.305 while X stayed63.929; reset clears pan. User began interacting with the final creator, so further scripted UI interaction stopped.

### Simpler navigation labels and preview headings

Creator forward buttons now read Next, and the right-side preview no longer has a character-name or race heading. The recovered vertical space belongs to the interactive preview; the left-page step heading remains.

### Female front-groin seam repair

Investigation reproduced the vertical crease in the resting mesh with the normal map disabled. A disconnected coincident UV seam contributed a hard shading line, and the underlying front surface also had an exaggerated central recess. The selected repair welds only coincident local seam vertices while retaining UV loops, then fits the front center strip to neighboring cross-sections to remove both the recess and a shallow ridge. Existing pelvis-dominant skin weights and the shared skeleton are retained. The female importer now recomputes MikkTSpace tangents, and the original normal map is retained. Source evidence is under ArtSource/Characters/BodyV2/groin-*.jpg; final idle proof is Saved/CreatorScreenshots/female-surface-repair-idle.png.

Validation: Development Editor build succeeded; all six FableForge automation tests passed after the final mesh import (Saved/FemaleSeamTestReport). All 26 individual morph endpoints and the combined endpoint passed triangle-orientation checks; sampled run poses were inspected. Live Unreal verified both Next labels, the removed preview heading, and the smoother female front surface in the actual idle animation.

### Equipped armor, portrait and weapon animation repairs

The peasant trousers and boots had empty mesh assignments. DT_Armor now maps fitted lower garments to the shared skeleton, with female mesh overrides. Authored trousers and boot details retain their original materials; closed leather linings cover the boot shell's open rear panels. Body morphs and normalized skin weights are transferred to the garments. Male deltoid skinning now blends the shoulder cap toward the clavicle with a smooth falloff, preventing the detached-looking running bulge; the tunic uses matching weights. Rest positions, UVs, all 26 body morphs and the female body are unchanged.

The HUD name occupies a centered row across the card, clear of the ornament. Removed the panel's implicit padding so the frame sits closer to the top-left. A still studio portrait copies the actual body, materials, morphs, hair and attached equipment; it refreshes only when its source appearance changes and uses a wider crop and softer light. This replaces the bare profile-only duplicate and obsolete world scene-capture code.

The sword grip socket is moved from its guard to the actual handle center. An equipped-sword mesh component blends a closed finger/thumb grip over locomotion. While airborne, it positions the right arm and blade outside the torso; unarmed animation is retained after blend-out. The correction runs before publishing pose buffers, so attachments and modular clothing use the same transforms. Ragdoll skips the correction.

Validation: Mac Development Editor build and all seven automation tests passed (Saved/ArmorHudTestReport), including 21 phases of the actual jump sequence on both meshes, partial blends, finite normalized transforms, bone-length preservation and unchanged unrelated/unarmed bones. The blade test uses a conservative torso envelope; it does not certify every possible morph/equipment combination. Imported lower garments match all 89 reference bones exactly. Source checks cover multiple run poses, rear views, broad body morph combinations, and male shoulder walk/jog/jump poses.

Live Unreal checks confirmed both male/female lower armor assignments, the runtime weapon-pose component on the inherited gameplay Blueprint, a raised sword clear of the torso during an actual jump, and the portrait changing from five attached visuals to four and back when the shirt is removed/re-equipped. Final HUD screenshots show the name inside the frame and the full head/upper armor crop. Evidence: Saved/GameplayScreenshots and Saved/ArmorHud*QA.log. Desktop automation became unavailable during QA; final captures were produced through isolated editor-only gameplay commands and Unreal's native screenshot facility. All QA saves use separate /tmp/FableForge directories.

Final rear idle inspection confirmed the added dark leather lining covers the previously exposed calf/heel panels (Saved/GameplayScreenshots/male-equipped-rear.png).

### HUD and fit refinement after close-up review

The HUD card now has explicit 350×138 bounds and a safe content inset. The name sits above the bars alongside the portrait, clear of the ornament. The portrait uses the same transparent compositor as the creator, with reduced studio illumination; the gray rectangle is removed. Bars show current/maximum points derived from the saved fractions and race BaseHitPoints/BaseMana. Current race data is 10 HP and 0 mana, so full bars read 10 / 10 and 0 / 0 with an empty mana reservoir. New alpha icons JournalUpright.png and SettingsEmblem.png replace the tilted journal and text settings button.

Corrected the earlier sword-socket experiment: the sword Root bone is offset −11.237671 cm. HandGrip is now Root-local Z=12.237671, yielding component-space Z=1 cm, centered within the measured usable handle span −4..6 cm. Runtime equip logging confirms this component-space result. Finger/jump animation logic is unchanged.

Trousers now tuck beneath the existing tunic silhouette, with a body-weighted inner waistband. Closed boot lining clearance increases around calves, ankles and heels. Both genders were checked with exported actual idle and running poses before reimporting; reference transforms remain unchanged. Build and all seven automation tests passed (Saved/HudPolishTestReport).

A body-hidden rear diagnostic proved the remaining boot/waist patches were outfit material artifacts, not body clipping. The two foot meshes now use the same peasant material in every slot, removing the contrasting lining response.
### Camera follow regression fix

The character camera now activates explicitly when the pawn begins play and the shoulder-follow update no longer depends on the transient `IsLocallyControlled()` result during possession. This keeps the spring-arm camera attached to the possessed character while preserving the controller's ability to replace the view target.
