"""Shared centimetre-space adult body and facial shape deformation.
FemaleBody/BodyFat/Muscle/Bust:0..1. Other channels:-1..1.
Neutral is0. Skeleton hierarchy unchanged; torso proportions bounded.
"""
import math
MORPH_NAMES=('BodyBuild','ShoulderWidth','WaistWidth','HipWidth','JawWidth','CheekWidth','NoseWidth','EarLength','FemaleBody','BodyFat','Muscle','Bust','TorsoLength','ChinHeight','ChinDepth','JawDepth','CheekFullness','NoseLength','NoseHeight','EyeSize','EyeSpacing','BrowHeight','MouthWidth','LipFullness','EarPoint')
POSITIVE_ONLY={'FemaleBody','BodyFat','Muscle','Bust'}
def bell(value,centre,radius):
 t=max(0.,1.-abs(value-centre)/radius)
 return t*t*(3.-2.*t)
def offset(name,co):
 x,y,z=co;dx=dy=dz=0.;side=1 if x>=0 else -1
 front=bell(y,-8,15);face=bell(y,-8,11)
 if name=='BodyBuild':
  a=bell(z,123,35);dx=x*.40*a;dy=(y+2)*.55*a
 elif name=='ShoulderWidth':dx=x*.34*bell(z,143,24)*bell(x,0,65)
 elif name=='WaistWidth':
  a=bell(z,113,23);dx=x*.42*a;dy=(y+2)*.32*a
 elif name=='HipWidth':dx=x*.42*bell(z,94,26)
 elif name=='JawWidth':dx=x*.30*bell(z,158,8)*bell(x,0,15)
 elif name=='CheekWidth':dx=x*.22*bell(z,164,7)*bell(x,0,15)
 elif name=='NoseWidth':dx=x*.40*bell(z,164,5)*bell(x,0,4)*bell(y,-10,7)
 elif name=='EarLength':
  a=bell(z,165,8)*bell(abs(x),9,4);dx=side*2.5*a;dz=1.2*a
 elif name=='FemaleBody':
  dx=x*(-.17*bell(z,144,22)*bell(x,0,48)-.20*bell(z,117,19)*bell(x,0,30)+.28*bell(z,95,24)*bell(x,0,35)-.18*bell(z,158,8)*bell(x,0,15))
  dy=(y+2)*(-.10*bell(z,121,22)+.12*bell(z,97,20))
  dy-=3.8*bell(abs(x),7,8)*bell(z,137,12)*front
  dz=-.8*bell(z,158,9)*face
 elif name=='BodyFat':
  # Broad abdomen/hip volume, no lateral bell attenuation at the silhouette.
  abdomen=bell(z,111,32);hips=bell(z,91,24);thigh=bell(z,74,22)
  dx=x*(.78*abdomen+.20*hips+.18*thigh)
  dy=(y+2)*(.85*abdomen+.30*hips+.18*thigh)
 elif name=='Muscle':
  a=bell(z,136,26)*bell(x,0,43);dx=x*.13*a;dy=(y+2)*.25*a
 elif name=='Bust':dy=-4.5*bell(abs(x),7,8)*bell(z,137,12)*front
 elif name=='TorsoLength':dz=2.5*bell(z,128,33)*bell(x,0,32)
 elif name=='ChinHeight':dz=-1.3*bell(z,155.5,5)*bell(x,0,6)*face
 elif name=='ChinDepth':dy=-1.5*bell(z,156,5)*bell(x,0,6)*face
 elif name=='JawDepth':dy=-1.5*bell(z,158,8)*bell(x,0,13)*face
 elif name=='CheekFullness':
  a=bell(z,162.5,6)*bell(abs(x),5,5)*face;dx=side*.8*a;dy=-1.2*a
 elif name=='NoseLength':dy=-1.4*bell(z,164,5)*bell(x,0,3.5)*bell(y,-10,7)
 elif name=='NoseHeight':dz=.8*bell(z,164,5)*bell(x,0,3.5)*bell(y,-10,7)
 elif name=='EyeSize':
  a=bell(z,166,4)*bell(abs(x),3.4,3.4)*face;dx=(x-side*3.4)*.22*a;dz=(z-166)*.22*a
 elif name=='EyeSpacing':dx=side*.75*bell(z,166,5)*bell(abs(x),3.4,4)*face
 elif name=='BrowHeight':dz=.8*bell(z,169,4)*bell(abs(x),3.5,4.5)*face
 elif name=='MouthWidth':dx=x*.30*bell(z,159,3.5)*bell(x,0,5.5)*face
 elif name=='LipFullness':dy=-.65*bell(z,159,2.2)*bell(x,0,3.5)*face
 elif name=='EarPoint':
  a=bell(z,168,5)*bell(abs(x),9,4);dx=side*1.5*a;dz=2.5*a
 if name in {'BodyBuild','BodyFat','WaistWidth','HipWidth'}:
  # Saturate outward translation smoothly instead of folding the outer arm at a cutoff.
  ratio=abs(x)/16.
  if ratio>1e-6:dx*=math.tanh(ratio)/ratio
  dy/=1+(abs(x)/24.)**4
 elif name in {'Muscle','TorsoLength','FemaleBody'}:
  t=max(0.,min(1.,(28.-abs(x))/6.));lateral=t*t*(3-2*t)
  h=max(0.,min(1.,(135.-z)/10.));h=h*h*(3-2*h);mask=1-(1-lateral)*h;dx*=mask;dy*=mask;dz*=mask
 if name in {'JawWidth','CheekWidth','NoseWidth','EarLength','ChinHeight','ChinDepth','JawDepth','CheekFullness','NoseLength','NoseHeight','EyeSize','EyeSpacing','BrowHeight','MouthWidth','LipFullness','EarPoint'}:
  t=max(0.,min(1.,(z-152.)/3.));mask=t*t*(3-2*t);dx*=mask;dy*=mask;dz*=mask
 return dx,dy,dz
