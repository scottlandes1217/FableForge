#pragma once

#include "CoreMinimal.h"
#include "Components/Viewport.h"
#include "FableTransparentViewport.generated.h"

/** Native UViewport preview world composited over the surrounding UMG page.
 * Requires r.PostProcessing.PropagateAlpha=True in renderer settings.
 * Keep the scene background black: UE scene alpha stores background visibility.
 */
UCLASS()
class UFableTransparentViewport : public UViewport
{
 GENERATED_BODY()
public:
 virtual void ReleaseSlateResources(bool bReleaseChildren) override;
 /** Configure before TakeWidget. Render above display resolution for small portraits. */
 void SetResolutionScale(float Scale) { ResolutionScale = FMath::Clamp(Scale, 1.f, 3.f); }
 /** Configure before TakeWidget. Clips the preview to the inscribed circle. */
 void SetCircularMask(bool bEnabled) { bCircularMask = bEnabled; }
protected:
 virtual TSharedRef<SWidget> RebuildWidget() override;
 virtual void SynchronizeProperties() override;
private:
 TSharedPtr<SWidget> Compositor;
 float ResolutionScale = 1.f;
 bool bCircularMask = false;
};
