// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "Variant_Combat/Interfaces/CombatDamageable.h"
#include "TrainingEnemy.generated.h"

class UTextRenderComponent;

/** A small, code-only combat target used to exercise the active RPG prototype. */
UCLASS()
class FABLEFORGE_API ATrainingEnemy : public ACharacter, public ICombatDamageable
{
	GENERATED_BODY()

public:
	ATrainingEnemy();

	/** Maximum health restored whenever the enemy respawns. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Training Enemy|Health", meta=(ClampMin="1.0"))
	float MaxHealth = 100.0f;

	/** Current health of the enemy. */
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category="Training Enemy|Health", meta=(ClampMin="0.0"))
	float CurrentHealth = 0.0f;

	/** Time between autonomous melee attacks. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Training Enemy|Attack", meta=(ClampMin="0.1", Units="s"))
	float AttackCooldown = 1.25f;

	/** Damage dealt by each successful melee sweep. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Training Enemy|Attack", meta=(ClampMin="0.0"))
	float AttackDamage = 10.0f;

	/** Delay before a defeated enemy becomes visible and damageable again. */
	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category="Training Enemy|Health", meta=(ClampMin="0.1", Units="s"))
	float RespawnDelay = 2.0f;

	// ICombatDamageable
	virtual void ApplyDamage(float Damage, AActor* DamageCauser, const FVector& DamageLocation, const FVector& DamageImpulse) override;
	virtual void HandleDeath() override;
	virtual void ApplyHealing(float Healing, AActor* Healer) override;
	virtual void NotifyDanger(const FVector& DangerLocation, AActor* DangerSource) override;

protected:
	virtual void BeginPlay() override;
	virtual void Tick(float DeltaSeconds) override;

private:
	void UpdateHealthText();
	void ResetTrainingEnemy();
	void TryAttack(AActor* Target);
	void ExecuteAttackHit(TWeakObjectPtr<AActor> Target);
	void RestoreAttackAnimation();
	AActor* FindPlayerTarget() const;

	UPROPERTY(VisibleAnywhere, Category="Training Enemy|Components")
	TObjectPtr<UTextRenderComponent> HealthText;

	FTimerHandle RespawnTimerHandle;
	FTimerHandle AttackAnimationRestoreTimerHandle;
	FTimerHandle AttackHitTimerHandle;
	float NextAttackTime = 0.0f;
	bool bIsDefeated = false;
};
