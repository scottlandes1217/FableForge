"""Bounded centimetre-space shape offsets shared by body and clothing.
All weights -1..1; neutral 0. Skeleton and limb length stay unchanged.
"""
import math
MORPH_NAMES=('BodyBuild','ShoulderWidth','WaistWidth','HipWidth','JawWidth','CheekWidth','NoseWidth','EarLength')
def bell(value,centre,radius):
 t=max(0.,1.-abs(value-centre)/radius)
 return t*t*(3.-2.*t)
def offset(name,co):
 x,y,z=co; dx=dy=dz=0.
 if name=='BodyBuild':
  a=bell(z,123,30)*bell(x,0,34);dx=x*.10*a;dy=(y+2)*.16*a
 elif name=='ShoulderWidth':
  a=bell(z,143,17)*bell(x,0,46);dx=x*.075*a
 elif name=='WaistWidth':
  a=bell(z,113,17)*bell(x,0,28);dx=x*.13*a;dy=(y+2)*.08*a
 elif name=='HipWidth':
  a=bell(z,94,19)*bell(x,0,29);dx=x*.10*a
 elif name=='JawWidth':
  a=bell(z,158,6)*bell(x,0,12);dx=x*.14*a
 elif name=='CheekWidth':
  a=bell(z,164,5)*bell(x,0,13);dx=x*.10*a
 elif name=='NoseWidth':
  a=bell(z,164,4)*bell(x,0,3)*bell(y,-10,5);dx=x*.18*a
 elif name=='EarLength':
  a=bell(z,165,6)*bell(abs(x),9,3);dx=(1 if x>=0 else -1)*1.0*a;dz=.6*a
 return (dx,dy,dz)
