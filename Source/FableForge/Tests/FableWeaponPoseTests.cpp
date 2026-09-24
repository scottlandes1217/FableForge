#if WITH_DEV_AUTOMATION_TESTS
#include "Misc/AutomationTest.h"
#include "RPG/Animation/FableWeaponPoseMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Animation/AnimSequence.h"
#include "Animation/Skeleton.h"

IMPLEMENT_SIMPLE_AUTOMATION_TEST(FFableWeaponPoseTest,"FableForge.Character.EquippedSwordPose",EAutomationTestFlags::EditorContext|EAutomationTestFlags::EngineFilter)
bool FFableWeaponPoseTest::RunTest(const FString& Parameters)
{
 for(const TCHAR* Path:{TEXT("/Game/Characters/PlayableCharacter/Meshes/basecharacter_v2.basecharacter_v2"),TEXT("/Game/Characters/PlayableCharacter/Meshes/femalecharacter_v2.femalecharacter_v2")})
 {
 USkeletalMesh* Mesh=LoadObject<USkeletalMesh>(nullptr,Path);
 UAnimSequence* Jump=LoadObject<UAnimSequence>(nullptr,TEXT("/Game/Characters/PlayableCharacter/Anims/Unarmed/Jump/MM_Jump.MM_Jump"));
 if(!TestNotNull(TEXT("Body exists"),Mesh)||!TestNotNull(TEXT("Jump exists"),Jump)) return false;
 FableWeaponPose::FRig Rig;Rig.Initialize(Mesh);
 if(!TestTrue(TEXT("Weapon rig is complete"),Rig.IsValid())) return false;
 const FReferenceSkeleton& Ref=Mesh->GetRefSkeleton();
 const FReferenceSkeleton& AnimRef=Jump->GetSkeleton()->GetReferenceSkeleton();
 // Sample every phase, including takeoff, apex, and landing, from the actual asset.
 for(int32 Sample=0;Sample<=20;++Sample)
 {
  TArray<FTransform> Source=Ref.GetRefBonePose();
  for(int32 Bone=0;Bone<Source.Num();++Bone)
  {
   const int32 AnimBone=AnimRef.FindBoneIndex(Ref.GetBoneName(Bone));
   if(AnimBone!=INDEX_NONE) Jump->GetBoneTransform(Source[Bone],FSkeletonPoseBoneIndex(AnimBone),Jump->GetPlayLength()*Sample/20.,true);
   const int32 Parent=Ref.GetParentIndex(Bone);if(Parent!=INDEX_NONE) Source[Bone]=Source[Bone]*Source[Parent];
  }
  TArray<FTransform> Unarmed=Source;
  FableWeaponPose::Apply(Rig,Unarmed,0.f,1.f);
  for(int32 Bone=0;Bone<Source.Num();++Bone) TestTrue(TEXT("Unarmed pose is unchanged"),Unarmed[Bone].Equals(Source[Bone],0.f));
  for(float Alpha:{.1f,.5f,1.f})
  {
   TArray<FTransform> Equipped=Source;
   FableWeaponPose::Apply(Rig,Equipped,Alpha,Alpha);
   for(int32 Bone=0;Bone<Equipped.Num();++Bone)
   {
    TestFalse(TEXT("Correction stays finite"),Equipped[Bone].ContainsNaN());
    TestTrue(TEXT("Rotation stays normalized"),Equipped[Bone].GetRotation().IsNormalized());
    const int32 Parent=Rig.Parents[Bone];
    if(Parent!=INDEX_NONE) TestTrue(FString::Printf(TEXT("%s sample %d alpha %.1f bone %s: bone length preserved"),*Mesh->GetName(),Sample,Alpha,*Ref.GetBoneName(Bone).ToString()),FMath::IsNearlyEqual(FVector::Distance(Equipped[Bone].GetLocation(),Equipped[Parent].GetLocation()),FVector::Distance(Source[Bone].GetLocation(),Source[Parent].GetLocation()),.02));
    if(!Rig.RightArm.Contains(Bone)) TestTrue(TEXT("Other limbs keep their original animation"),Equipped[Bone].Equals(Source[Bone],0.f));
   }
   if(Alpha==1.f)
   {
    const FTransform Grip=Rig.GripLocal*Equipped[Rig.Hand];
    // Conservative torso envelope. Blade travels upward/outward from the right
    // hand rather than inward through the torso in the unarmed jump animation.
    for(float Along:{0.f,20.f,40.f,60.f,80.f})
    {
     const FVector Blade=Grip.TransformPosition(FVector(0,0,Along));
     TestTrue(TEXT("Airborne blade stays outside central torso"),Blade.X < -25.f);
    }
   }
  }
 }
 }
 return true;
}
#endif
