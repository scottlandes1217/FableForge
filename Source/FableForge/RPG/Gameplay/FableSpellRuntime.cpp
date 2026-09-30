#include "RPG/Gameplay/FableSpellRuntime.h"

#include "Engine/DataTable.h"
#include "Engine/OverlapResult.h"
#include "Engine/World.h"
#include "Components/CapsuleComponent.h"
#include "Components/PrimitiveComponent.h"
#include "FableForgeCharacter.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/Pawn.h"
#include "GameFramework/PlayerController.h"
#include "Kismet/GameplayStatics.h"
#include "RPG/Data/FableSkillSystemTableRows.h"
#include "RPG/Gameplay/FableSpellVisualActor.h"
#include "RPG/Save/FableSaveSubsystem.h"
#include "Variant_Combat/Interfaces/CombatDamageable.h"

namespace
{
	const TCHAR* SkillsTablePath = TEXT("/Game/Data/DT_Skills.DT_Skills");
	const TCHAR* EffectsTablePath = TEXT("/Game/Data/DT_SkillEffects.DT_SkillEffects");

	const FFableSkillDefinitionTableRow* FindSkill(const FString& SkillId)
	{
		// Starter definitions are canonical across runtime and UI. This keeps an
		// older editor-generated table from reintroducing the legacy category.
		static FFableSkillDefinitionTableRow StarterDefinition;
		if (FableSkillCatalog::TryGetStarterSkillDefinition(SkillId, StarterDefinition)) return &StarterDefinition;

		UDataTable* Table = LoadObject<UDataTable>(nullptr, SkillsTablePath);
		if (Table != nullptr)
		{
			TArray<FFableSkillDefinitionTableRow*> Rows;
			Table->GetAllRows(TEXT("FFableSpellRuntime::FindSkill"), Rows);
			for (const FFableSkillDefinitionTableRow* Row : Rows)
				if (Row != nullptr && Row->SkillId.Equals(SkillId, ESearchCase::IgnoreCase)) return Row;
		}
		return nullptr;
	}

	const FFableSkillEffectTableRow* FindEffect(const FString& EffectId)
	{
		UDataTable* Table = LoadObject<UDataTable>(nullptr, EffectsTablePath);
		if (Table != nullptr)
		{
			TArray<FFableSkillEffectTableRow*> Rows;
			Table->GetAllRows(TEXT("FFableSpellRuntime::FindEffect"), Rows);
			for (const FFableSkillEffectTableRow* Row : Rows)
				if (Row != nullptr && Row->EffectId.Equals(EffectId, ESearchCase::IgnoreCase)) return Row;
		}
		static FFableSkillEffectTableRow StarterFallback;
		StarterFallback = FFableSkillEffectTableRow();
		if (EffectId.Equals(TEXT("eff_fireball_burst"), ESearchCase::IgnoreCase))
		{
			StarterFallback.EffectId = TEXT("eff_fireball_burst"); StarterFallback.EffectType = EFableSkillEffectType::AreaDamage;
			StarterFallback.BaseMagnitude = 44.f; StarterFallback.RadiusUnits = 180.f; StarterFallback.ScalingStat = TEXT("Intelligence"); StarterFallback.ScalingCoefficient = 1.f;
			return &StarterFallback;
		}
		if (EffectId.Equals(TEXT("eff_burn_dot"), ESearchCase::IgnoreCase))
		{
			StarterFallback.EffectId = TEXT("eff_burn_dot"); StarterFallback.EffectType = EFableSkillEffectType::DamageOverTime;
			StarterFallback.BaseMagnitude = 6.f; StarterFallback.DurationSeconds = 5.f; StarterFallback.ScalingStat = TEXT("Intelligence"); StarterFallback.ScalingCoefficient = 0.25f;
			return &StarterFallback;
		}
		if (EffectId.Equals(TEXT("eff_heal_wave_pulse"), ESearchCase::IgnoreCase))
		{
			StarterFallback.EffectId = TEXT("eff_heal_wave_pulse"); StarterFallback.EffectType = EFableSkillEffectType::Heal;
			StarterFallback.BaseMagnitude = 30.f; StarterFallback.RadiusUnits = 220.f; StarterFallback.ScalingStat = TEXT("Wisdom"); StarterFallback.ScalingCoefficient = 0.8f;
			return &StarterFallback;
		}
		if (EffectId.Equals(TEXT("eff_stone_spike_upthrust"), ESearchCase::IgnoreCase))
		{
			StarterFallback.EffectId = TEXT("eff_stone_spike_upthrust"); StarterFallback.EffectType = EFableSkillEffectType::AreaDamage;
			StarterFallback.BaseMagnitude = 48.f; StarterFallback.RadiusUnits = 180.f; StarterFallback.ScalingStat = TEXT("Strength"); StarterFallback.ScalingCoefficient = 0.65f;
			return &StarterFallback;
		}
		if (EffectId.Equals(TEXT("eff_gust_push"), ESearchCase::IgnoreCase))
		{
			StarterFallback.EffectId = TEXT("eff_gust_push"); StarterFallback.EffectType = EFableSkillEffectType::Push;
			StarterFallback.RadiusUnits = 260.f; StarterFallback.ForceMagnitude = 550.f; StarterFallback.ScalingStat = TEXT("Dexterity"); StarterFallback.ScalingCoefficient = 0.2f;
			return &StarterFallback;
		}
		if (EffectId.Equals(TEXT("eff_gust_pull_light"), ESearchCase::IgnoreCase))
		{
			StarterFallback.EffectId = TEXT("eff_gust_pull_light"); StarterFallback.EffectType = EFableSkillEffectType::Pull;
			StarterFallback.RadiusUnits = 220.f; StarterFallback.ForceMagnitude = 260.f; StarterFallback.ScalingStat = TEXT("Intelligence"); StarterFallback.ScalingCoefficient = 0.2f;
			return &StarterFallback;
		}
		if (EffectId.Equals(TEXT("eff_time_step_move"), ESearchCase::IgnoreCase))
		{
			StarterFallback.EffectId = TEXT("eff_time_step_move"); StarterFallback.DisplayName = TEXT("Time Step Movement");
			StarterFallback.EffectType = EFableSkillEffectType::Movement; StarterFallback.ScalingStat = TEXT("Dexterity"); StarterFallback.ScalingCoefficient = 0.65f;
			return &StarterFallback;
		}
		return nullptr;
	}

	void AddTargets(UWorld* World, const FVector& Center, float Radius, AActor* ExplicitTarget, AActor* Caster, TArray<AActor*>& OutTargets)
	{
		if (IsValid(ExplicitTarget)) OutTargets.AddUnique(ExplicitTarget);
		if (Radius <= 0.0f) return;
		FCollisionShape Shape = FCollisionShape::MakeSphere(Radius);
		FCollisionQueryParams Params(SCENE_QUERY_STAT(FableSpellTargets), false, Caster);
		FCollisionObjectQueryParams ObjectParams;
		ObjectParams.AddObjectTypesToQuery(ECC_Pawn);
		ObjectParams.AddObjectTypesToQuery(ECC_WorldDynamic);
		TArray<FOverlapResult> Hits;
		World->OverlapMultiByObjectType(Hits, Center, FQuat::Identity,
			ObjectParams, Shape, Params);
		for (const FOverlapResult& Hit : Hits)
			if (IsValid(Hit.GetActor())) OutTargets.AddUnique(Hit.GetActor());
	}

	EFableSpellVisual GetSpellVisual(const FString& SkillId, const FFableSkillDefinitionTableRow& Skill)
	{
		if (SkillId.Equals(TEXT("fireball"), ESearchCase::IgnoreCase)) return EFableSpellVisual::Fireball;
		if (SkillId.Equals(TEXT("fire_tornado"), ESearchCase::IgnoreCase)) return EFableSpellVisual::FireTornado;
		if (SkillId.Equals(TEXT("heal_wave"), ESearchCase::IgnoreCase)) return EFableSpellVisual::WaterHeal;
		if (SkillId.Equals(TEXT("stone_spike"), ESearchCase::IgnoreCase)) return EFableSpellVisual::EarthSpike;
		if (SkillId.Equals(TEXT("gust"), ESearchCase::IgnoreCase)) return EFableSpellVisual::AirGust;
		if (SkillId.Equals(TEXT("time_step"), ESearchCase::IgnoreCase)) return EFableSpellVisual::CosmicTimeStep;
		if (Skill.TagsCsv.Contains(TEXT("fire"))) return EFableSpellVisual::FireTornado;
		if (Skill.TagsCsv.Contains(TEXT("water"))) return EFableSpellVisual::WaterHeal;
		if (Skill.TagsCsv.Contains(TEXT("earth"))) return EFableSpellVisual::EarthSpike;
		if (Skill.TagsCsv.Contains(TEXT("air")) || Skill.TagsCsv.Contains(TEXT("wind"))) return EFableSpellVisual::AirGust;
		return EFableSpellVisual::CosmicTimeStep;
	}

	FLinearColor GetSpellColor(EFableSpellVisual Visual)
	{
		switch (Visual)
		{
		case EFableSpellVisual::Fireball:
		case EFableSpellVisual::FireTornado: return FLinearColor(1.0f, 0.12f, 0.015f);
		case EFableSpellVisual::WaterHeal: return FLinearColor(0.02f, 0.45f, 1.0f);
		case EFableSpellVisual::EarthSpike: return FLinearColor(0.45f, 0.22f, 0.04f);
		case EFableSpellVisual::AirGust: return FLinearColor(0.55f, 0.9f, 1.0f);
		case EFableSpellVisual::CosmicTimeStep: return FLinearColor(0.55f, 0.12f, 1.0f);
		default: return FLinearColor::White;
		}
	}

	bool RestoreControlledPlayerHealth(UWorld* World, AActor* Caster, float BaseMagnitude)
	{
		if (World == nullptr || Caster == nullptr) return false;
		APlayerController* PlayerController = UGameplayStatics::GetPlayerController(World, 0);
		if (PlayerController == nullptr || PlayerController->GetPawn() != Caster || Cast<AFableForgeCharacter>(Caster) == nullptr) return false;

		UFableSaveSubsystem* SaveSubsystem = PlayerController->GetGameInstance()
			? PlayerController->GetGameInstance()->GetSubsystem<UFableSaveSubsystem>() : nullptr;
		if (SaveSubsystem == nullptr) return false;

		FFableCharacterProfile Profile;
		if (!SaveSubsystem->TryGetActiveCharacterProfile(Profile)) return false;
		int32 BaseHitPoints = 0;
		for (const FFableRaceDefinition& Race : SaveSubsystem->GetRaces())
		{
			if (Race.Id.Equals(Profile.RaceId, ESearchCase::IgnoreCase))
			{
				BaseHitPoints = Race.BaseHitPoints;
				break;
			}
		}
		if (BaseHitPoints <= 0) return false;
		SaveSubsystem->RestoreActiveHealth(FMath::Max(0.0f, BaseMagnitude) / static_cast<float>(BaseHitPoints));
		return true;
	}
}

bool FFableSpellRuntime::ExecuteSkill(UWorld* World, AActor* Caster, const FString& SkillId, const FVector& TargetLocation, AActor* ExplicitTarget)
{
	if (World == nullptr || Caster == nullptr || SkillId.IsEmpty()) return false;
	const FFableSkillDefinitionTableRow* Skill = FindSkill(SkillId);
	if (Skill == nullptr) return false;
	const FVector CastOrigin = Caster->GetActorLocation();

	TArray<FString> EffectIds;
	Skill->EffectIdsCsv.ParseIntoArray(EffectIds, TEXT("|"), true);
	bool bAppliedAnyEffect = false;
	for (const FString& EffectId : EffectIds)
	{
		bAppliedAnyEffect |= ApplyEffect(World, Caster, EffectId.TrimStartAndEnd(), TargetLocation, ExplicitTarget);
	}
	if (!bAppliedAnyEffect) return false;

	SpawnSpellVisual(World, Caster, CastOrigin, SkillId, TargetLocation, *Skill);
	return true;
}

bool FFableSpellRuntime::ResolveSafeTimeStepDestination(UWorld* World, AActor* Caster, const FVector& SelectedGroundPoint, FVector& OutDestination)
{
	if (World == nullptr || Caster == nullptr || SelectedGroundPoint.ContainsNaN()) return false;

	const ACharacter* Character = Cast<ACharacter>(Caster);
	const UCapsuleComponent* Capsule = Character != nullptr ? Character->GetCapsuleComponent() : nullptr;
	if (Capsule == nullptr) return false;

	const float CapsuleRadius = Capsule->GetScaledCapsuleRadius();
	const float CapsuleHalfHeight = Capsule->GetScaledCapsuleHalfHeight();
	if (CapsuleRadius <= 0.0f || CapsuleHalfHeight <= 0.0f) return false;

	if (FVector::Dist(Caster->GetActorLocation(), SelectedGroundPoint) > 650.f) return false;
	// Validate the selected surface, never silently choose a different floor
	// above or below the cursor.
	const FVector TraceStart = SelectedGroundPoint + FVector(0.0f, 0.0f, 5.0f);
	const FVector TraceEnd = SelectedGroundPoint - FVector(0.0f, 0.0f, 10.0f);
	FCollisionQueryParams QueryParams(SCENE_QUERY_STAT(FableTimeStepGround), true, Caster);
	FHitResult GroundHit;
	if (!World->LineTraceSingleByChannel(GroundHit, TraceStart, TraceEnd, ECC_Visibility, QueryParams)) return false;

	const UCharacterMovementComponent* Movement = Character->GetCharacterMovement();
	const float WalkableFloorZ = Movement != nullptr ? Movement->GetWalkableFloorZ() : 0.7f;
	if (GroundHit.ImpactNormal.Z < WalkableFloorZ) return false;

	const float SlopeClearance = CapsuleRadius * (1.f / GroundHit.ImpactNormal.Z - 1.f);
	const FVector Destination(GroundHit.ImpactPoint.X, GroundHit.ImpactPoint.Y, GroundHit.ImpactPoint.Z + CapsuleHalfHeight + SlopeClearance + 2.f);
	const FCollisionShape CapsuleShape = FCollisionShape::MakeCapsule(CapsuleRadius, CapsuleHalfHeight);
	if (World->OverlapBlockingTestByChannel(Destination, FQuat::Identity, ECC_Pawn, CapsuleShape, QueryParams)) return false;

	OutDestination = Destination;
	return true;
}

void FFableSpellRuntime::SpawnSpellVisual(UWorld* World, AActor* Caster, const FVector& CastOrigin, const FString& SkillId, const FVector& TargetLocation, const FFableSkillDefinitionTableRow& Skill)
{
	if (World == nullptr || Caster == nullptr) return;

	const EFableSpellVisual Visual = GetSpellVisual(SkillId, Skill);
	const FLinearColor Color = GetSpellColor(Visual);
	const FVector Origin = CastOrigin + Caster->GetActorForwardVector() * 45.f + Caster->GetActorRightVector() * 22.f + FVector(0.0f, 0.0f, 25.0f);
	FVector VisualTarget = TargetLocation;
	if (Visual == EFableSpellVisual::CosmicTimeStep)
	{
		VisualTarget = Caster->GetActorLocation();
	}
	FActorSpawnParameters SpawnParams;
	SpawnParams.SpawnCollisionHandlingOverride = ESpawnActorCollisionHandlingMethod::AlwaysSpawn;

	if (AFableSpellVisualActor* SpellActor = World->SpawnActor<AFableSpellVisualActor>(Origin, FRotator::ZeroRotator, SpawnParams))
	{
		SpellActor->Initialize(Visual, Origin, VisualTarget, Color);
		UE_LOG(LogTemp, Display, TEXT("SPELL_VISUAL skill=%s origin=%s target=%s"), *SkillId, *Origin.ToString(), *VisualTarget.ToString());
	}
}

bool FFableSpellRuntime::ApplyEffect(UWorld* World, AActor* Caster, const FString& EffectId, const FVector& TargetLocation, AActor* ExplicitTarget)
{
	const FFableSkillEffectTableRow* Effect = FindEffect(EffectId);
	if (Effect == nullptr) return false;

	TArray<AActor*> Targets;
	AddTargets(World, TargetLocation, Effect->RadiusUnits, ExplicitTarget, Caster, Targets);
	if (Effect->EffectType == EFableSkillEffectType::Heal)
	{
		if (RestoreControlledPlayerHealth(World, Caster, Effect->BaseMagnitude)) Targets.Remove(Caster);
		else if (IsValid(Caster)) Targets.AddUnique(Caster);
	}
	for (AActor* Target : Targets)
	{
		if (Effect->EffectType == EFableSkillEffectType::Damage || Effect->EffectType == EFableSkillEffectType::DamageOverTime || Effect->EffectType == EFableSkillEffectType::AreaDamage)
		{
			if (ICombatDamageable* Damageable = Cast<ICombatDamageable>(Target))
			{
				Damageable->ApplyDamage(Effect->BaseMagnitude, Caster, Target->GetActorLocation(), FVector::ZeroVector);
			}
		}
		else if (Effect->EffectType == EFableSkillEffectType::Heal)
		{
			if (ICombatDamageable* Damageable = Cast<ICombatDamageable>(Target))
			{
				Damageable->ApplyHealing(Effect->BaseMagnitude, Caster);
			}
		}
		else if (Effect->EffectType == EFableSkillEffectType::Push || Effect->EffectType == EFableSkillEffectType::ForcedMovement || Effect->EffectType == EFableSkillEffectType::Pull)
		{
			const FVector Direction = (Effect->EffectType == EFableSkillEffectType::Pull ? TargetLocation - Target->GetActorLocation() : Target->GetActorLocation() - TargetLocation).GetSafeNormal();
			if (ACharacter* Character = Cast<ACharacter>(Target)) Character->LaunchCharacter(Direction * Effect->ForceMagnitude + FVector(0, 0, Effect->ForceMagnitude * 0.25f), true, true);
			else if (UPrimitiveComponent* Primitive = Cast<UPrimitiveComponent>(Target->GetRootComponent()); Primitive != nullptr && Primitive->IsSimulatingPhysics())
				Primitive->AddImpulse(Direction * Effect->ForceMagnitude, NAME_None, true);
		}
	}

	if (Effect->EffectType == EFableSkillEffectType::Movement && Caster != nullptr
		&& EffectId.Equals(TEXT("eff_time_step_move"), ESearchCase::IgnoreCase))
	{
		FVector Destination;
		if (!ResolveSafeTimeStepDestination(World, Caster, TargetLocation, Destination)) return false;
		if (!Caster->SetActorLocation(Destination, false, nullptr, ETeleportType::TeleportPhysics)) return false;
		if (ACharacter* Character = Cast<ACharacter>(Caster))
			if (UCharacterMovementComponent* Movement = Character->GetCharacterMovement()) Movement->StopMovementImmediately();
	}
	else if (Effect->EffectType == EFableSkillEffectType::Movement && Caster != nullptr)
	{
		// Other movement effects retain their existing collision-swept behavior.
		const FVector Start = Caster->GetActorLocation();
		FVector DesiredTarget = TargetLocation;
		if (FVector::DistSquared2D(Start, DesiredTarget) < FMath::Square(20.f))
			DesiredTarget = Start + Caster->GetActorForwardVector().GetSafeNormal2D() * 650.f;
		FHitResult GroundHit;
		FCollisionQueryParams Params(SCENE_QUERY_STAT(FableMovementGround), false, Caster);
		if (World->LineTraceSingleByChannel(GroundHit, DesiredTarget + FVector(0,0,400), DesiredTarget - FVector(0,0,2000), ECC_Visibility, Params))
		{
			const ACharacter* Character = Cast<ACharacter>(Caster);
			const float HalfHeight = Character && Character->GetCapsuleComponent() ? Character->GetCapsuleComponent()->GetScaledCapsuleHalfHeight() : 0.f;
			DesiredTarget = GroundHit.ImpactPoint + FVector(0,0,HalfHeight + 2.f);
		}
		Caster->SetActorLocation(FMath::VInterpConstantTo(Start, DesiredTarget, 1.f, 650.f), true);
	}

	// A recognized effect is a valid cast even when it has no valid victim or
	// makes no profile delta (for example a full-health player heal). Unsupported
	// effect types remain rejected because this runtime cannot execute them.
	return Effect->EffectType == EFableSkillEffectType::Damage
		|| Effect->EffectType == EFableSkillEffectType::DamageOverTime
		|| Effect->EffectType == EFableSkillEffectType::AreaDamage
		|| Effect->EffectType == EFableSkillEffectType::Heal
		|| Effect->EffectType == EFableSkillEffectType::Push
		|| Effect->EffectType == EFableSkillEffectType::ForcedMovement
		|| Effect->EffectType == EFableSkillEffectType::Pull
		|| Effect->EffectType == EFableSkillEffectType::Movement;
}
