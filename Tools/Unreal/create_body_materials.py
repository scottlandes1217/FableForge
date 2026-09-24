import unreal
root='/Game/Characters/PlayableCharacter/Materials/'
def material(name,parameter,texture_path=None,base=None,rough=.72):
 path=root+name;m=unreal.load_asset(path)
 if not m:m=unreal.AssetToolsHelpers.get_asset_tools().create_asset(name,root,unreal.Material,unreal.MaterialFactoryNew())
 unreal.MaterialEditingLibrary.delete_all_material_expressions(m)
 m.set_editor_property('used_with_skeletal_mesh',True);m.set_editor_property('used_with_morph_targets',True)
 tint=unreal.MaterialEditingLibrary.create_material_expression(m,unreal.MaterialExpressionVectorParameter);tint.set_editor_property('parameter_name',parameter);tint.set_editor_property('default_value',unreal.LinearColor(1,1,1,1))
 if texture_path:
  color=unreal.MaterialEditingLibrary.create_material_expression(m,unreal.MaterialExpressionTextureSample);color.texture=unreal.load_asset(texture_path)
 else:
  color=unreal.MaterialEditingLibrary.create_material_expression(m,unreal.MaterialExpressionConstant3Vector);color.constant=unreal.LinearColor(*base,1)
 mul=unreal.MaterialEditingLibrary.create_material_expression(m,unreal.MaterialExpressionMultiply)
 unreal.MaterialEditingLibrary.connect_material_expressions(color,'RGB' if texture_path else '',mul,'A');unreal.MaterialEditingLibrary.connect_material_expressions(tint,'',mul,'B');unreal.MaterialEditingLibrary.connect_material_property(mul,'',unreal.MaterialProperty.MP_BASE_COLOR)
 for value,prop in [(rough,unreal.MaterialProperty.MP_ROUGHNESS),(.28,unreal.MaterialProperty.MP_SPECULAR)]:
  e=unreal.MaterialEditingLibrary.create_material_expression(m,unreal.MaterialExpressionConstant);e.r=value;unreal.MaterialEditingLibrary.connect_material_property(e,'',prop)
 unreal.MaterialEditingLibrary.recompile_material(m);unreal.EditorAssetLibrary.save_loaded_asset(m);return m
skin=material('M_BodySkin_V2','SkinTint','/Game/Characters/PlayableCharacter/Textures/Base/Base_Dark')
eye_original=unreal.load_asset(root+'Base_Eye_Brown_Mat');eye_tex=next(o.texture.get_path_name() for o in unreal.ObjectIterator() if isinstance(o,unreal.MaterialExpressionTextureSample) and o.get_outer()==eye_original)
eyes=material('M_BodyEyes_V2','EyeTint',eye_tex,rough=.3)
hair=material('M_BodyHair_V2','HairTint',base=(.045,.025,.014),rough=.8)
b=unreal.load_asset('/Game/Characters/PlayableCharacter/Meshes/basecharacter_v2');slots=b.materials
for i,m in enumerate([hair,eyes,skin]):
 slot=slots[i];slot.material_interface=m;slots[i]=slot
b.set_editor_property('materials',slots);unreal.EditorAssetLibrary.save_loaded_asset(b)
print('BODY_MATERIALS_MORPH_READY')
