#pragma once

#include "CoreMinimal.h"
#include "Blueprint/DragDropOperation.h"
#include "FableInventoryDragDropOperation.generated.h"

UCLASS()
class UFableInventoryDragDropOperation : public UDragDropOperation
{
	GENERATED_BODY()

public:
	UPROPERTY(BlueprintReadWrite, Category = "Inventory")
	FName SourceSlotId;

	UPROPERTY(BlueprintReadWrite, Category = "Inventory")
	FString PayloadId;

	UPROPERTY(BlueprintReadWrite, Category = "Inventory")
	FString PayloadLabel;
};
