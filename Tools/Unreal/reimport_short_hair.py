"""Update only the four fitted short hair caps; preserve other hairstyles/materials."""
import unreal,json
from pathlib import Path
root=Path(unreal.Paths.project_dir()).resolve();source=root/'ArtSource/Characters/Hair';dest='/Game/Characters/PlayableCharacter/Hair'
unreal.SystemLibrary.execute_console_command(None,'Interchange.FeatureFlags.Import.FBX 0')
names=['Hair_Buzzed','Hair_BuzzedFemale','Female_Hair_Buzzed','Female_Hair_BuzzedFemale'];tasks=[]
for name in names:
 t=unreal.AssetImportTask();t.filename=str(source/(name+'.fbx'));t.destination_path=dest;t.destination_name='SM_'+name;t.automated=True;t.replace_existing=True;t.save=True
 opt=unreal.FbxImportUI();opt.import_mesh=True;opt.import_as_skeletal=False;opt.import_materials=False;opt.import_textures=False;opt.mesh_type_to_import=unreal.FBXImportType.FBXIT_STATIC_MESH;opt.static_mesh_import_data.combine_meshes=True;opt.static_mesh_import_data.auto_generate_collision=False;opt.static_mesh_import_data.normal_import_method=unreal.FBXNormalImportMethod.FBXNIM_IMPORT_NORMALS_AND_TANGENTS;t.options=opt;tasks.append(t)
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks(tasks)
mat=unreal.load_asset(dest+'/M_CreatorHair_1');assert mat
for name in names:
 mesh=unreal.load_asset(dest+'/SM_'+name);assert mesh
 for i in range(len(mesh.static_materials)):mesh.set_material(i,mat)
 unreal.EditorAssetLibrary.save_loaded_asset(mesh)
unreal.log('SHORT_HAIR_CLEARANCE_IMPORT_SUCCESS '+str(names));unreal.SystemLibrary.quit_editor()
