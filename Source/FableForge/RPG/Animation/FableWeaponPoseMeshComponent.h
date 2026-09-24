#pragma once
#include "CoreMinimal.h"
#include "Components/SkeletalMeshComponent.h"
#include "FableWeaponPoseMeshComponent.generated.h"

namespace FableWeaponPose
{
struct FRig
{
 TArray<FTransform> ReferenceComponent;
 TArray<TArray<int32>> Descendants;
 TArray<int32> Parents;
 TArray<int32> RightArm;
 TArray<TArray<int32>> Fingers;
 TArray<int32> Thumb;
 int32 Upper=INDEX_NONE,Lower=INDEX_NONE,Hand=INDEX_NONE;
 FTransform GripLocal=FTransform::Identity;
 void Initialize(const USkeletalMesh* Mesh);
 bool IsValid() const {return Hand!=INDEX_NONE && Upper!=INDEX_NONE && Lower!=INDEX_NONE;}
};
// Pure pose correction, shared by the component and asset-backed automation tests.
FABLEFORGE_API void Apply(const FRig& Rig,TArray<FTransform>& ComponentPose,float GripAlpha,float AirAlpha);
}

/** Retains the existing locomotion graph, correcting the equipped sword pose
 * immediately before the component publishes its completed bone transforms. */
UCLASS()
class FABLEFORGE_API UFableWeaponPoseMeshComponent : public USkeletalMeshComponent
{
 GENERATED_BODY()
public:
 void SetSwordEquipped(bool Equipped) {bSwordEquipped=Equipped;}
 virtual void TickComponent(float DeltaTime,ELevelTick TickType,FActorComponentTickFunction* ThisTickFunction) override;
 virtual void FinalizeBoneTransform() override;
private:
 bool bSwordEquipped=false;
 float GripBlend=0.f,AirBlend=0.f;
 TWeakObjectPtr<USkeletalMesh> CachedMesh;
 FableWeaponPose::FRig Rig;
};
