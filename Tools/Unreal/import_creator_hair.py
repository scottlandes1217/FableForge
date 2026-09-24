import unreal,json,shutil
from pathlib import Path
root=Path(unreal.Paths.project_dir()).resolve();src=root/'ArtSource/Characters/Hair';pack=Path('/Users/scottlandes/Downloads/Universal Base Characters[Standard]');dest='/Game/Characters/PlayableCharacter/Hair';lib=unreal.MaterialEditingLibrary
unreal.SystemLibrary.execute_console_command(None,'Interchange.FeatureFlags.Import.FBX 0')
shutil.copy2(pack/'License_Standard.txt',src/'LICENSE-Quaternius-CC0.txt')
spec=json.loads((src/'alignment.json').read_text());tasks=[]
if (src/'alignment-female.json').exists():spec['styles'].update(json.loads((src/'alignment-female.json').read_text())['styles'])
for name in spec['styles']:
 t=unreal.AssetImportTask();t.filename=str(src/(name+'.fbx'));t.destination_path=dest;t.destination_name='SM_'+name;t.automated=True;t.replace_existing=True;t.save=True
 opt=unreal.FbxImportUI();opt.import_mesh=True;opt.import_as_skeletal=False;opt.import_materials=False;opt.import_textures=False;opt.mesh_type_to_import=unreal.FBXImportType.FBXIT_STATIC_MESH;opt.static_mesh_import_data.combine_meshes=True;opt.static_mesh_import_data.auto_generate_collision=False;opt.static_mesh_import_data.normal_import_method=unreal.FBXNormalImportMethod.FBXNIM_IMPORT_NORMALS_AND_TANGENTS;t.options=opt;tasks.append(t)
for i in [1,2]:
 for typ in ['BaseColor','Normal']:
  t=unreal.AssetImportTask();t.filename=str(pack/'Hairstyles/Textures'/f'T_Hair_{i}_{typ}.png');t.destination_path=dest;t.automated=True;t.replace_existing=True;t.save=True;tasks.append(t)
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks(tasks)
materials={}
for i in [1,2]:
 name=f'M_CreatorHair_{i}';m=unreal.load_asset(dest+'/'+name) or unreal.AssetToolsHelpers.get_asset_tools().create_asset(name,dest,unreal.Material,unreal.MaterialFactoryNew());lib.delete_all_material_expressions(m);m.set_editor_property('two_sided',True)
 tex=lib.create_material_expression(m,unreal.MaterialExpressionTextureSample);tex.texture=unreal.load_asset(dest+f'/T_Hair_{i}_BaseColor')
 tint=lib.create_material_expression(m,unreal.MaterialExpressionVectorParameter);tint.set_editor_property('parameter_name','HairTint');tint.set_editor_property('default_value',unreal.LinearColor(.24,.12,.045,1))
 mul=lib.create_material_expression(m,unreal.MaterialExpressionMultiply);lib.connect_material_expressions(tex,'RGB',mul,'A');lib.connect_material_expressions(tint,'',mul,'B');lib.connect_material_property(mul,'',unreal.MaterialProperty.MP_BASE_COLOR)
 norm=lib.create_material_expression(m,unreal.MaterialExpressionTextureSample);norm.texture=unreal.load_asset(dest+f'/T_Hair_{i}_Normal');norm.sampler_type=unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL;lib.connect_material_property(norm,'RGB',unreal.MaterialProperty.MP_NORMAL)
 for value,prop in [(.68,unreal.MaterialProperty.MP_ROUGHNESS),(.2,unreal.MaterialProperty.MP_SPECULAR)]:
  c=lib.create_material_expression(m,unreal.MaterialExpressionConstant);c.r=value;lib.connect_material_property(c,'',prop)
 lib.recompile_material(m);unreal.EditorAssetLibrary.save_loaded_asset(m);materials[i]=m
for name,s in spec['styles'].items():
 mesh=unreal.load_asset(dest+'/SM_'+name)
 for i in range(len(mesh.static_materials)):mesh.set_material(i,materials[s['texture']])
 unreal.EditorAssetLibrary.save_loaded_asset(mesh)
unreal.log('CREATOR_HAIR_IMPORTED '+str(list(spec['styles'])));unreal.SystemLibrary.quit_editor()
