"""Read-only asset audit. Run with UnrealEditor -run=pythonscript -script=<this file>."""
import json
from pathlib import Path
import unreal

registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.search_all_assets(True)
assets = registry.get_assets_by_path('/Game', recursive=True)
counts = {}
for asset in assets:
    kind = str(asset.asset_class_path.asset_name)
    counts[kind] = counts.get(kind, 0) + 1
report = {
    'asset_counts': dict(sorted(counts.items())),
    'python_ready': True,
    'editor_scripting_ready': hasattr(unreal, 'EditorAssetLibrary'),
    'items': [],
}
table = unreal.load_asset('/Game/Data/DT_Items')
if table:
    report['items'] = json.loads(unreal.DataTableFunctionLibrary.export_data_table_to_json_string(table))
output = Path(unreal.Paths.project_saved_dir()) / 'OverhaulAssetAudit.json'
output.parent.mkdir(parents=True, exist_ok=True)
output.write_text(json.dumps(report, indent=2))
unreal.log('FABLEFORGE_SCRIPTING_READY: audit written to ' + str(output))
