#include "RPG/Animation/FableWeaponPoseMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/SkeletalMeshSocket.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Math/RotationMatrix.h"

namespace FableWeaponPose
{
void FRig::Initialize(const USkeletalMesh* Mesh)
{
 *this=FRig();if(!Mesh) return;
 const FReferenceSkeleton& Ref=Mesh->GetRefSkeleton();
 const int32 Count=Ref.GetNum();ReferenceComponent=Ref.GetRefBonePose();Parents.SetNum(Count);Descendants.SetNum(Count);
 for(int32 I=0;I<Count;++I)
 {
  Parents[I]=Ref.GetParentIndex(I);
  if(Parents[I]!=INDEX_NONE) ReferenceComponent[I]=ReferenceComponent[I]*ReferenceComponent[Parents[I]];
  for(int32 P=I;P!=INDEX_NONE;P=Parents[P]) Descendants[P].Add(I);
 }
 Upper=Ref.FindBoneIndex(TEXT("upperarm_r"));Lower=Ref.FindBoneIndex(TEXT("lowerarm_r"));Hand=Ref.FindBoneIndex(TEXT("hand_r"));
 if(Upper!=INDEX_NONE) RightArm=Descendants[Upper];
 for(const TCHAR* Prefix:{TEXT("index"),TEXT("middle"),TEXT("ring"),TEXT("pinky"),TEXT("thumb")})
 {
  TArray<int32> Chain;
  for(int32 Joint=1;Joint<=3;++Joint) Chain.Add(Ref.FindBoneIndex(FName(*FString::Printf(TEXT("%s_%02d_r"),Prefix,Joint))));
  if(Chain.Contains(INDEX_NONE)) continue;
  if(FCString::Strcmp(Prefix,TEXT("thumb"))==0) Thumb=MoveTemp(Chain);else Fingers.Add(MoveTemp(Chain));
 }
 if(const USkeletalMeshSocket* Socket=Mesh->FindSocket(TEXT("HandGrip_R"))) GripLocal=Socket->GetSocketLocalTransform();
}
static void Rotate(const FRig& R,TArray<FTransform>& Pose,int32 Bone,const FQuat& Delta)
{
 if(Bone==INDEX_NONE) return;
 const FVector Pivot=Pose[Bone].GetLocation();
 for(int32 I:R.Descendants[Bone])
 {
  Pose[I].SetLocation(Pivot+Delta.RotateVector(Pose[I].GetLocation()-Pivot));
  Pose[I].SetRotation((Delta*Pose[I].GetRotation()).GetNormalized());
 }
}
static void BlendLocal(const FRig& R,const TArray<FTransform>& Original,TArray<FTransform>& Corrected,float Alpha)
{
 if(Alpha>=1.f) return;
 TArray<FTransform> Locals;Locals.SetNum(Corrected.Num());
 for(int32 I:R.RightArm)
 {
  const int32 P=R.Parents[I];
  const FTransform A=P==INDEX_NONE?Original[I]:Original[I].GetRelativeTransform(Original[P]);
  const FTransform B=P==INDEX_NONE?Corrected[I]:Corrected[I].GetRelativeTransform(Corrected[P]);
  Locals[I].Blend(A,B,Alpha);
 }
 for(int32 I:R.RightArm) Corrected[I]=R.Parents[I]==INDEX_NONE?Locals[I]:Locals[I]*Corrected[R.Parents[I]];
}
void Apply(const FRig& R,TArray<FTransform>& Pose,float GripAlpha,float AirAlpha)
{
 GripAlpha=FMath::Clamp(GripAlpha,0.f,1.f);AirAlpha=FMath::Clamp(AirAlpha,0.f,1.f);
 if(!R.IsValid() || Pose.Num()!=R.Parents.Num() || GripAlpha<=KINDA_SMALL_NUMBER) return;
 const TArray<FTransform> Original=Pose;
 if(AirAlpha>KINDA_SMALL_NUMBER)
 {
  const FVector Shoulder=Pose[R.Upper].GetLocation();
  const FVector OldElbow=Pose[R.Lower].GetLocation();
  const FVector OldHand=Pose[R.Hand].GetLocation();
  const float UpperLength=FVector::Distance(Shoulder,OldElbow),LowerLength=FVector::Distance(OldElbow,OldHand);
  // Keep the weapon on the character's right, clear of the torso throughout jumping.
  FVector Goal=Shoulder+FVector(-30.f,12.f,-12.f);
  FVector Along=(Goal-Shoulder).GetSafeNormal();
  const float Distance=FMath::Clamp(FVector::Distance(Goal,Shoulder),FMath::Abs(UpperLength-LowerLength)+.1f,UpperLength+LowerLength-.1f);
  Goal=Shoulder+Along*Distance;
  FVector Bend=FVector(-1,0,-1)-Along*FVector::DotProduct(FVector(-1,0,-1),Along);Bend.Normalize();
  const float A=(UpperLength*UpperLength-LowerLength*LowerLength+Distance*Distance)/(2.f*Distance);
  const FVector Elbow=Shoulder+Along*A+Bend*FMath::Sqrt(FMath::Max(0.f,UpperLength*UpperLength-A*A));
  Rotate(R,Pose,R.Upper,FQuat::FindBetweenNormals((OldElbow-Shoulder).GetSafeNormal(),(Elbow-Shoulder).GetSafeNormal()));
  Rotate(R,Pose,R.Lower,FQuat::FindBetweenNormals((Pose[R.Hand].GetLocation()-Pose[R.Lower].GetLocation()).GetSafeNormal(),(Goal-Pose[R.Lower].GetLocation()).GetSafeNormal()));
  const FVector BladeDirection=FVector(-.25f,.05f,1.f).GetSafeNormal();
  const FQuat GripRotation=FRotationMatrix::MakeFromZY(BladeDirection,FVector(0,1,0)).ToQuat();
  const FQuat HandRotation=GripRotation*R.GripLocal.GetRotation().Inverse();
  Rotate(R,Pose,R.Hand,HandRotation*Pose[R.Hand].GetRotation().Inverse());
  BlendLocal(R,Original,Pose,AirAlpha);
 }
 // Restore only finger locals to the authored reference before curling. This
 // removes open-hand locomotion keys without replacing arm/leg animation.
 for(int32 I:R.Descendants[R.Hand])
 {
  if(I==R.Hand) continue;
  const int32 P=R.Parents[I];
  FTransform Local=R.ReferenceComponent[I].GetRelativeTransform(R.ReferenceComponent[P]);
  const FTransform AnimatedLocal=Original[I].GetRelativeTransform(Original[P]);
  Local.SetTranslation(AnimatedLocal.GetTranslation());Local.SetScale3D(AnimatedLocal.GetScale3D());
  Pose[I]=Local*Pose[P];
 }
 const FVector CurlAxis=Pose[R.Hand].GetRotation().RotateVector(FVector(0,0,1));
 const float CurlDegrees[]={-105.f,-90.f,-65.f};
 for(const TArray<int32>& Chain:R.Fingers)
  for(int32 J=0;J<Chain.Num();++J) Rotate(R,Pose,Chain[J],FQuat(CurlAxis,FMath::DegreesToRadians(CurlDegrees[J])));
 if(R.Thumb.Num()==3)
 {
  const int32 Tip=R.Thumb.Last();
  const FVector RefDirection=R.ReferenceComponent[Tip].GetLocation()-R.ReferenceComponent[R.Thumb[1]].GetLocation();
  const FVector TipOffset=R.ReferenceComponent[Tip].InverseTransformVectorNoScale(RefDirection.GetSafeNormal()*2.f);
  const FVector Target=Pose[R.Hand].TransformPosition(R.GripLocal.GetLocation()+FVector(.5f,1.6f,.3f));
  for(int32 Iteration=0;Iteration<4;++Iteration)
   for(int32 J=2;J>=0;--J)
   {
    const int32 Bone=R.Thumb[J];const FVector Pivot=Pose[Bone].GetLocation();
    const FVector End=Pose[Tip].TransformPosition(TipOffset);
    FQuat Delta=FQuat::FindBetweenNormals((End-Pivot).GetSafeNormal(),(Target-Pivot).GetSafeNormal());
    const float Angle=Delta.GetAngle();if(Angle>FMath::DegreesToRadians(35.f)) Delta=FQuat::Slerp(FQuat::Identity,Delta,FMath::DegreesToRadians(35.f)/Angle);
    Rotate(R,Pose,Bone,Delta);
   }
 }
 BlendLocal(R,Original,Pose,GripAlpha);
}
}
void UFableWeaponPoseMeshComponent::TickComponent(float DeltaTime,ELevelTick TickType,FActorComponentTickFunction* ThisTickFunction)
{
 const ACharacter* Character=Cast<ACharacter>(GetOwner());
 const bool Airborne=bSwordEquipped && Character && Character->GetCharacterMovement() && Character->GetCharacterMovement()->IsFalling();
 GripBlend=FMath::FInterpTo(GripBlend,bSwordEquipped?1.f:0.f,DeltaTime,18.f);
 AirBlend=FMath::FInterpTo(AirBlend,Airborne?1.f:0.f,DeltaTime,12.f);
 Super::TickComponent(DeltaTime,TickType,ThisTickFunction);
}
void UFableWeaponPoseMeshComponent::FinalizeBoneTransform()
{
 // The engine flips editable/read buffers in Super. Correct the completed
 // editable pose first so sockets, rendering and leader-pose clothing agree.
 if(bNeedToFlipSpaceBaseBuffers && GripBlend>KINDA_SMALL_NUMBER && !IsSimulatingPhysics())
 {
  if(CachedMesh.Get()!=GetSkeletalMeshAsset()) {CachedMesh=GetSkeletalMeshAsset();Rig.Initialize(GetSkeletalMeshAsset());}
  FableWeaponPose::Apply(Rig,GetEditableComponentSpaceTransforms(),GripBlend,AirBlend);
 }
 Super::FinalizeBoneTransform();
}
