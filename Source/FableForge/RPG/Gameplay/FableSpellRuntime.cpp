#include "RPG/Gameplay/FableSpellRuntime.h"

#include "DrawDebugHelpers.h"
#include "Engine/DataTable.h"
#include "Engine/OverlapResult.h"
#include "Components/PrimitiveComponent.h"
#include "GameFramework/Character.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/Pawn.h"
#include "Kismet/GameplayStatics.h"
#include "RPG/Data/FableSkillSystemTableRows.h"
#include "Variant_Combat/Interfaces/CombatDamageable.h"

namespace
{
	const TCHAR* SkillsTablePath = TEXT("/Game/Data/DT_Skills.DT_Skills");
	const TCHAR* EffectsTablePath = TEXT("/Game/Data/DT_SkillEffects.DT_SkillEffects");

	const FFableSkillDefinitionTableRow* FindSkill(const FString& SkillId)
	{
		UDataTable* Table = LoadObject<UDataTable>(nullptr, SkillsTablePath);
		if (Table == nullptr) return nullptr;
		TArray<FFableSkillDefinitionTableRow*> Rows;
		Table->GetAllRows(TEXT("FFableSpellRuntime::FindSkill"), Rows);
		for (const FFableSkillDefinitionTableRow* Row : Rows)
			if (Row != nullptr && Row->SkillId.Equals(SkillId, ESearchCase::IgnoreCase)) return Row;
		return nullptr;
	}

	const FFableSkillEffectTableRow* FindEffect(const FString& EffectId)
	{
		UDataTable* Table = LoadObject<UDataTable>(nullptr, EffectsTablePath);
		if (Table == nullptr) return nullptr;
		TArray<FFableSkillEffectTableRow*> Rows;
		Table->GetAllRows(TEXT("FFableSpellRuntime::FindEffect"), Rows);
		for (const FFableSkillEffectTableRow* Row : Rows)
			if (Row != nullptr && Row->EffectId.Equals(EffectId, ESearchCase::IgnoreCase)) return Row;
		return nullptr;
	}

	void AddTargets(UWorld* World, const FVector& Center, float Radius, AActor* ExplicitTarget, AActor* Caster, TArray<AActor*>& OutTargets)
	{
		if (IsValid(ExplicitTarget)) OutTargets.AddUnique(ExplicitTarget);
		if (Radius <= 0.0f) return;
		FCollisionShape Shape = FCollisionShape::MakeSphere(Radius);
		FCollisionQueryParams Params(SCENE_QUERY_STAT(FableSpellTargets), false, Caster);
		TArray<FOverlapResult> Hits;
		World->OverlapMultiByObjectType(Hits, Center, FQuat::Identity,
			FCollisionObjectQueryParams(ECC_Pawn | ECC_WorldDynamic), Shape, Params);
		for (const FOverlapResult& Hit : Hits)
			if (IsValid(Hit.GetActor())) OutTargets.AddUnique(Hit.GetActor());
	}
}

bool FFableSpellRuntime::ExecuteSkill(UWorld* World, AActor* Caster, const FString& SkillId, const FVector& TargetLocation, AActor* ExplicitTarget)
{
	if (World == nullptr || Caster == nullptr || SkillId.IsEmpty()) return false;
	const FFableSkillDefinitionTableRow* Skill = FindSkill(SkillId);
	if (Skill == nullptr) return false;

	TArray<FString> EffectIds;
	Skill->EffectIdsCsv.ParseIntoArray(EffectIds, TEXT("|"), true);
	for (const FString& EffectId : EffectIds) ApplyEffect(World, Caster, EffectId.TrimStartAndEnd(), TargetLocation, ExplicitTarget);

	const FColor DebugColor = Skill->TagsCsv.Contains(TEXT("fire")) ? FColor::Red :
		Skill->TagsCsv.Contains(TEXT("water")) ? FColor::Cyan :
		Skill->TagsCsv.Contains(TEXT("earth")) ? FColor::Green : FColor::White;
	DrawDebugLine(World, Caster->GetActorLocation(), TargetLocation, DebugColor, false, 1.25f, 0, 2.0f);
	DrawDebugSphere(World, TargetLocation, FMath::Max(22.0f, Skill->RadiusUnits), 24, DebugColor, false, 1.25f, 0, 2.0f);
	return true;
}

void FFableSpellRuntime::ApplyEffect(UWorld* World, AActor* Caster, const FString& EffectId, const FVector& TargetLocation, AActor* ExplicitTarget)
{
	const FFableSkillEffectTableRow* Effect = FindEffect(EffectId);
	if (Effect == nullptr) return;

	TArray<AActor*> Targets;
	AddTargets(World, TargetLocation, Effect->RadiusUnits, ExplicitTarget, Caster, Targets);
	for (AActor* Target : Targets)
	{
		if (Effect->EffectType == EFableSkillEffectType::Damage || Effect->EffectType == EFableSkillEffectType::DamageOverTime || Effect->EffectType == EFableSkillEffectType::AreaDamage)
		{
			if (ICombatDamageable* Damageable = Cast<ICombatDamageable>(Target))
				Damageable->ApplyDamage(Effect->BaseMagnitude, Caster, Target->GetActorLocation(), FVector::ZeroVector);
		}
		else if (Effect->EffectType == EFableSkillEffectType::Heal)
		{
			if (ICombatDamageable* Damageable = Cast<ICombatDamageable>(Target)) Damageable->ApplyHealing(Effect->BaseMagnitude, Caster);
		}
		else if (Effect->EffectType == EFableSkillEffectType::Push || Effect->EffectType == EFableSkillEffectType::ForcedMovement || Effect->EffectType == EFableSkillEffectType::Pull)
		{
			const FVector Direction = (Effect->EffectType == EFableSkillEffectType::Pull ? TargetLocation - Target->GetActorLocation() : Target->GetActorLocation() - TargetLocation).GetSafeNormal();
			if (ACharacter* Character = Cast<ACharacter>(Target)) Character->LaunchCharacter(Direction * Effect->ForceMagnitude + FVector(0, 0, Effect->ForceMagnitude * 0.25f), true, true);
			else if (UPrimitiveComponent* Primitive = Cast<UPrimitiveComponent>(Target->GetRootComponent())) Primitive->AddImpulse(Direction * Effect->ForceMagnitude, NAME_None, true);
		}
	}

	if (Effect->EffectType == EFableSkillEffectType::Movement && Caster != nullptr)
	{
		const FVector Destination = FMath::VInterpConstantTo(Caster->GetActorLocation(), TargetLocation, 1.0f, 650.0f);
		Caster->SetActorLocation(Destination, true);
	}
}
