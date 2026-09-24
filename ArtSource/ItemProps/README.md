# Generated medieval item props

Eight reusable static meshes authored for FableForge: health and mana flasks, bound firewood, river stone, iron ore, venison joint, honey crock, and berries. Blender source scenes and FBX exports are retained here. They use solid geometry and separately named material slots, with dimensions appropriate for handheld pickups (roughly 10–35 cm).

`build_props.py` regenerates the geometry with Blender 5.0.1. `materials.json` captures the base colors, roughness and metalness for equivalent Unreal materials.

Run `Tools/Unreal/import_generated_item_props.py` via the editor `-ExecutePythonScript` option (not a Python commandlet: UE5.7 AssetTools requires Slate while saving imported assets). The import script then runs `materialize_generated_item_props.py` to create and assign explicit Unreal materials (that script can also be run independently). Import script preserves a JSON backup of DT_Items and fills only the eight matching WorldStaticMesh fields. Generated assets live under `/Game/Items/GeneratedProps`.

Run `Tools/Unreal/export_item_icons.sh` after import and material setup to render inventory images from the actual meshes.
