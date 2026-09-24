import unreal,json
base=unreal.load_asset('/Game/Characters/PlayableCharacter/Meshes/basecharacter_v2');b=unreal.SkeletalMeshComponent();b.set_skinned_asset_and_update(base)
results=[]
for gender in ['male','female']:
 for part in ['legs','feet']:
  name=gender+'_peasant_'+part+'_v2';mesh=unreal.load_asset('/Game/Items/Armor/FittedLowerArmor/'+name);assert mesh
  c=unreal.SkeletalMeshComponent();c.set_skinned_asset_and_update(mesh)
  maximum=0.
  for i in range(b.get_num_bones()):
   bone=b.get_bone_name(i);a=c.get_socket_transform(bone,unreal.RelativeTransformSpace.RTS_COMPONENT);r=b.get_socket_transform(bone,unreal.RelativeTransformSpace.RTS_COMPONENT)
   delta=(a.translation-r.translation).length();maximum=max(maximum,delta)
   assert delta<.01,(name,str(bone),delta)
   assert a.rotation.angular_distance(r.rotation)<.001,(name,str(bone),'rotation')
  results.append(dict(mesh=name,maximum_reference_position_difference_cm=maximum))
root=unreal.Paths.convert_relative_path_to_full(unreal.Paths.project_dir());open(root+'ArtSource/Characters/FittedLowerArmor/reference-pose-validation.json','w').write(json.dumps(results,indent=2));print('LOWER_ARMOR_REFERENCE_POSES_VALID',results)
