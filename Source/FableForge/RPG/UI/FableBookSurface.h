#pragma once

#include "CoreMinimal.h"
#include "Components/Widget.h"
#include "FableBookSurface.generated.h"

class SFableBookSurface;

/** An opaque, resolution independent painted book; menu content is layered above it. */
UCLASS()
class FABLEFORGE_API UFableBookSurface : public UWidget
{
	GENERATED_BODY()
public:
	UFableBookSurface(const FObjectInitializer& ObjectInitializer);
	UPROPERTY(EditAnywhere, BlueprintReadWrite, Category="Book")
	bool bOpenBook = true;
	UFUNCTION(BlueprintCallable, Category="Book")
	void SetOpenBook(bool bOpen);
	virtual void SynchronizeProperties() override;
	virtual void ReleaseSlateResources(bool bReleaseChildren) override;
protected:
	virtual TSharedRef<SWidget> RebuildWidget() override;
private:
	TSharedPtr<SFableBookSurface> BookSurface;
};
