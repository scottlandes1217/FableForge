# Character and shirt repair

The two FBX files are the reimport sources for the existing `basecharacter` and `shirt` Unreal assets. `FableForge_Character_Clothing_Repair.blend` contains the repaired meshes and an imported running animation for preview.

## Changes

- Smoothed the body's existing weight transitions around the shoulders/arms and hips. Body vertex positions were not changed.
- Transferred the repaired body's weights to the shirt using the nearest body triangle and interpolated vertex weights.
- Added 1.5 cm of shirt clearance along the nearest body-surface normal.
- Normalized weights with at most eight influences per vertex.
- Retained the original Unreal skeletons, materials, and physics assets.

## Verification

Sampled 19 frames of the exported run cycle in Blender. The number of measured edges exceeding three times their rest length fell from 42 to 5 in the arms and from 21 to 1 in the hips. These measurements indicate reduced deformation; they do not imply zero stretching in every animation.

Imported and rendered the original and repaired meshes in Unreal at 0.25 and 0.65 seconds of `MF_Unarmed_Jog_Fwd`. Both meshes retain the original 89-bone hierarchy and reference transforms. The comparison images in `Validation` show the original on the left and the repair on the right. A temporary white shirt material was used to expose clipping; the saved game asset retains its original material.

This validation covered the running animation, not a complete gameplay regression pass. The concurrent game-source changes are outside this asset repair.

Original Unreal assets and exported originals are backed up at `Saved/ClothingRepairBackup/20260920-180547`.
