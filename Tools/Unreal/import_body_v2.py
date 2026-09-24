import unreal,json,os,sys
project=unreal.Paths.convert_relative_path_to_full(unreal.Paths.project_dir());root=project+'ArtSource/Characters/BodyV2/';sys.path.insert(0,root)
from morph_contract import MORPH_NAMES
unreal.SystemLibrary.execute_console_command(None,'Interchange.FeatureFlags.Import.FBX 0')
base=unreal.load_asset('/Game/Characters/PlayableCharacter/Meshes/basecharacter')
opts=unreal.FbxImportUI()
for p,v in [('import_as_skeletal',True),('mesh_type_to_import',unreal.FBXImportType.FBXIT_SKELETAL_MESH),('import_mesh',True),('import_animations',False),('import_materials',False),('import_textures',False),('create_physics_asset',False),('skeleton',base.skeleton)]:opts.set_editor_property(p,v)
opts.skeletal_mesh_import_data.set_editor_property('import_morph_targets',True)
opts.skeletal_mesh_import_data.set_editor_property('normal_import_method',unreal.FBXNormalImportMethod.FBXNIM_IMPORT_NORMALS_AND_TANGENTS)
t=unreal.AssetImportTask();t.filename=root+'basecharacter_v2.fbx';t.destination_path='/Game/Characters/PlayableCharacter/Meshes';t.destination_name='basecharacter_v2';t.automated=True;t.replace_existing=True;t.save=True;t.options=opts;t.factory=unreal.FbxFactory()
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([t]);mesh=unreal.load_asset('/Game/Characters/PlayableCharacter/Meshes/basecharacter_v2');assert mesh
slots=base.get_editor_property('materials')
for index,name in enumerate(['M_BodyHair_V2','M_BodyEyes_V2','M_BodySkin_V2']):
 material=unreal.load_asset('/Game/Characters/PlayableCharacter/Materials/'+name)
 if material:
  slot=slots[index];slot.material_interface=material;slots[index]=slot
mesh.set_editor_property('materials',slots);mesh.set_editor_property('physics_asset',base.get_editor_property('physics_asset'))
a=unreal.SkeletalMeshComponent();a.set_skinned_asset_and_update(mesh);b=unreal.SkeletalMeshComponent();b.set_skinned_asset_and_update(base)
assert [str(a.get_bone_name(i)) for i in range(a.get_num_bones())]==[str(b.get_bone_name(i)) for i in range(b.get_num_bones())]
names=[m.get_name() for m in mesh.get_editor_property('morph_targets')]
expected=list(MORPH_NAMES);assert all(n in names for n in expected),names
unreal.EditorAssetLibrary.save_loaded_asset(mesh)
sub=unreal.get_editor_subsystem(unreal.SkeletalMeshEditorSubsystem)
sections=[sub.get_lod_material_slot(mesh,0,i) for i in range(sub.get_num_sections(mesh,0))]
assert sections==[0,1,2],sections
open(root+'import-validation.json','w').write(json.dumps({'mesh':mesh.get_path_name(),'bones':a.get_num_bones(),'section_material_indices':sections,'skeleton':mesh.skeleton.get_path_name(),'morphs':names,'materials':[str(m.material_interface) for m in mesh.materials]},indent=2))
print('BODY_V2_IMPORTED',names)
