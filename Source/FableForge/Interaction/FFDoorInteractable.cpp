#include "Interaction/FFDoorInteractable.h"

#include "Components/StaticMeshComponent.h"

AFFDoorInteractable::AFFDoorInteractable()
{
	PrimaryActorTick.bCanEverTick = true;

	DoorMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("DoorMesh"));
	DoorMesh->SetupAttachment(SceneRoot);
	DoorMesh->SetCollisionProfileName(TEXT("BlockAll"));
}

void AFFDoorInteractable::BeginPlay()
{
	Super::BeginPlay();

	ClosedRotation = DoorMesh ? DoorMesh->GetRelativeRotation() : FRotator::ZeroRotator;
	OpenRotation = ClosedRotation + FRotator(0.0f, OpenYawOffset, 0.0f);

	bOpen = bStartsOpen;
	if (DoorMesh)
	{
		DoorMesh->SetRelativeRotation(bOpen ? OpenRotation : ClosedRotation);
	}
}

void AFFDoorInteractable::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	if (!bMoving || DoorMesh == nullptr)
	{
		return;
	}

	const FRotator TargetRotation = bOpen ? OpenRotation : ClosedRotation;
	const FRotator NewRotation = FMath::RInterpConstantTo(DoorMesh->GetRelativeRotation(), TargetRotation, DeltaSeconds, OpenCloseInterpSpeed);
	DoorMesh->SetRelativeRotation(NewRotation);

	if (NewRotation.Equals(TargetRotation, 0.5f))
	{
		DoorMesh->SetRelativeRotation(TargetRotation);
		bMoving = false;
	}
}

void AFFDoorInteractable::Interact_Implementation(AActor* Interactor)
{
	Super::Interact_Implementation(Interactor);

	bOpen = !bOpen;
	bMoving = true;
}
