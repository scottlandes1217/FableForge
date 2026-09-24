"""Read-only navigation bounds and animation hierarchy audit. Never saves assets."""
import json
from pathlib import Path
import unreal

report = {'navigation': [], 'largest_actors': [], 'meshes': [], 'rigs': [], 'errors': []}
def prop(obj, key):
    try:
        return str(obj.get_editor_property(key))
    except Exception as exc:
        return 'unavailable: ' + str(exc)
def vec(v):
    return [v.x, v.y, v.z]

level = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
level.load_level('/Game/Medieval_Village/maps/Medieval_Village_Demo')
actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
for actor in actors:
    origin, extent = actor.get_actor_bounds(False)
    entry = {'name': actor.get_name(), 'label': actor.get_actor_label(), 'class': actor.get_class().get_name(), 'origin': vec(origin), 'extent': vec(extent), 'location': vec(actor.get_actor_location()), 'scale': vec(actor.get_actor_scale3d())}
    report['largest_actors'].append(entry)
    if 'NavMesh' in entry['class'] or 'Navigation' in entry['class']:
        entry = dict(entry)
        if entry['class'] == 'RecastNavMesh':
            entry['properties'] = {k: prop(actor, k) for k in ('tile_size_uu', 'tile_number_hard_limit', 'runtime_generation', 'fixed_tile_pool_size', 'tile_pool_size', 'agent_radius')}
        report['navigation'].append(entry)
report['largest_actors'].sort(key=lambda a: max(a['extent']), reverse=True)
report['largest_actors'] = report['largest_actors'][:30]
registry = unreal.AssetRegistryHelpers.get_asset_registry()
registry.search_all_assets(True)
assets = registry.get_assets_by_path('/Game/Characters', recursive=True)
for data in assets:
    kind = str(data.asset_class_path.asset_name)
    if kind == 'SkeletalMesh' and ('basecharacter' in str(data.asset_name).lower() or 'SKM_Manny' in str(data.asset_name)):
        mesh = data.get_asset()
        component = unreal.new_object(unreal.SkeletalMeshComponent)
        component.set_skeletal_mesh_asset(mesh)
        names = [component.get_bone_name(i) for i in range(component.get_num_bones())]
        report['meshes'].append({'path': mesh.get_path_name(), 'bones': {str(n): str(component.get_parent_bone(n)) for n in names}})
    elif kind == 'ControlRigBlueprint':
        rig = data.get_asset()
        entry = {'path': rig.get_path_name()}
        try:
            hierarchy = rig.get_editor_property('hierarchy')
            entry['bones'] = {str(k.name): str(hierarchy.get_first_parent(k).name) for k in hierarchy.get_all_keys() if k.type == unreal.RigElementType.BONE}
        except Exception as exc:
            entry['error'] = str(exc)
        report['rigs'].append(entry)
output = Path(unreal.Paths.project_saved_dir()) / 'OverhaulNavigationAnimationAudit.json'
output.write_text(json.dumps(report, indent=2))
unreal.log('FABLEFORGE_NAV_ANIM_AUDIT: ' + str(output))
