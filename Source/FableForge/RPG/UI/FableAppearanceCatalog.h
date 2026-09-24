#pragma once
#include "CoreMinimal.h"

namespace FableAppearanceAssets
{
struct FStyle
{
 FString Id;
 FString DisplayName;
 FString MaleMeshPath;
 FString FemaleMeshPath;
};
struct FColorPreset
{
 FString Id;
 FString DisplayName;
 FLinearColor Color=FLinearColor::White;
};
// Stable IDs are saved with characters. Lists contain only entries available
// for the requested body; the explicit "none" choice is always included.
FABLEFORGE_API const TArray<FStyle>& ListHairStyles(bool Female=false);
FABLEFORGE_API const TArray<FStyle>& ListBeardStyles(bool Female=false);
FABLEFORGE_API const TArray<FColorPreset>& ListHairColors();
FABLEFORGE_API const TArray<FColorPreset>& ListEyeColors();
}
