#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Actor.h"
#include "Interaction/FFInteractable.h"
#include "FFInteractableBase.generated.h"

UCLASS(Abstract)
class AFFInteractableBase : public AActor, public IFFInteractable
{
	GENERATED_BODY()

public:
	AFFInteractableBase();

	virtual bool CanInteract_Implementation(AActor* Interactor) const override;
	virtual void Interact_Implementation(AActor* Interactor) override;
	virtual FVector GetInteractionLocation_Implementation() const override;
	virtual float GetInteractionRange_Implementation() const override;
	virtual void SetHighlighted_Implementation(bool bHighlighted) override;

protected:
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Interaction")
	TObjectPtr<USceneComponent> SceneRoot;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Interaction")
	TObjectPtr<USceneComponent> InteractionPoint;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Interaction", meta = (ClampMin = "10.0", UIMin = "10.0", Units = "cm"))
	float InteractionRange = 150.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Interaction|Highlight", meta = (ClampMin = "0", ClampMax = "255"))
	int32 HighlightStencilValue = 1;

	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Interaction|Highlight")
	bool bIsHighlighted = false;

private:
	void ApplyHighlightToPrimitiveComponents(bool bEnabled) const;
};
