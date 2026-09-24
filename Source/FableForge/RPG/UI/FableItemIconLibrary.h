#pragma once

#include "CoreMinimal.h"
class UTexture2D;

/** Shared, GC-safe item model thumbnails, with generated emblems where no model is available. */
namespace FableItemIcons
{
	UTexture2D* Get(const FString& ItemId);
}
