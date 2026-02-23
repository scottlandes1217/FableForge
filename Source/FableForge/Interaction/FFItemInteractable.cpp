#include "Interaction/FFItemInteractable.h"

#include "Components/StaticMeshComponent.h"
#include "Engine/GameInstance.h"
#include "RPG/Save/FableSaveSubsystem.h"

namespace
{
	bool TryAddItemToActiveInventory(UGameInstance* GameInstance, const FString& ItemId)
	{
		if (GameInstance == nullptr || ItemId.IsEmpty())
		{
			return false;
		}

		UFableSaveSubsystem* SaveSubsystem = GameInstance->GetSubsystem<UFableSaveSubsystem>();
		if (SaveSubsystem == nullptr)
		{
			return false;
		}

		TArray<FString> InventorySlots;
		TArray<FString> EquippedSlots;
		if (!SaveSubsystem->TryGetActiveInventory(InventorySlots, EquippedSlots))
		{
			return false;
		}

		const int32 EmptyIndex = InventorySlots.IndexOfByPredicate([](const FString& ExistingId)
		{
			return ExistingId.IsEmpty();
		});

		if (EmptyIndex == INDEX_NONE)
		{
			return false;
		}

		InventorySlots[EmptyIndex] = ItemId;
		return SaveSubsystem->SetActiveInventory(InventorySlots, EquippedSlots);
	}
}

AFFItemInteractable::AFFItemInteractable()
{
	ItemMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ItemMesh"));
	ItemMesh->SetupAttachment(SceneRoot);
	ItemMesh->SetCollisionProfileName(TEXT("BlockAllDynamic"));
}

bool AFFItemInteractable::CanInteract_Implementation(AActor* Interactor) const
{
	return Super::CanInteract_Implementation(Interactor) && !bPickedUp;
}

void AFFItemInteractable::Interact_Implementation(AActor* Interactor)
{
	if (bPickedUp || ItemId.IsEmpty())
	{
		return;
	}

	UGameInstance* GameInstance = GetGameInstance();
	if (!TryAddItemToActiveInventory(GameInstance, ItemId))
	{
		return;
	}

	bPickedUp = true;
	SetActorEnableCollision(false);
	SetActorHiddenInGame(true);

	if (bDestroyOnPickup)
	{
		Destroy();
	}
}
