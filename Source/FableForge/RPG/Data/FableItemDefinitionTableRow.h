#pragma once

#include "CoreMinimal.h"
#include "Engine/DataTable.h"
#include "FableItemDefinitionTableRow.generated.h"

class UStaticMesh;
class USkeletalMesh;
class UTexture2D;

USTRUCT(BlueprintType)
struct FFableItemDefinitionTableRow : public FTableRowBase
{
	GENERATED_BODY()

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Item")
	FString ItemId;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Item")
	FString DisplayName;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Item")
	FString Type = TEXT("misc");

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Item")
	bool bStackable = false;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Item")
	bool bEquipable = false;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "UI")
	TSoftObjectPtr<UTexture2D> IconTexture;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Visual")
	TSoftObjectPtr<UStaticMesh> WorldStaticMesh;

	UPROPERTY(EditAnywhere, BlueprintReadOnly, Category = "Visual")
	TSoftObjectPtr<USkeletalMesh> WorldSkeletalMesh;
};
