#pragma once
#include "CoreMinimal.h"
#include "RPG/UI/FableAppearanceCatalog.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/SkeletalMesh.h"
#include "Engine/StaticMesh.h"
#include "Materials/MaterialInstanceDynamic.h"

namespace FableAppearanceAssets
{
inline FString StyleMeshPath(const FString& Style, bool Beard = false, bool Female = false)
{
 const TArray<FStyle>& Styles=Beard?ListBeardStyles(Female):ListHairStyles(Female);
 for(const FStyle& Entry:Styles) if(Entry.Id==Style) return Female?Entry.FemaleMeshPath:Entry.MaleMeshPath;
 return FString();
}

// Static hair is authored in the body's reference component space. Cancel the
// head's reference transform while retaining its animated attachment.
inline FTransform HeadRelativeTransform(const USkeletalMesh* Mesh, float HeadSize = 0.f)
{
 if (!Mesh) return FTransform::Identity;
 const FReferenceSkeleton& Ref=Mesh->GetRefSkeleton();
 int32 Bone=Ref.FindBoneIndex(TEXT("head"));
 if (Bone==INDEX_NONE) return FTransform::Identity;
 FTransform Head=Ref.GetRefBonePose()[Bone];
 while ((Bone=Ref.GetParentIndex(Bone))!=INDEX_NONE) Head=Head*Ref.GetRefBonePose()[Bone];
 // Match the authored HeadSize morph above the neck transition.
 const float Scale=1.f+.30f*FMath::Clamp(HeadSize,0.f,1.f);
 const FVector Pivot(0,0,154.f);
 const FTransform Enlargement(FQuat::Identity,Pivot*(1.f-Scale),FVector(Scale));
 return Enlargement*Head.Inverse();
}

inline void ConfigureStyle(UStaticMeshComponent* Component, USkeletalMeshComponent* Body, const FString& Style, bool Beard, FLinearColor Tint, float HeadSize = 0.f)
{
 if (!Component || !Body) return;
 const bool Female=Body->GetSkeletalMeshAsset() && Body->GetSkeletalMeshAsset()->GetName().StartsWith(TEXT("female"));
 const FString Path=StyleMeshPath(Style,Beard,Female);
 UStaticMesh* Mesh=Component->GetStaticMesh();
 if (Path.IsEmpty()) Mesh=nullptr;
 else if (!Mesh || Mesh->GetPathName()!=Path) Mesh=LoadObject<UStaticMesh>(nullptr,*Path);
 const bool Changed=Component->GetStaticMesh()!=Mesh;
 if (Changed) { Component->SetStaticMesh(Mesh); Component->EmptyOverrideMaterials(); }
 Component->SetVisibility(Mesh!=nullptr);
 Component->SetCollisionEnabled(ECollisionEnabled::NoCollision);
 Component->SetCastShadow(false);
 Component->SetReceivesDecals(false);
 Component->AttachToComponent(Body,FAttachmentTransformRules::KeepRelativeTransform,TEXT("head"));
 Component->SetRelativeTransform(HeadRelativeTransform(Body->GetSkeletalMeshAsset(),HeadSize));
 if (Mesh)
 {
  for (int32 Slot=0; Slot<Component->GetNumMaterials(); ++Slot)
  {
   UMaterialInstanceDynamic* Material=Cast<UMaterialInstanceDynamic>(Component->GetMaterial(Slot));
   if (!Material) Material=Component->CreateAndSetMaterialInstanceDynamic(Slot);
   if (Material) Material->SetVectorParameterValue(TEXT("HairTint"),Tint);
  }
 }
}
}
