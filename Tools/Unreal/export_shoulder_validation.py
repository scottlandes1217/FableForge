import unreal,os
root=unreal.Paths.convert_relative_path_to_full(unreal.Paths.project_dir())+"ArtSource/Characters/BodyV2/ValidationAnimations/"
os.makedirs(root,exist_ok=True)
mesh=unreal.load_asset('/Game/Characters/PlayableCharacter/Meshes/basecharacter_v2')
for name,path in [('jump','Jump/MM_Jump'),('walk','Walk/MF_Unarmed_Walk_Fwd'),('jogright','Jog/MF_Unarmed_Jog_Right')]:
 a=unreal.load_asset('/Game/Characters/PlayableCharacter/Anims/Unarmed/'+path);assert a;a.set_preview_skeletal_mesh(mesh)
 t=unreal.AssetExportTask();t.object=a;t.filename=root+name+'.fbx';t.automated=True;t.prompt=False;t.replace_identical=True;t.exporter=unreal.AnimSequenceExporterFBX();t.options=unreal.FbxExportOption();assert unreal.Exporter.run_asset_export_task(t)
