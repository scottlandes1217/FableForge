#pragma once

#include "CoreMinimal.h"
#include "Interaction/FFInteractableBase.h"
#include "FFItemInteractable.generated.h"

class UStaticMeshComponent;

UCLASS()
class AFFItemInteractable : public AFFInteractableBase
{
	GENERATED_BODY()

public:
	AFFItemInteractable();

	/** Initializes this actor as a visible, pickup-able world drop. */
	UFUNCTION(BlueprintCallable, Category = "Item")
	bool InitializeDroppedItem(const FString& InItemId, int32 InQuantity = 1);

	const FString& GetItemId() const { return ItemId; }
	int32 GetQuantity() const { return Quantity; }

	virtual bool CanInteract_Implementation(AActor* Interactor) const override;
	virtual void Interact_Implementation(AActor* Interactor) override;

protected:
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Item")
	TObjectPtr<UStaticMeshComponent> ItemMesh;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Item")
	FString ItemId = TEXT("health_potion");

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Item", meta = (ClampMin = "1", UIMin = "1"))
	int32 Quantity = 1;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Item")
	bool bDestroyOnPickup = true;

	UPROPERTY(BlueprintReadOnly, Category = "Item")
	bool bPickedUp = false;
};
