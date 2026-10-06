#pragma once

#include "CoreMinimal.h"

class AActor;
class UWorld;
struct FFableSkillDefinitionTableRow;

/** Runtime bridge between skill/effect data rows and world gameplay. */
class FFableSpellRuntime
{
public:
	static bool ExecuteSkill(UWorld* World, AActor* Caster, const FString& SkillId, const FVector& TargetLocation, AActor* ExplicitTarget = nullptr);
	static bool ApplyPersistentSkillEffects(UWorld* World, AActor* Caster, const FString& SkillId, const FVector& TargetLocation);
	static bool ResolveSafeTimeStepDestination(UWorld* World, AActor* Caster, const FVector& SelectedGroundPoint, FVector& OutDestination);

private:
	static bool ApplyEffect(UWorld* World, AActor* Caster, const FString& EffectId, const FVector& TargetLocation, AActor* ExplicitTarget);
	static void SpawnSpellVisual(UWorld* World, AActor* Caster, const FVector& CastOrigin, const FString& SkillId, const FVector& TargetLocation, const FFableSkillDefinitionTableRow& Skill, AActor* ExplicitTarget = nullptr);
};
