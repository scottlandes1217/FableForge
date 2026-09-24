#pragma once

#include "CoreMinimal.h"

class AActor;
class UWorld;

/** Runtime bridge between skill/effect data rows and world gameplay. */
class FFableSpellRuntime
{
public:
	static bool ExecuteSkill(UWorld* World, AActor* Caster, const FString& SkillId, const FVector& TargetLocation, AActor* ExplicitTarget = nullptr);

private:
	static void ApplyEffect(UWorld* World, AActor* Caster, const FString& EffectId, const FVector& TargetLocation, AActor* ExplicitTarget);
};
