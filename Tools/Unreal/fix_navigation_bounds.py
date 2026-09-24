"""Fit only medieval map navigation coverage to its landscape; default is dry-run.

UnrealEditor-Cmd FableForge.uproject -run=pythonscript \
  -script="/absolute/path/fix_navigation_bounds.py --apply" -nullrhi -unattended
The original map is backed up before the explicit --apply operation.
"""
import json
import math
from pathlib import Path
import shutil
import sys
from datetime import datetime, timezone
import unreal

MAP = '/Game/Medieval_Village/maps/Medieval_Village_Demo'
apply = '--apply' in sys.argv
level = unreal.get_editor_subsystem(unreal.LevelEditorSubsystem)
if not level.load_level(MAP):
    raise RuntimeError('Could not load medieval map')
actors = unreal.get_editor_subsystem(unreal.EditorActorSubsystem).get_all_level_actors()
navs = [a for a in actors if a.get_class().get_name() == 'NavMeshBoundsVolume']
landscapes = [a for a in actors if a.get_class().get_name() in ('Landscape', 'LandscapeStreamingProxy')]
if len(navs) != 1 or not landscapes:
    raise RuntimeError('Expected one navigation volume and at least one landscape; refusing ambiguous edit')
nav = navs[0]
if nav.is_package_external() or nav.get_outermost().get_name() != MAP:
    raise RuntimeError('Navigation is not stored inside expected map; refusing to save additional packages')
def xyz(v): return [v.x, v.y, v.z]
lo, hi = [float('inf')] * 3, [float('-inf')] * 3
for landscape in landscapes:
    origin, extent = landscape.get_actor_bounds(False)
    for i, (o, e) in enumerate(zip(xyz(origin), xyz(extent))):
        lo[i], hi[i] = min(lo[i], o-e), max(hi[i], o+e)
padding = [1000.0, 1000.0, 2000.0]
center = [(a+b)/2 for a,b in zip(lo,hi)]
target_extent = [(b-a)/2+p for a,b,p in zip(lo,hi,padding)]
old_origin, old_extent = nav.get_actor_bounds(False)
old_scale = nav.get_actor_scale3d()
if min(xyz(old_extent)) <= 0 or min(target_extent) <= 0:
    raise RuntimeError('Degenerate navigation bounds')
scale = [s*t/e for s,t,e in zip(xyz(old_scale),target_extent,xyz(old_extent))]
report = {'apply': apply, 'map': MAP, 'nav_actor': nav.get_path_name(), 'package': nav.get_outermost().get_name(), 'external_package': nav.is_package_external(), 'before': {'origin': xyz(old_origin), 'extent': xyz(old_extent), 'scale': xyz(old_scale)}, 'target': {'origin': center, 'extent': target_extent, 'scale': scale}, 'approximate_xy_tiles_at_1000cm': math.ceil(target_extent[0]*2/1000)*math.ceil(target_extent[1]*2/1000)}
project = Path(unreal.Paths.convert_relative_path_to_full(unreal.Paths.project_dir()))
if apply:
    source = project / 'Content' / (MAP.removeprefix('/Game/') + '.umap')
    backup = project / 'Saved/OverhaulBackups' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') / source.relative_to(project)
    backup.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, backup)
    report['backup'] = str(backup)
    # Account for any brush center offset rather than assuming its origin is centered.
    old_location = xyz(nav.get_actor_location())
    new_location = [c-(o-l)*(ns/os) for c,o,l,ns,os in zip(center,xyz(old_origin),old_location,scale,xyz(old_scale))]
    nav.set_actor_scale3d(unreal.Vector(*scale))
    nav.set_actor_location(unreal.Vector(*new_location), False, False)
    result_origin, result_extent = nav.get_actor_bounds(False)
    for actual,target in zip(xyz(result_origin)+xyz(result_extent),center+target_extent):
        if abs(actual-target) > 1:
            raise RuntimeError('Navigation bounds verification failed; map not saved')
    if not level.save_current_level():
        raise RuntimeError('Failed to save navigation map; backup retained')
    report['after'] = {'origin': xyz(result_origin), 'extent': xyz(result_extent)}
output = project / 'Saved/OverhaulNavigationFix.json'
output.write_text(json.dumps(report, indent=2))
unreal.log('FABLEFORGE_NAV_FIX: ' + json.dumps(report))
