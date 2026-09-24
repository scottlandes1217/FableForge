import unreal,os
project=unreal.Paths.convert_relative_path_to_full(unreal.Paths.project_dir())
code=open(project+'Tools/Unreal/import_body_v2.py').read()
exec(compile(code,'import_body_v2.py','exec'))
exec(compile(code.replace('basecharacter_v2','femalecharacter_v2').replace('import-validation.json','female-import-validation.json'),'import_female_v2.py','exec'))
# Import the authored female albedo/normal/roughness, retaining original UVs.
source=project+'ArtSource/Characters/BodyV2/SourcePack/Textures/'
unreal.SystemLibrary.execute_console_command(None,'Interchange.FeatureFlags.Import.PNG 0')
tasks=[]
for suffix in ['Light_BaseColor','Normal','Roughness']:
 t=unreal.AssetImportTask();t.factory=unreal.TextureFactory();t.filename=source+'T_Superhero_Female_'+suffix+'.png';t.destination_path='/Game/Characters/PlayableCharacter/Textures/Female';t.automated=True;t.replace_existing=True;t.save=True;tasks.append(t)
unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks(tasks)
# Import the matching authored male normal/roughness maps too.
for suffix in ['Normal','Roughness']:
 t=unreal.AssetImportTask();t.factory=unreal.TextureFactory();t.filename=source+'T_Superhero_Male_'+suffix+'.png';t.destination_path='/Game/Characters/PlayableCharacter/Textures/Male';t.automated=True;t.replace_existing=True;t.save=True
 unreal.AssetToolsHelpers.get_asset_tools().import_asset_tasks([t])
helpers=open(project+'Tools/Unreal/create_body_materials.py').read().split("skin=material(")[0];exec(helpers)
female=material('M_FemaleSkin_V2','SkinTint','/Game/Characters/PlayableCharacter/Textures/Female/T_Superhero_Female_Light_BaseColor')
for sex,mat in [('Female',female),('Male',unreal.load_asset('/Game/Characters/PlayableCharacter/Materials/M_BodySkin_V2'))]:
 for suffix,prop in [('Normal',unreal.MaterialProperty.MP_NORMAL),('Roughness',unreal.MaterialProperty.MP_ROUGHNESS)]:
  tex=unreal.load_asset('/Game/Characters/PlayableCharacter/Textures/'+sex+'/T_Superhero_'+sex+'_'+suffix);assert tex
  tex.set_editor_property('srgb',False)
  if suffix=='Normal':tex.set_editor_property('compression_settings',unreal.TextureCompressionSettings.TC_NORMALMAP)
  unreal.EditorAssetLibrary.save_loaded_asset(tex)
  e=unreal.MaterialEditingLibrary.create_material_expression(mat,unreal.MaterialExpressionTextureSample);e.texture=tex
  e.set_editor_property('sampler_type',unreal.MaterialSamplerType.SAMPLERTYPE_NORMAL if suffix=='Normal' else unreal.MaterialSamplerType.SAMPLERTYPE_LINEAR_COLOR)
  unreal.MaterialEditingLibrary.connect_material_property(e,'RGB' if suffix=='Normal' else 'R',prop)
 unreal.MaterialEditingLibrary.recompile_material(mat);unreal.EditorAssetLibrary.save_loaded_asset(mat)
mesh=unreal.load_asset('/Game/Characters/PlayableCharacter/Meshes/femalecharacter_v2');slots=mesh.materials;slot=slots[2];slot.material_interface=female;slots[2]=slot;mesh.set_editor_property('materials',slots);unreal.EditorAssetLibrary.save_loaded_asset(mesh)
print('EXPANDED_BODIES_READY')
import json
report={};sub=unreal.get_editor_subsystem(unreal.SkeletalMeshEditorSubsystem)
for name in ['basecharacter_v2','femalecharacter_v2']:
 mesh=unreal.load_asset('/Game/Characters/PlayableCharacter/Meshes/'+name)
 lods=[[sub.get_lod_material_slot(mesh,lod,i) for i in range(sub.get_num_sections(mesh,lod))] for lod in range(sub.get_lod_count(mesh))]
 assert all(all(0<=i<len(mesh.materials) for i in indices) for indices in lods)
 materials=[]
 for slot in mesh.materials:
  mat=slot.material_interface;assert mat.get_editor_property('used_with_morph_targets')
  materials.append(mat.get_path_name())
 report[name]={'lod_sections':lods,'materials':materials,'morphs':[m.get_name() for m in mesh.morph_targets],'morph_usage_verified':True}
open(project+'ArtSource/Characters/BodyV2/expanded-import-validation.json','w').write(json.dumps(report,indent=2))
