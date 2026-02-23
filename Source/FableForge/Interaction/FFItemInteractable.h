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

	virtual bool CanInteract_Implementation(AActor* Interactor) const override;
	virtual void Interact_Implementation(AActor* Interactor) override;

protected:
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Item")
	TObjectPtr<UStaticMeshComponent> ItemMesh;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Item")
	FString ItemId = TEXT("health_potion");

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Item")
	bool bDestroyOnPickup = true;

	UPROPERTY(BlueprintReadOnly, Category = "Item")
	bool bPickedUp = false;
};
