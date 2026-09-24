# Female-only reimport: preserve authored female skin and all shared morphs.
import os
root=os.path.dirname(os.path.abspath(__file__))
code=open(root+'/import_body_v2.py').read().replace('basecharacter_v2','femalecharacter_v2').replace('M_BodySkin_V2','M_FemaleSkin_V2').replace('import-validation.json','female-import-validation.json')
exec(compile(code,root+'/import_body_v2.py','exec'))
# Blender-authored tangent-space detail uses MikkTSpace at UV seams.
mesh=unreal.load_asset('/Game/Characters/PlayableCharacter/Meshes/femalecharacter_v2')
sub=unreal.get_editor_subsystem(unreal.SkeletalMeshEditorSubsystem)
settings=sub.get_lod_build_settings(mesh,0)
settings.set_editor_property('use_mikk_t_space',True)
settings.set_editor_property('recompute_tangents',True)
sub.set_lod_build_settings(mesh,0,settings)
unreal.EditorAssetLibrary.save_loaded_asset(mesh)
