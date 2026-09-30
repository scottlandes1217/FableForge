"""Build the project-owned instanced, unlit spell-mote material."""
import unreal

lib = unreal.MaterialEditingLibrary
material = unreal.load_asset('/Game/UI/Materials/M_SpellMotes')
if not material:
    material = unreal.AssetToolsHelpers.get_asset_tools().create_asset(
        'M_SpellMotes', '/Game/UI/Materials', unreal.Material, unreal.MaterialFactoryNew())
lib.delete_all_material_expressions(material)
material.set_editor_property('shading_model', unreal.MaterialShadingModel.MSM_UNLIT)
material.set_editor_property('blend_mode', unreal.BlendMode.BLEND_ADDITIVE)
material.set_editor_property('two_sided', True)
lib.set_material_usage(material, unreal.MaterialUsage.MATUSAGE_INSTANCED_STATIC_MESHES)
color = lib.create_material_expression(material, unreal.MaterialExpressionVectorParameter)
color.set_editor_property('parameter_name', 'Color')
color.set_editor_property('default_value', unreal.LinearColor(1, .3, .05, 1))
lib.connect_material_property(color, '', unreal.MaterialProperty.MP_EMISSIVE_COLOR)
opacity = lib.create_material_expression(material, unreal.MaterialExpressionConstant)
opacity.set_editor_property('r', .65)
lib.connect_material_property(opacity, '', unreal.MaterialProperty.MP_OPACITY)
lib.recompile_material(material)
unreal.EditorAssetLibrary.save_loaded_asset(material)
unreal.log('SPELL_MATERIAL_READY')
