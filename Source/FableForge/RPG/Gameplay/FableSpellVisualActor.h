#pragma once
#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "FableSpellVisualActor.generated.h"
class UInstancedStaticMeshComponent;
class UPointLightComponent;
class AActor;
UENUM()
enum class EFableSpellVisual : uint8 { Fireball, FireTornado, WaterHeal, EarthSpike, AirGust, CosmicTimeStep };
/** Bounded, transient spell motes and ground geometry; never participates in collision. */
UCLASS(NotPlaceable, Transient)
class AFableSpellVisualActor : public AActor
{
 GENERATED_BODY()
public:
 AFableSpellVisualActor();
 void Initialize(EFableSpellVisual InVisual, const FVector& InOrigin, const FVector& InTarget, const FLinearColor& InColor);
 void SetFollowTarget(AActor* InTarget);
 void SetPersistentEffect(AActor* InCaster, const FString& InSkillId);
protected:
 virtual void Tick(float DeltaSeconds) override;
private:
 void UpdateVisual();
 UPROPERTY() TObjectPtr<UInstancedStaticMeshComponent> Motes;
 UPROPERTY() TObjectPtr<UInstancedStaticMeshComponent> Stones;
 UPROPERTY() TObjectPtr<UPointLightComponent> Glow;
 EFableSpellVisual Visual = EFableSpellVisual::Fireball;
 FVector Origin = FVector::ZeroVector;
 FVector Target = FVector::ZeroVector;
 FLinearColor Color = FLinearColor::White;
 float Elapsed = 0.f;
 float Lifetime = 1.f;
 TWeakObjectPtr<AActor> FollowTarget;
 bool bAttachedToFollowTarget = false;
 TWeakObjectPtr<AActor> EffectCaster;
 FString PersistentSkillId;
 float EffectPulseAccumulator = 0.f;
};
