import unreal,json,os,shutil
project=unreal.Paths.convert_relative_path_to_full(unreal.Paths.project_dir())
root=project+'ArtSource/Characters/FittedTunic/'
female=os.environ.get('FABLE_FEMALE_TUNIC')=='1'
asset='female_tunic_v2' if female else 'peasant_tunic_v2'
unreal.SystemLibrary.execute_console_command(None,'Interchange.FeatureFlags.Import.FBX 0')
body=unreal.load_asset('/Game/Characters/PlayableCharacter/Meshes/basecharacter')
opts=unreal.FbxImportUI()
for p,v in [('import_as_skeletal',True),('mesh_type_to_import',unreal.FBXImportType.FBXIT_SKELETAL_MESH),('import_mesh',True),('import_animations',False),('import_materials',True),('import_textures',False),('create_physics_asset',False),('skeleton',body.get_editor_property('skeleton'))]:opts.set_editor_property(p,v)
opts.skeletal_mesh_import_data.set_editor_property('import_morph_targets',True)
opts.skeletal_mesh_import_data.set_editor_property('normal_import_method',unreal.FBXNormalImportMethod.FBXNIM_IMPORT_NORMALS_AND_TANGENTS)
existing=unreal.load_asset('/Game/Items/Armor/FittedTunic/'+asset)
if existing: existing.get_editor_property('asset_import_data').set_editor_property('import_morph_targets',True)
t=unreal.AssetImportTask();t.filename=root+asset+'.fbx';t.destination_path='/Game/Items/Armor/FittedTunic';t.destination_name=asset;t.automated=True;t.replace_existing=True;t.save=True;t.options=opts;t.factory=unreal.FbxFactory()
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([t])
mesh=unreal.load_asset('/Game/Items/Armor/FittedTunic/'+asset);assert mesh
c=unreal.SkeletalMeshComponent();c.set_skinned_asset_and_update(mesh)
b=unreal.SkeletalMeshComponent();b.set_skinned_asset_and_update(body)
assert [str(c.get_bone_name(i)) for i in range(c.get_num_bones())]==[str(b.get_bone_name(i)) for i in range(b.get_num_bones())]
slots=list(mesh.get_editor_property('materials'))
for index,slot in enumerate(slots):
 name='Linen_Ochre' if index==0 else 'Woven_Trim'
 mat=unreal.load_asset('/Game/Items/Armor/FittedTunic/'+name)
 if not mat: mat=unreal.AssetToolsHelpers.get_asset_tools().create_asset(name,'/Game/Items/Armor/FittedTunic',unreal.Material,unreal.MaterialFactoryNew())
 slot.material_interface=mat
mesh.set_editor_property('materials',slots)
unreal.EditorAssetLibrary.save_loaded_asset(mesh)
for slot in mesh.get_editor_property('materials'):
 mat=slot.material_interface
 if isinstance(mat,unreal.Material):
  mat.set_editor_property('used_with_skeletal_mesh',True)
  mat.set_editor_property('used_with_morph_targets',True)
  unreal.MaterialEditingLibrary.delete_all_material_expressions(mat)
  col=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector)
  col.constant=unreal.LinearColor(.035,.065,.075,1) if 'Linen' in mat.get_name() else unreal.LinearColor(.07,.03,.011,1)
  unreal.MaterialEditingLibrary.connect_material_property(col,'',unreal.MaterialProperty.MP_BASE_COLOR)
  rough=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionConstant);rough.r=.92
  unreal.MaterialEditingLibrary.connect_material_property(rough,'',unreal.MaterialProperty.MP_ROUGHNESS)
  unreal.MaterialEditingLibrary.recompile_material(mat);unreal.EditorAssetLibrary.save_loaded_asset(mat)
if not female:
 dt=unreal.load_asset('/Game/Data/DT_Armor')
 raw=unreal.DataTableFunctionLibrary.export_data_table_to_json_string(dt)
 if not os.path.exists(root+'DT_Armor_before.json'): open(root+'DT_Armor_before.json','w').write(raw)
 rows=json.loads(raw)
 for row in rows:
  if row['Name']=='peasant_chest':
   row['WorldSkeletalMesh']=mesh.get_path_name();row['DisplayName']='Linen Tunic'
 assert unreal.DataTableFunctionLibrary.fill_data_table_from_json_string(dt,json.dumps(rows))
 unreal.EditorAssetLibrary.save_loaded_asset(dt)
open(root+('female-import-validation.json' if female else 'import-validation.json'),'w').write(json.dumps({'mesh':mesh.get_path_name(),'bones':c.get_num_bones(),'skeleton':mesh.skeleton.get_path_name(),'datatable_updated':not female,'morphs':[str(m.get_name()) for m in mesh.get_editor_property('morph_targets')]},indent=2))
print('FITTED_TUNIC_IMPORTED')
