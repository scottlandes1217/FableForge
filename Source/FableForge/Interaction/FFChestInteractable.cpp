#include "Interaction/FFChestInteractable.h"

#include "Components/StaticMeshComponent.h"
#include "Engine/GameInstance.h"
#include "FableForgePlayerController.h"
#include "RPG/Save/FableSaveSubsystem.h"

AFFChestInteractable::AFFChestInteractable()
{
	ChestMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ChestMesh"));
	ChestMesh->SetupAttachment(SceneRoot);
	ChestMesh->SetCollisionProfileName(TEXT("BlockAll"));
}

bool AFFChestInteractable::CanInteract_Implementation(AActor* Interactor) const
{
	return Super::CanInteract_Implementation(Interactor) && ChestItems.Num() > 0;
}

void AFFChestInteractable::Interact_Implementation(AActor* Interactor)
{
	APlayerController* PlayerController = nullptr;

	if (const APawn* InteractorPawn = Cast<APawn>(Interactor))
	{
		PlayerController = Cast<APlayerController>(InteractorPawn->GetController());
	}
	else
	{
		PlayerController = Cast<APlayerController>(Interactor);
	}

	AFableForgePlayerController* FableController = Cast<AFableForgePlayerController>(PlayerController);
	if (FableController != nullptr)
	{
		FableController->OpenChest(this);
	}
}

const TArray<FFChestItemEntry>& AFFChestInteractable::GetChestItems() const
{
	return ChestItems;
}

FString AFFChestInteractable::GetChestDisplayName() const
{
	return ChestDisplayName.IsEmpty() ? FString(TEXT("Chest")) : ChestDisplayName;
}

bool AFFChestInteractable::TakeOneAtIndex(int32 ItemIndex, APlayerController* LootingController)
{
	if (!ChestItems.IsValidIndex(ItemIndex))
	{
		return false;
	}

	FFChestItemEntry& ItemEntry = ChestItems[ItemIndex];
	if (ItemEntry.ItemId.IsEmpty() || ItemEntry.Quantity <= 0)
	{
		return false;
	}

	if (!TryAddItemToInventory(LootingController, ItemEntry.ItemId))
	{
		return false;
	}

	ItemEntry.Quantity -= 1;
	CleanupEmptyEntries();
	return true;
}

int32 AFFChestInteractable::TakeAll(APlayerController* LootingController)
{
	UGameInstance* GameInstance = LootingController ? LootingController->GetGameInstance() : nullptr;
	UFableSaveSubsystem* SaveSubsystem = GameInstance ? GameInstance->GetSubsystem<UFableSaveSubsystem>() : nullptr;
	TArray<FString> InventorySlots;
	TArray<FString> EquippedSlots;
	if (!SaveSubsystem || !SaveSubsystem->TryGetActiveInventory(InventorySlots, EquippedSlots))
	{
		return 0;
	}

	// Build one transaction: saving and broadcasting after each item caused repeated UI and mesh rebuilds.
	TArray<FFChestItemEntry> RemainingItems = ChestItems;
	int32 ItemsTaken = 0;
	int32 NextInventorySlot = 0;
	for (int32 Index = RemainingItems.Num() - 1; Index >= 0; --Index)
	{
		FFChestItemEntry& ItemEntry = RemainingItems[Index];
		if (ItemEntry.ItemId.IsEmpty())
		{
			continue;
		}
		while (ItemEntry.Quantity > 0)
		{
			while (InventorySlots.IsValidIndex(NextInventorySlot) && !InventorySlots[NextInventorySlot].IsEmpty())
			{
				++NextInventorySlot;
			}
			if (!InventorySlots.IsValidIndex(NextInventorySlot))
			{
				break;
			}
			InventorySlots[NextInventorySlot++] = ItemEntry.ItemId;
			--ItemEntry.Quantity;
			++ItemsTaken;
		}
	}

	if (ItemsTaken == 0)
	{
		CleanupEmptyEntries();
		return 0;
	}
	if (!SaveSubsystem->SetActiveInventory(InventorySlots, EquippedSlots))
	{
		return 0;
	}
	ChestItems = MoveTemp(RemainingItems);
	CleanupEmptyEntries();
	return ItemsTaken;
}

bool AFFChestInteractable::TryAddItemToInventory(APlayerController* LootingController, const FString& ItemId) const
{
	if (LootingController == nullptr || ItemId.IsEmpty())
	{
		return false;
	}

	UGameInstance* GameInstance = LootingController->GetGameInstance();
	if (GameInstance == nullptr)
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

void AFFChestInteractable::CleanupEmptyEntries()
{
	for (int32 Index = ChestItems.Num() - 1; Index >= 0; --Index)
	{
		const FFChestItemEntry& ItemEntry = ChestItems[Index];
		if (ItemEntry.Quantity <= 0 || ItemEntry.ItemId.IsEmpty())
		{
			ChestItems.RemoveAt(Index);
		}
	}
}
