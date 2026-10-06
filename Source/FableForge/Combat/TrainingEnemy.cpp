// Copyright Epic Games, Inc. All Rights Reserved.

#include "TrainingEnemy.h"

#include "Animation/AnimInstance.h"
#include "Animation/AnimSequenceBase.h"
#include "Components/CapsuleComponent.h"
#include "Components/SkeletalMeshComponent.h"
#include "Components/TextRenderComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "Kismet/GameplayStatics.h"
#include "TimerManager.h"
#include "UObject/ConstructorHelpers.h"

ATrainingEnemy::ATrainingEnemy()
{
	PrimaryActorTick.bCanEverTick = true;

	GetCapsuleComponent()->InitCapsuleSize(35.0f, 90.0f);
	// The capsule is the authoritative combat volume, while the visual mesh
	// participates only in visibility traces so aiming at the torso/head still
	// resolves to this actor instead of passing through to the floor.
	GetCapsuleComponent()->SetCollisionProfileName(TEXT("Pawn"));
	GetCapsuleComponent()->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	GetMesh()->SetCollisionEnabled(ECollisionEnabled::QueryOnly);
	GetMesh()->SetCollisionResponseToAllChannels(ECR_Ignore);
	GetMesh()->SetCollisionResponseToChannel(ECC_Visibility, ECR_Block);
	GetMesh()->SetGenerateOverlapEvents(false);
	GetCharacterMovement()->MaxWalkSpeed = 180.0f;
	GetCharacterMovement()->bOrientRotationToMovement = true;
	bUseControllerRotationYaw = false;
	AutoPossessAI = EAutoPossessAI::PlacedInWorldOrSpawned;

	static ConstructorHelpers::FObjectFinder<USkeletalMesh> CharacterMesh(
		TEXT("/Game/Characters/PlayableCharacter/Meshes/basecharacter_v2.basecharacter_v2"));
	if (CharacterMesh.Succeeded())
	{
		GetMesh()->SetSkeletalMesh(CharacterMesh.Object);
		GetMesh()->SetRelativeLocation(FVector(0.0f, 0.0f, -90.0f));
		GetMesh()->SetRelativeRotation(FRotator(0.0f, -90.0f, 0.0f));
	}

	static ConstructorHelpers::FClassFinder<UAnimInstance> UnarmedAnimation(
		TEXT("/Game/Characters/PlayableCharacter/Anims/Unarmed/ABP_Unarmed"));
	if (UnarmedAnimation.Succeeded())
	{
		GetMesh()->SetAnimationMode(EAnimationMode::AnimationBlueprint);
		GetMesh()->SetAnimInstanceClass(UnarmedAnimation.Class);
	}

	HealthText = CreateDefaultSubobject<UTextRenderComponent>(TEXT("HealthText"));
	HealthText->SetupAttachment(RootComponent);
	HealthText->SetRelativeLocation(FVector(0.0f, 0.0f, 205.0f));
	HealthText->SetHorizontalAlignment(EHTA_Center);
	HealthText->SetVerticalAlignment(EVRTA_TextCenter);
	HealthText->SetWorldSize(32.0f);
	HealthText->SetTextRenderColor(FColor::White);

	CurrentHealth = MaxHealth;
}

void ATrainingEnemy::BeginPlay()
{
	Super::BeginPlay();
	CurrentHealth = MaxHealth;
	UpdateHealthText();
	UE_LOG(LogTemp, Log, TEXT("TRAINING_ENEMY_SPAWN name=%s health=%.1f"), *GetName(), CurrentHealth);
}

void ATrainingEnemy::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	if (bIsDefeated || !GetWorld())
	{
		return;
	}

	AActor* Target = FindPlayerTarget();
	if (!Target)
	{
		return;
	}

	const FVector ToTarget = Target->GetActorLocation() - GetActorLocation();
	const float DistanceSquared = ToTarget.SizeSquared2D();
	constexpr float AttackRange = 150.0f;
	if (DistanceSquared > FMath::Square(AttackRange))
	{
		AddMovementInput(ToTarget.GetSafeNormal2D());
	}
	else
	{
		SetActorRotation(FRotator(0.0f, ToTarget.Rotation().Yaw, 0.0f));
		TryAttack(Target);
	}
}

AActor* ATrainingEnemy::FindPlayerTarget() const
{
	AActor* Player = UGameplayStatics::GetPlayerPawn(this, 0);
	return Player && Player != this && Player->ActorHasTag(FName("Player")) && Cast<ICombatDamageable>(Player)
		? Player
		: nullptr;
}

void ATrainingEnemy::TryAttack(AActor* Target)
{
	if (!Target || !GetWorld() || GetWorld()->GetTimeSeconds() < NextAttackTime)
	{
		return;
	}

	NextAttackTime = GetWorld()->GetTimeSeconds() + AttackCooldown;
	if (GetMesh())
	{
		if (UAnimationAsset* Attack = LoadObject<UAnimationAsset>(nullptr, TEXT("/Game/Characters/PlayableCharacter/Anims/Unarmed/Attack/MM_Attack_01.MM_Attack_01")))
		{
			GetMesh()->PlayAnimation(Attack, false);
			const float RestoreDelay = FMath::Max(0.2f, Cast<UAnimSequenceBase>(Attack) ? Cast<UAnimSequenceBase>(Attack)->GetPlayLength() : 0.7f);
			GetWorld()->GetTimerManager().SetTimer(AttackAnimationRestoreTimerHandle, this, &ATrainingEnemy::RestoreAttackAnimation, RestoreDelay, false);
		}
	}
	TWeakObjectPtr<AActor> WeakTarget(Target);
	GetWorld()->GetTimerManager().SetTimer(AttackHitTimerHandle, FTimerDelegate::CreateLambda([this, WeakTarget]()
	{
		if (IsValid(this)) ExecuteAttackHit(WeakTarget);
	}), 0.25f, false);
}

void ATrainingEnemy::ExecuteAttackHit(TWeakObjectPtr<AActor> WeakTarget)
{
	AActor* Target = WeakTarget.Get();
	if (!Target || bIsDefeated || !GetWorld()) return;
	TArray<FHitResult> Hits;
	const FVector Start = GetActorLocation() + FVector(0.0f, 0.0f, 65.0f);
	const FVector End = Start + GetActorForwardVector() * 115.0f;
	FCollisionQueryParams QueryParams(SCENE_QUERY_STAT(TrainingEnemyAttack), false, this);
	FCollisionShape Shape = FCollisionShape::MakeSphere(55.0f);

	if (!GetWorld()->SweepMultiByChannel(Hits, Start, End, FQuat::Identity, ECC_Pawn, Shape, QueryParams))
	{
		return;
	}

	for (const FHitResult& Hit : Hits)
	{
		AActor* HitActor = Hit.GetActor();
		if (HitActor && HitActor != this && HitActor == Target && HitActor->ActorHasTag(FName("Player")))
		{
			if (ICombatDamageable* Damageable = Cast<ICombatDamageable>(HitActor))
			{
				Damageable->ApplyDamage(AttackDamage, this, Hit.ImpactPoint, FVector::ZeroVector);
				UE_LOG(LogTemp, Log, TEXT("TRAINING_ENEMY_ATTACK attacker=%s target=%s damage=%.1f cooldown=%.2f"), *GetName(), *HitActor->GetName(), AttackDamage, AttackCooldown);
			}
			return;
		}
	}
}

void ATrainingEnemy::RestoreAttackAnimation()
{
	if (GetMesh())
	{
		GetMesh()->SetAnimationMode(EAnimationMode::AnimationBlueprint);
		GetMesh()->InitAnim(true);
	}
}

void ATrainingEnemy::ApplyDamage(float Damage, AActor* DamageCauser, const FVector& DamageLocation, const FVector& DamageImpulse)
{
	if (bIsDefeated || Damage <= 0.0f)
	{
		return;
	}

	const float AppliedDamage = FMath::Min(Damage, CurrentHealth);
	CurrentHealth -= AppliedDamage;
	UpdateHealthText();
	UE_LOG(LogTemp, Log, TEXT("TRAINING_ENEMY_DAMAGE victim=%s amount=%.1f remaining=%.1f causer=%s"), *GetName(), AppliedDamage, CurrentHealth, DamageCauser ? *DamageCauser->GetName() : TEXT("None"));

	if (DamageImpulse != FVector::ZeroVector)
	{
		GetCharacterMovement()->AddImpulse(DamageImpulse, true);
	}
	if (CurrentHealth <= 0.0f)
	{
		HandleDeath();
	}
}

void ATrainingEnemy::HandleDeath()
{
	if (bIsDefeated)
	{
		return;
	}

	bIsDefeated = true;
	GetCapsuleComponent()->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	GetCharacterMovement()->DisableMovement();
	GetMesh()->SetVisibility(false, true);
	HealthText->SetVisibility(false, true);
	UE_LOG(LogTemp, Log, TEXT("TRAINING_ENEMY_DEFEATED name=%s respawn_delay=%.2f"), *GetName(), RespawnDelay);

	GetWorld()->GetTimerManager().SetTimer(RespawnTimerHandle, this, &ATrainingEnemy::ResetTrainingEnemy, RespawnDelay, false);
}

void ATrainingEnemy::ResetTrainingEnemy()
{
	bIsDefeated = false;
	CurrentHealth = MaxHealth;
	NextAttackTime = GetWorld() ? GetWorld()->GetTimeSeconds() + AttackCooldown : 0.0f;
	GetCapsuleComponent()->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	GetCharacterMovement()->SetMovementMode(MOVE_Walking);
	GetMesh()->SetVisibility(true, true);
	HealthText->SetVisibility(true, true);
	UpdateHealthText();
	UE_LOG(LogTemp, Log, TEXT("TRAINING_ENEMY_RESPAWN name=%s health=%.1f"), *GetName(), CurrentHealth);
}

void ATrainingEnemy::ApplyHealing(float Healing, AActor* Healer)
{
	if (!bIsDefeated && Healing > 0.0f)
	{
		CurrentHealth = FMath::Min(MaxHealth, CurrentHealth + Healing);
		UpdateHealthText();
	}
}

void ATrainingEnemy::NotifyDanger(const FVector& DangerLocation, AActor* DangerSource)
{
	UE_LOG(LogTemp, Verbose, TEXT("TRAINING_ENEMY_DANGER name=%s source=%s location=%s"), *GetName(), DangerSource ? *DangerSource->GetName() : TEXT("None"), *DangerLocation.ToCompactString());
}

void ATrainingEnemy::UpdateHealthText()
{
	if (HealthText)
	{
		HealthText->SetText(FText::FromString(FString::Printf(TEXT("HP %.0f / %.0f"), CurrentHealth, MaxHealth)));
	}
}
