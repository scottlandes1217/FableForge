"""Male shoulder-cap skinning correction; source coordinates are centimetres.

The cap follows the clavicle while upper-arm swing retains influence toward the
arm. No rest positions, shape keys, UVs, skeleton bones, or female mesh change.
Apply once to the original male source, before exporting body or fitted clothing.
"""
def stabilize_male_shoulders(body):
 changed=0
 for v in body.data.vertices:
  x,y,z=v.co
  def smooth(t):
   t=max(0,min(1,t));return t*t*(3-2*t)
  t=((abs(x)-16.05)*16.4+(z-142.84)*-21.6)/(16.4**2+21.6**2)
  alpha=.65*smooth((abs(x)-11)/5)*(1-smooth((t-.05)/.55))*smooth((164-z)/6)
  if alpha<=0:continue
  side='l' if x>0 else 'r';target=body.vertex_groups['clavicle_'+side];added=0
  for g in list(v.groups):
   name=body.vertex_groups[g.group].name
   if name=='upperarm_'+side or name.startswith('upperarm_twist_') or name.startswith('neck_'):
    w=g.weight*alpha;added+=w;body.vertex_groups[g.group].add([v.index],g.weight-w,'REPLACE')
  old=next((g.weight for g in v.groups if g.group==target.index),0);target.add([v.index],old+added,'REPLACE')
  if added>1e-7:changed+=1
  # Preserve the importer's eight-influence limit and normalized skinning.
  weights=sorted(((g.group,g.weight) for g in v.groups if g.weight>1e-7),key=lambda pair:pair[1],reverse=True)[:8]
  total=sum(w for _,w in weights)
  for group in [g.group for g in v.groups]:body.vertex_groups[group].remove([v.index])
  for group,w in weights:body.vertex_groups[group].add([v.index],w/total,'REPLACE')
 return changed
