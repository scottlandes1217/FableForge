import unreal

shared = unreal.load_asset('/Game/Items/Armor/Materials/MI_Peasant')
assert shared
for name in ('male_peasant_feet_v2', 'female_peasant_feet_v2'):
    mesh = unreal.load_asset('/Game/Items/Armor/FittedLowerArmor/' + name)
    assert mesh
    slots = list(mesh.get_editor_property('materials'))
    for slot in slots:
        slot.material_interface = shared
    mesh.set_editor_property('materials', slots)
    unreal.EditorAssetLibrary.save_loaded_asset(mesh)
    print('UNIFIED_LOWER_ARMOR_MATERIAL', name, len(slots))
