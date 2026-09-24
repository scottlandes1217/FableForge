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
protected:
 virtual TSharedRef<SWidget> RebuildWidget() override;
 virtual void SynchronizeProperties() override;
private:
 TSharedPtr<SWidget> Compositor;
};
