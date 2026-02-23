#pragma once

#include "CoreMinimal.h"
#include "Interaction/FFInteractableBase.h"
#include "FFDoorInteractable.generated.h"

class UStaticMeshComponent;

UCLASS()
class AFFDoorInteractable : public AFFInteractableBase
{
	GENERATED_BODY()

public:
	AFFDoorInteractable();

	virtual void Tick(float DeltaSeconds) override;
	virtual void BeginPlay() override;
	virtual void Interact_Implementation(AActor* Interactor) override;

protected:
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category = "Door")
	TObjectPtr<UStaticMeshComponent> DoorMesh;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Door")
	bool bStartsOpen = false;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Door", meta = (ClampMin = "-180.0", ClampMax = "180.0", Units = "deg"))
	float OpenYawOffset = 90.0f;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Door", meta = (ClampMin = "5.0", ClampMax = "720.0", Units = "deg/s"))
	float OpenCloseInterpSpeed = 150.0f;

private:
	FRotator ClosedRotation = FRotator::ZeroRotator;
	FRotator OpenRotation = FRotator::ZeroRotator;
	bool bOpen = false;
	bool bMoving = false;
};
