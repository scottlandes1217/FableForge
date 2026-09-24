import unreal,json
source='/Game/Characters/PlayableCharacter/Materials/Base_Dark_Mat';dest='/Game/Characters/PlayableCharacter/Materials/M_BodySkin_V2'
m=unreal.load_asset(dest) or unreal.EditorAssetLibrary.duplicate_asset(source,dest)
for node in list(unreal.ObjectIterator()):
 if isinstance(node,unreal.MaterialExpressionConstant) and node.get_outer()==m and node.get_editor_property('desc') in ['Skin roughness','Skin specular']:
  unreal.MaterialEditingLibrary.delete_material_expression(m,node)
for name,value,prop in [('Skin roughness',.72,unreal.MaterialProperty.MP_ROUGHNESS),('Skin specular',.28,unreal.MaterialProperty.MP_SPECULAR)]:
 e=unreal.MaterialEditingLibrary.create_material_expression(m,unreal.MaterialExpressionConstant);e.r=value;e.set_editor_property('desc',name);unreal.MaterialEditingLibrary.connect_material_property(e,'',prop)
unreal.MaterialEditingLibrary.recompile_material(m);unreal.EditorAssetLibrary.save_loaded_asset(m)
b=unreal.load_asset('/Game/Characters/PlayableCharacter/Meshes/basecharacter_v2');slots=b.get_editor_property('materials');slot=slots[2];slot.material_interface=m;slots[2]=slot;b.set_editor_property('materials',slots);unreal.EditorAssetLibrary.save_loaded_asset(b)
print('SKIN_V2_REFINED',m.get_path_name())
