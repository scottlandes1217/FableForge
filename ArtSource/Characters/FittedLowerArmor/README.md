# Shared-skeleton lower armor

`create_lower_armor.py` refits the downloaded Modular Character Outfits authored male/female peasant trousers and boots onto the playable body rig. It preserves UVs and uses the existing MI_Peasant material. The original armor assets are untouched.

Trousers have one additional subdivision and interpolated current-body skin weights to prevent the original female thigh clipping. Boots retain their authored straps/cuffs and have enlarged toe boxes. Both use the current BodyV2 morph contract; female offsets use the same 0.8 factor as the female body. Only channels affecting the garment survive Unreal import (seven trousers, two boots).

Run Blender in background with create_lower_armor.py, then UnrealEditor-Cmd with Tools/Unreal/import_lower_armor.py. The importer updates only peasant_legs and peasant_feet table mappings. Runtime chooses the female sibling assets when appropriate. All assets use the existing playable skeleton and leader-pose attachment.

Validation:
- import-validation.json records exact 89-bone hierarchy identity, shared skeleton, materials, and retained morphs.
- validate_lower_armor.py checks imported component reference bone transforms against the body.
- render_run.py tests frames 6, 16, and 40 of the existing run plus a combined broad-body morph setting. Result images are saved alongside this file.
- These Blender screenshots isolate clothing fit with simple colors, not the final Unreal lighting/materials. Final game equip/run inspection remains necessary; every possible morph and animation combination is not exhaustively verified.

## Waist and heel correction

The waistband above z102 cm is tucked closer to the body to stay underneath the unchanged tunic. A small inner waistband follows exact body topology/weights; it prevents skin showing through sparse authored panels during MM_Idle. Both boot versions include a closed calf/heel lining (1.4 cm calf clearance, 1.8 cm foot clearance) beneath the original detailed shell. These lining sections use Boot_Leather_Lining.

`render_idle.py` runs the outfit harness using gameplay_idle.fbx exported from the actual MM_Idle asset. Rear views are included for both body types, in addition to the original run and broad-body checks. Main game rendering and animation-blend transitions still require live QA.
