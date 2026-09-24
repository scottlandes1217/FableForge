"""Import authored reusable item meshes and fill missing item mesh references."""
import unreal, json
from pathlib import Path
unreal.SystemLibrary.execute_console_command(None, 'Interchange.FeatureFlags.Import.FBX 0')
root=Path(unreal.Paths.project_dir()).resolve()
items=['health_potion','mana_potion','wood','stone','iron_ore','meat','honey','berries']
tasks=[]
for item in items:
 task=unreal.AssetImportTask();task.filename=str(root/'ArtSource/ItemProps'/(item+'.fbx'));task.destination_path='/Game/Items/GeneratedProps';task.destination_name='SM_'+item;task.automated=True;task.save=True;task.replace_existing=True
 options=unreal.FbxImportUI();options.import_mesh=True;options.import_materials=True;options.import_textures=False;options.import_as_skeletal=False;options.mesh_type_to_import=unreal.FBXImportType.FBXIT_STATIC_MESH
 options.static_mesh_import_data.normal_import_method=unreal.FBXNormalImportMethod.FBXNIM_IMPORT_NORMALS_AND_TANGENTS;options.static_mesh_import_data.combine_meshes=True;options.static_mesh_import_data.auto_generate_collision=True;task.options=options;tasks.append(task)
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks(tasks)
table=unreal.load_asset('/Game/Data/DT_Items')
original=unreal.DataTableFunctionLibrary.export_data_table_to_json_string(table)
backup=root/'Saved/OverhaulBackups/DT_Items_before_generated_props.json';backup.parent.mkdir(parents=True,exist_ok=True)
if not backup.exists():backup.write_text(original)
rows=json.loads(original); changed=[]
for row in rows:
 item=row.get('ItemId',row.get('Name','')).lower()
 if item in items:
  path='/Game/Items/GeneratedProps/SM_'+item
  mesh=unreal.load_asset(path)
  if not mesh:raise RuntimeError('Missing imported mesh '+path)
  row['WorldStaticMesh']=mesh.get_path_name();changed.append(item)
if len(changed)!=8:raise RuntimeError('Unexpected coverage: '+str(changed))
if not unreal.DataTableFunctionLibrary.fill_data_table_from_json_string(table,json.dumps(rows)):raise RuntimeError('Table update failed')
unreal.EditorAssetLibrary.save_loaded_asset(table)
unreal.log('GENERATED_ITEM_PROPS_SUCCESS '+str(changed))

exec(compile((root/'Tools/Unreal/materialize_generated_item_props.py').read_text(),str(root/'Tools/Unreal/materialize_generated_item_props.py'),'exec'))
