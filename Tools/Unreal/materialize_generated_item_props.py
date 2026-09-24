import unreal,json,re
from pathlib import Path
root=Path(unreal.Paths.project_dir()).resolve(); specs=json.loads((root/'ArtSource/ItemProps/materials.json').read_text()); mats={};lib=unreal.MaterialEditingLibrary
for name,spec in specs.items():
 slug=re.sub('[^A-Za-z0-9_]','_',name);path='/Game/Items/GeneratedProps/M_'+slug
 m=unreal.load_asset(path) or unreal.AssetToolsHelpers.get_asset_tools().create_asset('M_'+slug,'/Game/Items/GeneratedProps',unreal.Material,unreal.MaterialFactoryNew())
 lib.delete_all_material_expressions(m)
 c=lib.create_material_expression(m,unreal.MaterialExpressionConstant3Vector);c.constant=unreal.LinearColor(*spec['color'],1);lib.connect_material_property(c,'',unreal.MaterialProperty.MP_BASE_COLOR)
 for key,prop in [('roughness',unreal.MaterialProperty.MP_ROUGHNESS),('metallic',unreal.MaterialProperty.MP_METALLIC)]:
  e=lib.create_material_expression(m,unreal.MaterialExpressionConstant);e.r=spec[key];lib.connect_material_property(e,'',prop)
 lib.recompile_material(m);unreal.EditorAssetLibrary.save_loaded_asset(m);mats[slug.lower()]=m
report={}
for f in (root/'ArtSource/ItemProps').glob('*.fbx'):
 mesh=unreal.load_asset('/Game/Items/GeneratedProps/SM_'+f.stem);slots=mesh.static_materials
 for i,slot in enumerate(slots):
  key=re.sub('[^A-Za-z0-9_]','_',str(slot.material_slot_name)).lower();m=mats.get(key)
  if m:mesh.set_material(i,m)
  else:raise RuntimeError('Unknown material '+key)
 unreal.EditorAssetLibrary.save_loaded_asset(mesh);bounds=mesh.get_bounds();report[f.stem]={'dimensions_cm':str(bounds.box_extent*2),'material_count':len(slots)}
(root/'Saved/GeneratedPropValidation.json').write_text(json.dumps(report,indent=2));unreal.log('PROP_MATERIALS_SUCCESS '+str(report));unreal.SystemLibrary.quit_editor()
