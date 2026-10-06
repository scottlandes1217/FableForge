#include "RPG/Gameplay/FableSpellVisualActor.h"
#include "Components/InstancedStaticMeshComponent.h"
#include "Components/PointLightComponent.h"
#include "Components/SceneComponent.h"
#include "Materials/MaterialInstanceDynamic.h"
#include "Engine/Texture.h"
#include "UObject/ConstructorHelpers.h"
#include "RPG/Gameplay/FableSpellRuntime.h"

namespace { constexpr int32 MoteCount = 80; }

AFableSpellVisualActor::AFableSpellVisualActor()
{
 PrimaryActorTick.bCanEverTick = true;
 SetCanBeDamaged(false);
 RootComponent = CreateDefaultSubobject<USceneComponent>(TEXT("Origin"));
 Motes = CreateDefaultSubobject<UInstancedStaticMeshComponent>(TEXT("SpellMotes"));
 Stones = CreateDefaultSubobject<UInstancedStaticMeshComponent>(TEXT("GroundSpikes"));
 for (UInstancedStaticMeshComponent* Mesh : {Motes.Get(), Stones.Get()})
 {
  Mesh->SetupAttachment(RootComponent);
  Mesh->SetCollisionEnabled(ECollisionEnabled::NoCollision);
  Mesh->SetCastShadow(false);
  Mesh->SetCanEverAffectNavigation(false);
 }
 Glow = CreateDefaultSubobject<UPointLightComponent>(TEXT("CastLight"));
 Glow->SetupAttachment(RootComponent);
 Glow->SetCastShadows(false);
 Glow->SetIntensityUnits(ELightUnits::Lumens);
 Glow->SetAttenuationRadius(260.f);
 static ConstructorHelpers::FObjectFinder<UStaticMesh> Sphere(TEXT("/Engine/BasicShapes/Sphere.Sphere"));
 static ConstructorHelpers::FObjectFinder<UStaticMesh> Cone(TEXT("/Engine/BasicShapes/Cone.Cone"));
 static ConstructorHelpers::FObjectFinder<UMaterialInterface> Emissive(TEXT("/Game/UI/Materials/M_SpellMotes.M_SpellMotes"));
 static ConstructorHelpers::FObjectFinder<UMaterialInterface> Rock(TEXT("/Engine/BasicShapes/BasicShapeMaterial.BasicShapeMaterial"));
 Motes->SetStaticMesh(Sphere.Object);
 Stones->SetStaticMesh(Cone.Object);
 Motes->SetMaterial(0, Emissive.Object);
 Stones->SetMaterial(0, Rock.Object);
}

void AFableSpellVisualActor::Initialize(EFableSpellVisual InVisual, const FVector& InOrigin, const FVector& InTarget, const FLinearColor& InColor)
{
 Visual = InVisual; Origin = InOrigin; Target = InTarget; Color = InColor;
 Lifetime = Visual == EFableSpellVisual::FireTornado ? 2.8f : Visual == EFableSpellVisual::EarthSpike ? 2.f : 1.5f;
 SetActorLocation(FVector::ZeroVector);
 if (UMaterialInstanceDynamic* Material = Motes->CreateAndSetMaterialInstanceDynamic(0))
 {
  TArray<FMaterialParameterInfo> Parameters; TArray<FGuid> Ids;
  Material->GetAllVectorParameterInfo(Parameters, Ids);
  for (const auto& Parameter : Parameters)
   if (Parameter.Name.ToString().Contains(TEXT("Color"))) Material->SetVectorParameterValue(Parameter.Name, Color * 1.4f);
  // Remove the engine material's checker texture from the small additive motes.
  Material->GetAllTextureParameterInfo(Parameters, Ids);
  if (UTexture* White = LoadObject<UTexture>(nullptr, TEXT("/Engine/EngineResources/WhiteSquareTexture.WhiteSquareTexture")))
   for (const auto& Parameter : Parameters) Material->SetTextureParameterValue(Parameter.Name, White);
 }
 if (UMaterialInstanceDynamic* Material = Stones->CreateAndSetMaterialInstanceDynamic(0))
  Material->SetVectorParameterValue(TEXT("Color"), FLinearColor(.18f,.12f,.065f));
 for (int32 I=0; I<MoteCount; ++I) Motes->AddInstance(FTransform::Identity);
 if (Visual == EFableSpellVisual::EarthSpike)
  for (int32 I=0; I<5; ++I) Stones->AddInstance(FTransform::Identity);
 Glow->SetLightColor(Color);
 UpdateVisual();
 SetLifeSpan(Lifetime + .1f);
}

void AFableSpellVisualActor::SetFollowTarget(AActor* InTarget)
{
	FollowTarget = InTarget;
}

void AFableSpellVisualActor::SetPersistentEffect(AActor* InCaster, const FString& InSkillId)
{
	EffectCaster = InCaster;
	PersistentSkillId = InSkillId;
}

void AFableSpellVisualActor::Tick(float DeltaSeconds)
{
 Super::Tick(DeltaSeconds);
 Elapsed += DeltaSeconds;
 if (FollowTarget.IsValid())
 {
		Target = FollowTarget->GetActorLocation() + FVector(0.f, 0.f, 70.f);
		if (!bAttachedToFollowTarget && Elapsed >= 0.65f)
		{
			AttachToActor(FollowTarget.Get(), FAttachmentTransformRules::KeepWorldTransform);
			SetActorLocation(Target);
			bAttachedToFollowTarget = true;
		}
	}
	if (!PersistentSkillId.IsEmpty() && EffectCaster.IsValid() && Elapsed > 0.25f)
	{
		EffectPulseAccumulator += DeltaSeconds;
		if (EffectPulseAccumulator >= 0.35f)
		{
			EffectPulseAccumulator = 0.f;
			FFableSpellRuntime::ApplyPersistentSkillEffects(GetWorld(), EffectCaster.Get(), PersistentSkillId, Target);
		}
	}
 UpdateVisual();
 if (Elapsed >= Lifetime) Destroy();
}

void AFableSpellVisualActor::UpdateVisual()
{
 const float Alpha = FMath::Clamp(Elapsed/Lifetime, 0.f, 1.f);
 const float Fade = FMath::Min(1.f, (1.f-Alpha)*5.f);
 const FVector Direction = (Target-Origin).GetSafeNormal();
 const FVector Right = FVector::CrossProduct(Direction, FVector::UpVector).GetSafeNormal();
 const FVector Up = FVector::CrossProduct(Right, Direction).GetSafeNormal();
 const float TravelAlpha = FMath::Clamp(Elapsed/.65f,0.f,1.f);
 const FVector Head = FMath::Lerp(Origin,Target,TravelAlpha);
 for (int32 I=0; I<MoteCount; ++I)
 {
  const float T = static_cast<float>(I)/MoteCount;
  const float Phase = T*TWO_PI;
  const float Seed = FMath::Frac(I*.618034f);
  FVector P = Head;
  FVector Size(2.5f);
  FRotator Rotation = Direction.Rotation();
  if (Visual == EFableSpellVisual::FireTornado)
  {
   const float Height = FMath::Fmod(T + Elapsed*.5f,1.f);
   const float Angle = Height*TWO_PI*2.5f + Elapsed*8.f + (I%2)*PI;
   const float Radius = 15.f + Height*65.f;
   P = Target + FVector(FMath::Cos(Angle)*Radius,FMath::Sin(Angle)*Radius,Height*210.f);
   Size = FVector(7.f,2.3f,2.3f)*(0.7f+Seed*.7f);
   Rotation = FRotator(22.f,FMath::RadiansToDegrees(Angle)+90.f,0.f);
  }
  else if (Visual == EFableSpellVisual::WaterHeal)
  {
   const float Ring = I%3;
   const float Radius = 30.f + FMath::Fmod(Alpha*1.7f+Ring*.3f,1.f)*110.f;
   const float Angle = Phase*3.f + Elapsed*.8f;
   P = Target + FVector(FMath::Cos(Angle)*Radius,FMath::Sin(Angle)*Radius,8.f+Ring*6.f);
   Size = FVector(6.f,1.4f,1.4f);
   Rotation = FRotator(0,FMath::RadiansToDegrees(Angle)+90.f,0);
  }
  else if (Visual == EFableSpellVisual::EarthSpike)
  {
   const float Radius = (30.f+Seed*85.f)*Alpha;
   P = Target + FVector(FMath::Cos(Phase)*Radius,FMath::Sin(Phase)*Radius,FMath::Max(0.f,130.f*FMath::Sin(Alpha*PI)-Seed*50.f));
   Size = FVector(1.2f+Seed*1.5f);
  }
  else if (Visual == EFableSpellVisual::AirGust)
  {
   const float Angle = Phase*3.f+Elapsed*9.f;
   const float Radius = 20.f+Seed*40.f;
   P = FMath::Lerp(Origin,Target,FMath::Clamp(TravelAlpha-T*.25f,0.f,1.f)) + (Right*FMath::Cos(Angle)+Up*FMath::Sin(Angle))*Radius;
   Size = FVector(12.f,1.f,1.f);
  }
  else if (Visual == EFableSpellVisual::CosmicTimeStep)
  {
   const float Angle = Phase*2.f+Elapsed*4.f;
   P = FMath::Lerp(Origin,Target,T) + FVector(FMath::Cos(Angle)*20.f,FMath::Sin(Angle)*20.f,30.f*FMath::Sin(Phase));
   Size = FVector(2.f+Seed*2.f);
  }
  else
  {
   const float Radius = TravelAlpha < 1.f ? 8.f+Seed*9.f : 10.f+(Elapsed-.65f)*100.f;
   P = Head - Direction*T*70.f*(1.f-TravelAlpha) + (Right*FMath::Cos(Phase*3.f)+Up*FMath::Sin(Phase*3.f))*Radius;
   Size = FVector(2.f+Seed*3.f);
  }
  // A compact hand-level origin cue, never a second full-size spell on the caster.
  if (I<8 && Elapsed<.2f) P = Origin + FVector(FMath::Cos(Phase*10.f)*12.f,FMath::Sin(Phase*10.f)*12.f,Seed*12.f);
	 const FVector LocalP = bAttachedToFollowTarget ? P - GetActorLocation() : P;
	 Motes->UpdateInstanceTransform(I,FTransform(Rotation,LocalP,Size*Fade/50.f),false,I==MoteCount-1,true);
 }
 for (int32 I=0; I<Stones->GetInstanceCount(); ++I)
 {
  const float Angle = I*TWO_PI/5.f;
  const float Growth = FMath::Min(Elapsed/.22f,1.f)*Fade;
  const float Height = (I==0 ? 160.f : 90.f)*Growth;
  const FVector P = Target+FVector(FMath::Cos(Angle)*I*18.f,FMath::Sin(Angle)*I*18.f,Height*.5f-5.f);
	  const FVector LocalP = bAttachedToFollowTarget ? P - GetActorLocation() : P;
	  Stones->UpdateInstanceTransform(I,FTransform(FRotator(0,Angle*180.f/PI,0),LocalP,FVector(.35f,.35f,Height/100.f)),false,I==Stones->GetInstanceCount()-1,true);
 }
 // Instance transforms invalidate cached bounds but do not update the component's
 // world bounds. Keep transient effects from being culled at their spawn position.
 Motes->UpdateBounds();
 Stones->UpdateBounds();
 Glow->SetWorldLocation(Visual==EFableSpellVisual::Fireball ? Head : Target+FVector(0,0,55));
 Glow->SetIntensity((Visual==EFableSpellVisual::EarthSpike ? 0.f : 65.f)*Fade);
}
