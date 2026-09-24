# Fitted linen tunic

New sibling replacement for the peasant chest item. The original shirt and base character assets are preserved.

`create_tunic.py` creates a short-sleeved fitted shell from the repaired body's skin topology, cuts an open neckline/hem/cuffs, welds duplicate seam vertices, retains the body's skin weights, adds 1.1 cm clearance and 1.8 mm fabric thickness, and exports the unchanged 89-bone skeleton. `FittedTunic.blend` retains the imported jog animation for inspection. `Tools/Unreal/import_fitted_tunic.py` imports the sibling asset, creates matte dark teal linen and dark trim materials, verifies bone names against the playable body, and assigns `peasant_chest` to the new mesh.

Unreal mesh: `/Game/Items/Armor/FittedTunic/peasant_tunic_v2`

Validation: Unreal import succeeded; 89 bone names match. Blender workbench renders at jog frames 1, 6, and 16 show the fitted silhouette without visible torso/shoulder skin breakthrough in these views. These images are geometry diagnostics, not Unreal material screenshots. Unreal gameplay animation still requires verification. The original body Control Rig hierarchy warnings remain outside this clothing change.

The tunic includes BodyBuild, ShoulderWidth, WaistWidth, and HipWidth morphs from the shared BodyV2/morph_contract.py. Unreal import confirmed all four names. Combined maximum morphs were visually checked at jog frames 6 and 16 in Blender (run-maxmorph images) without visible torso/shoulder breakthrough in those views. Runtime code must set the same weights on the body and equipment mesh. Future morphs need equivalent clothing shape keys.

Material audit: tunic LOD0 sections map to [0,1], with explicit Linen_Ochre (retained asset name, now dark teal) and Woven_Trim assignments. Fixed Blender material clearing that had removed the trim face assignments. Audited bounds z101.78..152.48cm against body z-0.94..177.33cm; both root transforms are identity and have 89 bones. See material-bounds-audit.json.

Expanded creator: shared 25-channel contract regenerated for clothing. Unreal retained 13 nonzero tunic channels (including FemaleBody, BodyFat, Muscle, Bust, TorsoLength and face channels that affect the neckline). FemaleBody=1, Bust=.2, BodyFat=.2 inspected at jog frames 6/16; run-female images show the geometry diagnostics. Cloth materials now explicitly support morph targets.

Authored female: run generator with `-- --female` to derive `female_tunic_v2` from the female body topology and matching shared rig. Import with `FABLE_FEMALE_TUNIC=1`; this leaves the common armor DataTable unchanged, and runtime selects the female variant for female characters. Authored-female jog frames 6/16 confirm movement in Blender; a small central neckline/chest crease remains visible and the diagnostic is not a comprehensive clipping guarantee.

Final authored female source incorporates the sternum smoothing fix; regenerated clothing and updated jog renders remove the previously visible neckline slit in the inspected views. Female clothing uses the same 0.8 morph amplitude as the authored female body; male clothing uses 1.0. Shared torso offsets include the final elbow masks.

Latest contract validation: both tunics regenerated and reimported after the final female neck seam weld, stronger body controls, and head-only facial masks. Both now retain exactly nine body morphs (face changes no longer deform collars). Female BodyFat=.7 plus BodyBuild=.3 were checked at jog frames 6/16; see authored-female-heavy images.

Balanced torso/limb contract: both tunics regenerated after the final smooth radial muscle falloff update. Unreal audit confirms matching 89-bone skeletons, two valid material sections and nine body morphs each. Blender orc-default jog frames 6/16 inspected for both sexes; see orc-male/female images and final-limb-contract-audit.json. No visible clipping in those inspected views; this is not all-animation coverage.
