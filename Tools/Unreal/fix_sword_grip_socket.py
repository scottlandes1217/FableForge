"""Align sword HandGrip with the center of its actual wrapped handle."""
import unreal
mesh=unreal.load_asset('/Game/Items/Weapons/Skeletal_Meshes/SM_Sword')
socket=mesh.find_socket('HandGrip')
assert socket and str(socket.get_editor_property('bone_name'))=='Root'
socket.set_editor_property('relative_location',unreal.Vector(0,0,12.237671))
assert unreal.EditorAssetLibrary.save_loaded_asset(mesh.get_editor_property('skeleton'),False)
assert abs(socket.get_editor_property('relative_location').z-12.237671)<0.0001
print('Sword HandGrip Root-local Z=12.237671 cm; Root Z=-11.237671 cm; handle center component Z=1 cm')
