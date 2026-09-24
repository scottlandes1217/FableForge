# Character creator hair

Adapted from the user's existing Quaternius Universal Base Characters Standard download, licensed CC0; license retained beside this file. The original pack contains five scalp styles, a beard and two eyebrow sets. There is no separate eyelash model in this pack.

`prepare_hair.py` fits the authored static FBX geometry to the current male body by aligning the authored regular eyebrow mesh to the existing eyebrow section. `--female` fits the female eyebrow pair, producing matching female versions of every style. Alignment reports preserve the transforms and residual error. UVs and original normal maps are retained.

Generated FBXs are in the body component's reference space, in meters before UE's centimeter conversion. Runtime components attach to `head` with the inverse of its composed reference transform; no per-style offsets are needed. Static meshes avoid incompatibilities between the original 65-bone source rigs and the game's 89-bone rig.

Unreal assets: `/Game/Characters/PlayableCharacter/Hair/SM_Hair_{Buzzed,BuzzedFemale,Long,SimpleParted,Buns,Beard}` and female counterparts `SM_Female_Hair_*`. Eyebrow assets are included separately but the existing body eyebrow section remains visible by default. Hair materials expose vector parameter `HairTint`, preserve source albedo/normal detail, and use opaque two-sided shading.

Run `Tools/Unreal/import_creator_hair.py` through the normal editor `-ExecutePythonScript` to import and assign materials. Source scenes, exports and license are preserved for further art adjustments.

Short caps additionally use subdivided geometry fitted to the actual target scalp with 3 mm nominal clearance. `prepare_hair.py -- --short-only` (and `--female --short-only`) rebuilds only these caps; `Tools/Unreal/reimport_short_hair.py` imports only the four affected assets. Alignment JSON records minimum vertex/face clearance; `Validation/` contains before/after source renders.
