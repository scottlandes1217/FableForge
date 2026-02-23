#include "Interaction/FFInteractableBase.h"

#include "Components/PrimitiveComponent.h"

AFFInteractableBase::AFFInteractableBase()
{
	PrimaryActorTick.bCanEverTick = false;

	SceneRoot = CreateDefaultSubobject<USceneComponent>(TEXT("Root"));
	RootComponent = SceneRoot;

	InteractionPoint = CreateDefaultSubobject<USceneComponent>(TEXT("InteractionPoint"));
	InteractionPoint->SetupAttachment(SceneRoot);
}

bool AFFInteractableBase::CanInteract_Implementation(AActor* Interactor) const
{
	return IsValid(Interactor);
}

void AFFInteractableBase::Interact_Implementation(AActor* Interactor)
{
}

FVector AFFInteractableBase::GetInteractionLocation_Implementation() const
{
	return InteractionPoint ? InteractionPoint->GetComponentLocation() : GetActorLocation();
}

float AFFInteractableBase::GetInteractionRange_Implementation() const
{
	return InteractionRange;
}

void AFFInteractableBase::SetHighlighted_Implementation(bool bHighlighted)
{
	if (bIsHighlighted == bHighlighted)
	{
		return;
	}

	bIsHighlighted = bHighlighted;
	ApplyHighlightToPrimitiveComponents(bHighlighted);
}

void AFFInteractableBase::ApplyHighlightToPrimitiveComponents(bool bEnabled) const
{
	TInlineComponentArray<UPrimitiveComponent*> PrimitiveComponents;
	GetComponents<UPrimitiveComponent>(PrimitiveComponents);

	for (UPrimitiveComponent* PrimitiveComponent : PrimitiveComponents)
	{
		if (PrimitiveComponent == nullptr)
		{
			continue;
		}

		PrimitiveComponent->SetRenderCustomDepth(bEnabled);
		PrimitiveComponent->SetCustomDepthStencilValue(HighlightStencilValue);
	}
}
