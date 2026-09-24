#pragma once

#include "CoreMinimal.h"
#include "Components/Button.h"
#include "Fonts/SlateFontInfo.h"
#include "Misc/Paths.h"
#include "Styling/SlateTypes.h"

namespace FableBookStyle
{
	inline const FLinearColor Ink(0.105f, 0.065f, 0.040f, 1.f);
	inline const FLinearColor Parchment(0.87f, 0.79f, 0.62f, 1.f);
	inline const FLinearColor Oxblood(0.105f, 0.022f, 0.018f, 1.f);
	inline const FLinearColor Gold(0.64f, 0.40f, 0.14f, 1.f);
	inline FSlateFontInfo Font(int32 Size, bool bBold = false)
	{
		return FSlateFontInfo(FPaths::ProjectContentDir() / TEXT("Slate/Fonts") /
			(bBold ? TEXT("CrimsonText-SemiBold.ttf") : TEXT("CrimsonText-Regular.ttf")), Size);
	}
	void ApplyButton(UButton* Button, bool bCover = false);
}
