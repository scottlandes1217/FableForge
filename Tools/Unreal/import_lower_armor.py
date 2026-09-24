import unreal,json,os
project=unreal.Paths.convert_relative_path_to_full(unreal.Paths.project_dir());root=project+'ArtSource/Characters/FittedLowerArmor/'
unreal.SystemLibrary.execute_console_command(None,'Interchange.FeatureFlags.Import.FBX 0')
body=unreal.load_asset('/Game/Characters/PlayableCharacter/Meshes/basecharacter_v2');skeleton=body.skeleton
material=unreal.load_asset('/Game/Items/Armor/Materials/MI_Peasant');assert material
base=material.get_base_material();base.set_editor_property('used_with_skeletal_mesh',True);base.set_editor_property('used_with_morph_targets',True);unreal.MaterialEditingLibrary.recompile_material(base);unreal.EditorAssetLibrary.save_loaded_asset(base)
lining=unreal.load_asset('/Game/Items/Armor/FittedLowerArmor/Boot_Leather_Lining')
if not lining:
 lining=unreal.AssetToolsHelpers.get_asset_tools().create_asset('Boot_Leather_Lining','/Game/Items/Armor/FittedLowerArmor',unreal.Material,unreal.MaterialFactoryNew())
 lining.set_editor_property('used_with_skeletal_mesh',True);lining.set_editor_property('used_with_morph_targets',True)
 color=unreal.MaterialEditingLibrary.create_material_expression(lining,unreal.MaterialExpressionConstant3Vector);color.constant=unreal.LinearColor(.055,.026,.012,1);unreal.MaterialEditingLibrary.connect_material_property(color,'',unreal.MaterialProperty.MP_BASE_COLOR)
 rough=unreal.MaterialEditingLibrary.create_material_expression(lining,unreal.MaterialExpressionConstant);rough.r=.85;unreal.MaterialEditingLibrary.connect_material_property(rough,'',unreal.MaterialProperty.MP_ROUGHNESS)
 unreal.MaterialEditingLibrary.recompile_material(lining);unreal.EditorAssetLibrary.save_loaded_asset(lining)
# Dedicated rough surfaces avoid sampling body UVs through the outfit atlas on
# the fitted lining. Both shell and lining use the same surface per garment.
def surface(name, color, roughness):
 path='/Game/Items/Armor/FittedLowerArmor'
 mat=unreal.load_asset(path+'/'+name)
 if not mat: mat=unreal.AssetToolsHelpers.get_asset_tools().create_asset(name,path,unreal.Material,unreal.MaterialFactoryNew())
 mat.set_editor_property('used_with_skeletal_mesh',True)
 mat.set_editor_property('used_with_morph_targets',True)
 unreal.MaterialEditingLibrary.delete_all_material_expressions(mat)
 col=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionConstant3Vector)
 col.constant=unreal.LinearColor(*color,1)
 unreal.MaterialEditingLibrary.connect_material_property(col,'',unreal.MaterialProperty.MP_BASE_COLOR)
 r=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionConstant);r.r=roughness
 unreal.MaterialEditingLibrary.connect_material_property(r,'',unreal.MaterialProperty.MP_ROUGHNESS)
 unreal.MaterialEditingLibrary.recompile_material(mat)
 unreal.EditorAssetLibrary.save_loaded_asset(mat)
 return mat
cloth_surface=surface('M_FittedTrouserCloth',(.055,.035,.022),.93)
boot_surface=surface('M_FittedBootLeather',(.035,.020,.012),.78)
report=[]
for gender in ['male','female']:
 for part in ['legs','feet']:
  asset=gender+'_peasant_'+part+'_v2';opts=unreal.FbxImportUI()
  for key,value in [('import_as_skeletal',True),('mesh_type_to_import',unreal.FBXImportType.FBXIT_SKELETAL_MESH),('import_mesh',True),('import_animations',False),('import_materials',False),('import_textures',False),('create_physics_asset',False),('skeleton',skeleton)]:opts.set_editor_property(key,value)
  opts.skeletal_mesh_import_data.set_editor_property('import_morph_targets',True);opts.skeletal_mesh_import_data.set_editor_property('normal_import_method',unreal.FBXNormalImportMethod.FBXNIM_IMPORT_NORMALS_AND_TANGENTS)
  task=unreal.AssetImportTask();task.filename=root+asset+'.fbx';task.destination_path='/Game/Items/Armor/FittedLowerArmor';task.destination_name=asset;task.automated=True;task.replace_existing=True;task.save=True;task.options=opts;task.factory=unreal.FbxFactory()
  unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([task]);mesh=unreal.load_asset(task.destination_path+'/'+asset);assert mesh
  slots=list(mesh.materials)
  for i,slot in enumerate(slots):slot.material_interface=cloth_surface if part=='legs' else boot_surface
  mesh.materials=slots;unreal.EditorAssetLibrary.save_loaded_asset(mesh,False)
  c=unreal.SkeletalMeshComponent();c.set_skinned_asset_and_update(mesh);b=unreal.SkeletalMeshComponent();b.set_skinned_asset_and_update(body)
  assert mesh.skeleton==skeleton
  assert [str(c.get_bone_name(i)) for i in range(c.get_num_bones())]==[str(b.get_bone_name(i)) for i in range(b.get_num_bones())]
  assert mesh.get_editor_property('morph_targets')
  report.append(dict(asset=mesh.get_path_name(),bones=c.get_num_bones(),materials=[s.material_interface.get_path_name() for s in slots],morphs=[m.get_name() for m in mesh.get_editor_property('morph_targets')]))
dt=unreal.load_asset('/Game/Data/DT_Armor');raw=unreal.DataTableFunctionLibrary.export_data_table_to_json_string(dt)
if not os.path.exists(root+'DT_Armor_before.json'):open(root+'DT_Armor_before.json','w').write(raw)
rows=json.loads(raw)
for row in rows:
 if row['Name'] in ['peasant_legs','peasant_feet']:
  asset='male_'+row['Name']+'_v2';row['WorldSkeletalMesh']='/Game/Items/Armor/FittedLowerArmor/'+asset+'.'+asset;row['DisplayName']='Linen Trousers' if row['Name']=='peasant_legs' else 'Leather Boots'
assert unreal.DataTableFunctionLibrary.fill_data_table_from_json_string(dt,json.dumps(rows));unreal.EditorAssetLibrary.save_loaded_asset(dt)
open(root+'import-validation.json','w').write(json.dumps(report,indent=2));print('LOWER_ARMOR_IMPORTED',report)
