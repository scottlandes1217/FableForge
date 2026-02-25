#pragma once

#include "CoreMinimal.h"
#include "Interaction/FFInteractableBase.h"
#include "FFChestInteractable.generated.h"

USTRUCT(BlueprintType)
struct FFChestItemEntry
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Chest")
	FString ItemId;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Chest", meta = (ClampMin = "1", UIMin = "1"))
	int32 Quantity = 1;
};

class UStaticMeshComponent;

UCLASS()
class AFFChestInteractable : public AFFInteractableBase
{
	GENERATED_BODY()

public:
	AFFChestInteractable();

	virtual bool CanInteract_Implementation(AActor* Interactor) const override;
	virtual void Interact_Implementation(AActor* Interactor) override;

	const TArray<FFChestItemEntry>& GetChestItems() const;
	FString GetChestDisplayName() const;
	bool TakeOneAtIndex(int32 ItemIndex, APlayerController* LootingController);
	int32 TakeAll(APlayerController* LootingController);

protected:
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Chest")
	TObjectPtr<UStaticMeshComponent> ChestMesh;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Chest")
	TArray<FFChestItemEntry> ChestItems;

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Chest")
	FString ChestDisplayName = TEXT("Chest");

private:
	bool TryAddItemToInventory(APlayerController* LootingController, const FString& ItemId) const;
	void CleanupEmptyEntries();
};
