#pragma once

#include "CoreMinimal.h"
#include "Components/Button.h"
#include "FableActionButton.generated.h"

DECLARE_DYNAMIC_MULTICAST_DELEGATE_OneParam(FFableActionButtonClickedSignature, FName, ActionId);

UCLASS()
class UFableActionButton : public UButton
{
	GENERATED_BODY()

public:
	UFableActionButton();

	void InitializeAction(FName InActionId);

	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category = "Action")
	FName ActionId;

	UPROPERTY(BlueprintAssignable, Category = "Action")
	FFableActionButtonClickedSignature OnActionClicked;

private:
	UFUNCTION()
	void HandleInternalClicked();

	bool bIsBoundToClick = false;
};
