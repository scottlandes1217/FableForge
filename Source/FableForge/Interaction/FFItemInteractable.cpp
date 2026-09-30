#include "Interaction/FFItemInteractable.h"

#include "Components/StaticMeshComponent.h"
#include "Engine/DataTable.h"
#include "Engine/GameInstance.h"
#include "Engine/StaticMesh.h"
#include "Misc/PackageName.h"
#include "RPG/Data/FableItemDefinitionTableRow.h"
#include "RPG/Save/FableSaveSubsystem.h"

namespace
{
	UStaticMesh* ResolveDroppedItemMesh(const FString& ItemId)
	{
		if (UDataTable* ItemTable = LoadObject<UDataTable>(nullptr, TEXT("/Game/Data/DT_Items.DT_Items")))
		{
			static const FString ContextString(TEXT("InitializeDroppedItem"));
			const FFableItemDefinitionTableRow* ItemRow = ItemTable->FindRow<FFableItemDefinitionTableRow>(FName(*ItemId), ContextString, false);

			if (ItemRow == nullptr)
			{
				TArray<FFableItemDefinitionTableRow*> ItemRows;
				ItemTable->GetAllRows(ContextString, ItemRows);
				for (const FFableItemDefinitionTableRow* CandidateRow : ItemRows)
				{
					if (CandidateRow != nullptr && CandidateRow->ItemId.Equals(ItemId, ESearchCase::IgnoreCase))
					{
						ItemRow = CandidateRow;
						break;
					}
				}
			}

			if (ItemRow != nullptr && !ItemRow->WorldStaticMesh.IsNull())
			{
				if (UStaticMesh* ItemMesh = ItemRow->WorldStaticMesh.LoadSynchronous())
				{
					return ItemMesh;
				}
			}
		}

		// Existing generated prop identities match the item ids. Do not probe
		// invented asset paths (which emits missing-package errors on every drop).
		const FString PropPackage = TEXT("/Game/Items/GeneratedProps/SM_") + ItemId;
		if (!ItemId.Contains(TEXT("/")) && FPackageName::DoesPackageExist(PropPackage))
		{
			if (UStaticMesh* Prop = LoadObject<UStaticMesh>(nullptr, *(PropPackage + TEXT(".SM_") + ItemId))) return Prop;
		}
		if (ItemId == TEXT("iron_sword"))
			if (UStaticMesh* Sword = LoadObject<UStaticMesh>(nullptr, TEXT("/Game/Items/Weapons/SM_Sword.SM_Sword"))) return Sword;
		if (UStaticMesh* Container = LoadObject<UStaticMesh>(nullptr, TEXT("/Game/Medieval_Village/meshes/props/SM_box_02.SM_box_02"))) return Container;
		return LoadObject<UStaticMesh>(nullptr, TEXT("/Engine/BasicShapes/Cube.Cube"));
	}

	void ApplyManageableDropScale(UStaticMeshComponent* MeshComponent, UStaticMesh* Mesh)
	{
		if (MeshComponent == nullptr || Mesh == nullptr)
		{
			return;
		}

		const float LargestExtent = Mesh->GetBounds().BoxExtent.GetMax();
		const float TargetHalfExtent = 20.0f;
		const float UniformScale = LargestExtent > KINDA_SMALL_NUMBER
			? FMath::Clamp(TargetHalfExtent / LargestExtent, 0.05f, 1.0f)
			: 0.35f;
		MeshComponent->SetRelativeScale3D(FVector(UniformScale));
	}

	int32 AddItemToActiveInventory(UGameInstance* GameInstance, const FString& ItemId, int32 Quantity)
	{
		if (GameInstance == nullptr || ItemId.IsEmpty() || Quantity <= 0)
		{
			return 0;
		}

		UFableSaveSubsystem* SaveSubsystem = GameInstance->GetSubsystem<UFableSaveSubsystem>();
		if (SaveSubsystem == nullptr)
		{
			return 0;
		}
		return SaveSubsystem->AddActiveInventoryItem(ItemId, Quantity);
	}
}

AFFItemInteractable::AFFItemInteractable()
{
	ItemMesh = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("ItemMesh"));
	ItemMesh->SetupAttachment(SceneRoot);
	ItemMesh->SetCollisionProfileName(TEXT("BlockAllDynamic"));
}

bool AFFItemInteractable::InitializeDroppedItem(const FString& InItemId, int32 InQuantity)
{
	if (InItemId.IsEmpty() || InQuantity <= 0 || ItemMesh == nullptr)
	{
		return false;
	}

	UStaticMesh* DropMesh = ResolveDroppedItemMesh(InItemId);
	if (DropMesh == nullptr)
	{
		// A blueprint-provided mesh is still preferable to an invisible drop if an
		// asset lookup failed, while the normal path always reaches the cube fallback.
		DropMesh = ItemMesh->GetStaticMesh();
	}
	if (DropMesh == nullptr)
	{
		return false;
	}

	ItemId = InItemId;
	Quantity = InQuantity;
	bPickedUp = false;
	ItemMesh->SetStaticMesh(DropMesh);
	ApplyManageableDropScale(ItemMesh, DropMesh);
	ItemMesh->SetCollisionProfileName(TEXT("BlockAll"));
	ItemMesh->SetCollisionEnabled(ECollisionEnabled::QueryAndPhysics);
	ItemMesh->SetCollisionResponseToChannel(ECC_Visibility, ECR_Block);
	ItemMesh->SetVisibility(true, true);
	ItemMesh->SetHiddenInGame(false, true);
	SetActorHiddenInGame(false);
	SetActorEnableCollision(true);
	return true;
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
	const int32 Accepted = AddItemToActiveInventory(GameInstance, ItemId, Quantity);
	if (Accepted <= 0)
	{
		return;
	}
	Quantity -= Accepted;
	if (Quantity > 0)
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
