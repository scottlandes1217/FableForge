# Item model icons

Run Blender in background mode with `Tools/Blender/render_item_icons.py` from this project. It renders the actual source meshes into 512×512 RGBA PNGs in `Content/Slate/ItemIcons`, using transparent film, studio lighting, and matching lower armor materials. Set `ICON_ONLY` to one item ID to regenerate only that icon.

Do not color-key dark pixels: cloth, leather, and blade details overlap the old thumbnail checkerboard colors. The old Unreal thumbnail exporter is a diagnostic export with an opaque checkerboard; it must not overwrite the production transparent icons.

Runtime caches icons per process. Restart the preview after regeneration. These offline images create no additional runtime 3D scenes.
