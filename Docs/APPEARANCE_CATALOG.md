# Character appearance catalog

Edit `Content/Data/AppearanceStyles.json` to add hairstyles, beards, hair colors or eye colors. The creator and in-game attachment code read the same catalog. Restart the game/editor after editing: the catalog loads once per process.

## Adding a style

Add an object to `hairStyles` or `beardStyles`:

```json
{
  "id": "braided",
  "name": "Braided",
  "maleMesh": "/Game/Characters/PlayableCharacter/Hair/SM_Hair_Braided.SM_Hair_Braided",
  "femaleMesh": "/Game/Characters/PlayableCharacter/Hair/SM_Female_Hair_Braided.SM_Female_Hair_Braided"
}
```

This is a schema example, not an included hairstyle. Create/import the actual meshes before adding their entries. IDs must be unique lowercase letters, digits or underscores. Keep existing IDs stable: character saves retain them. The display name and list order may change freely. An empty mesh path makes a style unavailable for that body. Missing asset packages are also excluded from that body's selector with a warning; unavailable styles never silently use the other body's fit.

Keep one `none` entry in each style list with both mesh paths empty. It represents bald/no beard. Five modeled scalp styles and one beard are currently included, each fitted for both bodies.

Meshes must be static meshes authored in the corresponding body's reference component space; runtime attaches them to `head` while cancelling the head's reference transform. Preserve the UV/material setup, and expose the `HairTint` vector parameter on hair/beard materials. See `ArtSource/Characters/Hair/README.md` for the existing fit pipeline.

The Hair asset directory is already included in `DirectoriesToAlwaysCook`. If using another asset directory, add that directory to packaging settings: JSON paths alone do not cause assets to cook. The Data directory is staged as UFS so the JSON is available to packaged builds.

## Adding colors

Add `{ "id": "copper", "name": "Copper", "rgb": [0.5, 0.18, 0.06] }` to `hairColors` or `eyeColors`. RGB numbers use linear color values from 0 to 1. Actual RGB values are stored in character saves, so editing a preset does not change existing characters.

## Validation and fallback

The file requires `version: 1`, all four nonempty lists, unique IDs per list, nonempty display names, valid `/Game/...Asset.Asset` paths and finite RGB components in range. Invalid JSON/schema falls back as a whole to the built-in catalog. A missing file also uses built-ins. No mesh assets are synthesized by adding catalog entries.

C++ API lives in `FableAppearanceCatalog.h`, under `FableAppearanceAssets`: `ListHairStyles(Female)`, `ListBeardStyles(Female)`, `ListHairColors()` and `ListEyeColors()`. `StyleMeshPath` and `ConfigureStyle` keep their existing signatures and now resolve through the catalog.
