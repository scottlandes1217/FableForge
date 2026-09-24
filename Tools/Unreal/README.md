# Local asset tooling

The project enables Epic's bundled **Python Editor Script Plugin** and **Editor Scripting Utilities** for editor targets. No remote execution server is enabled. Restart an already-open Unreal Editor to load these plugins.

Run the read-only asset audit on this Mac:

```sh
'/Users/Shared/Epic Games/UE_5.7/Engine/Binaries/Mac/UnrealEditor.app/Contents/MacOS/UnrealEditor' \
  '/Users/scottlandes/Projects/FableForge/FableForge.uproject' \
  -run=pythonscript \
  -script='/Users/scottlandes/Projects/FableForge/Tools/Unreal/audit_project.py' \
  -unattended -nullrhi
```

The report is written to `Saved/OverhaulAssetAudit.json`. It lists asset counts and the item table without changing assets.

Blender 5.0.1 is installed at `/Applications/Blender.app`. Its built-in Python interface was verified with:

```sh
'/Applications/Blender.app/Contents/MacOS/Blender' --background --factory-startup \
  --python-expr 'import bpy; print(bpy.app.version_string)'
```

For mesh work, use a script via `--python path/to/script.py`, save source `.blend` files under `ArtSource`, and export/import only the intended assets. Do not overwrite source assets during an audit.
