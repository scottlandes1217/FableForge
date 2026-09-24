# Shared body shape source

`FableForge_BodyV2.blend` and `basecharacter_v2.fbx` add eight shape keys to the previously repaired body. The original body asset is preserved. Unreal sibling: `/Game/Characters/PlayableCharacter/Meshes/basecharacter_v2`, using the existing 89-bone `SK_Mannequin` skeleton, original material slots, and physics asset.

The morph contract is `BodyBuild`, `ShoulderWidth`, `WaistWidth`, `HipWidth`, `JawWidth`, `CheekWidth`, `NoseWidth`, `EarLength`. Values range from -1 to 1, neutral 0. These are conservative proportion changes; they do not represent new anatomy or arbitrary skeleton editing. Height is handled at runtime. The same coordinate functions in `morph_contract.py` are used by the fitted tunic generator for its four body morphs.

Run `create_body.py` in Blender background mode, then `Tools/Unreal/import_body_v2.py` via Unreal Python. FBX export strips material graphs from export-only placeholders to avoid a UE5.7 commandlet crash caused by duplicate source texture names; the saved Blender file retains its materials, and the import script restores original Unreal materials.

Validation: 8,421 source vertices; all eight imported Unreal morph targets verified; all 89 bone names match; original skeleton reference preserved. `validate_endpoints.py` checks rest triangle orientation and area at each individual -1/+1 endpoint and all-shapes-together -1/+1. No inverted triangles were found. This is a topology check, not a complete animation or clothing regression. Different signed combinations and all animations are not exhaustively checked.

The painted boxer texture is retained. A skin material audit found only a base-color texture and default roughness/specular. `Tools/Unreal/refine_body_skin.py` creates `M_BodySkin_V2` with explicit .72 roughness and .28 specular, applied only to the new body. This reduces glossy highlights but adds no invented normal detail.

The groin stretching reproduces in Blender using the imported run, so it is not solely an Unreal shader problem. Broad smoothing and generic twist redistribution worsened maximum stretch and were rejected. A localized smooth pelvis blend centered at z89cm, with 6cm horizontal/vertical falloff and maximum strength .5, improves the central groin seam. All other source weights remain unchanged. The final generated weights were tested across 19 run frames: maximum hip edge stretch falls from 3.064 to 2.684, edges exceeding3x from1 to0, p99 from1.782 to1.770. Arm metrics remain unchanged. Frames16/40 were visually compared; evidence is in `hip-final-validation.json` and the `hip-before/after` images. This reduces distortion, not a claim of zero stretching or a full animation regression.

## Expanded appearance system

The current contract contains 25 channels; `morph_contract.py` is authoritative. BodyBuild/widths now have stronger visible endpoints. FemaleBody, BodyFat, Muscle and Bust are 0..1; remaining channels are -1..1. FemaleBody is skipped on the authored female mesh. Both meshes retain the same 89-bone reference skeleton, enabling shared animation; gender selects the appropriate base mesh rather than forcing mismatched topology into a shape key.

`femalecharacter_v2` is derived from the user's Universal Base Characters female GLTF. The original female face, body topology and UVs are retained. Source bind directions are mapped to the existing arm/leg chain, preserving the common rig hierarchy. Torso coordinates retain authored proportions; the sternum transition is smoothed locally. Source copies are in `SourcePack`, and `create_female.py` builds the editable Blender file and FBX. Female channels use 80% of the common coordinate offsets, matched by the female tunic generator.

`create_body_materials.py` adds SkinTint/HairTint/EyeTint vector parameters and explicit skeletal/morph usage flags. `import_expanded_bodies.py` imports both bodies, authored gender-specific normal/roughness maps and female albedo, then verifies all LOD material references. Missing morph material usage was the cause of the gray default-material fallback when applying customization.

Endpoint tests cover each channel independently and the combined positive endpoints. Zero triangle orientation flips were found in those final checks. The full space of mixed extreme values is not exhaustively validated. Female run frames6/16/40 were rendered and inspected in Blender; in-engine QA remains necessary. This is a bounded shape system, not arbitrary skeleton editing or unlimited anatomical sculpting.

The later body-volume pass uses smooth outward saturation instead of a hard lateral cutoff, avoiding folded upper-arm faces at large values. Female BodyFat at 70% expands sampled waist width from28.3cm to38.5cm and depth20.7cm to30.4cm; at100%,42.9cm wide and34.6cm deep. Two near-collinear authored elbow vertices were dissolved and locally retriangulated to remove unstable sliver triangles. Individual and combined positive morph endpoint checks then passed on both meshes. See `bodyfat-validation.json` and `female-fat-*.jpg`.

Neck QA correction: coincident UV seam vertices in the local neck smoothing region must be welded before smoothing; otherwise they separate into a visible gap. The generator now welds only skin vertices within x±7cm, z135–155cm while preserving per-loop UVs. This avoids welding intentional lip contacts. Close-up renders confirm the neck opening is gone. All facial offsets fade to zero at/below z152cm. EyeSize and EyeSpacing affect all556 eyeball vertices as well as the surrounding face; positive/negative endpoint close-ups were inspected. Evidence: `female-neck-inspect.jpg`, `eyes-validation.json`, and `EyeSize/EyeSpacing-*.jpg`.

## Orc proportion correction

Frame and muscle no longer stack large chest/back inflation. Frame depth strength changed .55 to .14; muscle torso depth .25 to .10. Muscle and frame now add radial volume around the unchanged upper-arm, forearm, thigh and calf axes, with smooth joint, armpit and groin falloffs. Orc defaults/ranges in `FableAppearancePresets.h` are balanced around these shapes. No bones or rig attachments changed.

`validate_orc_proportions.py` checks both genders at neutral, Orc defaults, and combined upper Orc limits. All passed triangle-orientation checks. Corrected arm measurement tracks the same neutral vertices around their transformed centroid: male mean cross-section radius6.72→8.32cm at default and8.60cm upper; female4.18→5.21cm and5.36cm. Default chest depth increases13% male and10% female. Front/side renders, run frames16/40, and Human Muscle=1 renders were inspected. Individual morph endpoints and combined positive endpoints passed; the combined test excludes hidden FemaleBody, which runtime does not apply on either active gender mesh.

## Dwarf head proportions

`HeadSize` is the26th morph, 0..1. At full strength it scales the head30% about body-space(0,0,154cm), using smoothstep((z-150)/7) to blend through the neck. It includes eyes and eyebrows. Female uses full strength for this channel, unlike its .8 multiplier on other shapes. Dwarf default .67 produces20.1% enlargement; allowed dwarf range.40–1. Other races default0. Hair alignment uses the same pivot and uniform1+.30*value scaling above z157cm. The tunic edge remains inside its existing clearance, so no clothing update was needed.

`validate_dwarf_head.py` renders male/female dwarf presets before, at default, and at maximum head size from front and side. All tested combined presets and independent/combined morph endpoints passed triangle checks. Halfling height policy changed to .82–.94, with defaults .88 male/.85 female; dwarf height is unchanged.

### Female front underwear seam correction
The deep vertical front groove was present in the authored rest geometry, including
with the normal texture disabled. Coincident UV seam vertices also produced a hard
shading seam. `create_female.py` now welds only coincident local groin vertices
(0.0001 cm tolerance, preserving per-loop UVs), then moves the narrow recessed
front strip onto the surrounding fabric surface before generating all morphs.
The correction peaks at 1.8 cm, falls off within 1.4 cm of the centerline and
z=82..100 cm, and excludes the posterior. Skeleton and skin weights are unchanged.

`validate_female_groin.py` checks front/side rest and running frames 16/40 at
BodyFat 0 and .7. All 26 morph endpoints and the combined positive endpoint
passed triangle orientation/area validation. Textured before/after evidence:
`groin-material-before-normal1.jpg` and `groin-material-narrow-normal1.jpg`.
Female-only Unreal reimport is `Tools/Unreal/import_female_body.py`; it retains
M_FemaleSkin_V2 and verifies all morphs, 89 shared bones, and section slots 0/1/2.

Live idle follow-up showed a remaining shallow ridge even with flat material
normals and zero BodyFat/Muscle. The generator now additionally fits the central
2 cm half-width strip to a weighted local quadratic surface using neighboring
front vertices (2–6 cm from center). This removes the alternating ridge/recess
left by the first offset, with a smooth vertical fade over z=88..112 cm.
Endpoint and run checks were repeated successfully after this correction.
Female FBX import now enables MikkTSpace tangent recomputation to match the
Blender-authored tangent-space material. The diagnostic flat-normal material was
removed and the original female normal texture restored.

### Male shoulder deformation correction
Creator plays MM_Idle directly; gameplay uses ABP_Unarmed with locomotion and
FootIK. The raised, detached-looking male deltoid cap reproduces in locomotion
without ControlRig. Removing twist influence alone did not fix it. The final
`shoulder_weights.py` correction keeps the cap more clavicle-driven, with a smooth
falloff along the upper-arm axis so the rest of the arm still swings normally.
It adjusts 518 vertices, normalizes weights to at most eight influences, and
changes no rest positions, UVs, topology, skeleton, or shape-key coordinates.
Female source/assets are unchanged.

Validation includes both strides in the original running source and exported
MM_Jump, MF_Unarmed_Walk_Fwd, and MF_Unarmed_Jog_Right at Muscle=1, frames 6/16/30.
`Tools/Unreal/export_shoulder_validation.py` refreshes the animation FBXs;
`validate_shoulders.py` renders the saved male source against them. Before/after
images use `shoulder-original-*` and `shoulder-validated-*`. Existing clay-lighting
facets and extreme-pose lower-body issues are present in the original comparison;
this correction is limited to shoulders. `shoulder-validation.json` confirms zero
rest-position change, normalized weights, 26 morphs, 88 Blender deform bones plus
the exported armature root (89 Unreal bones). All morph endpoint checks pass.
