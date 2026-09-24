#pragma once

#include "CoreMinimal.h"
#include "Blueprint/UserWidget.h"
#include "RPG/Data/FableForgeRPGTypes.h"
#include "FableMainMenuWidget.generated.h"

class UBorder;
class UEditableTextBox;
class USlider;
class UTextBlock;
class USkeletalMeshComponent;
class UPointLightComponent;
class UVerticalBox;
class UHorizontalBox;
class UStaticMeshComponent;
class UViewport;
class UFableActionButton;

UCLASS()
class UFableMainMenuWidget : public UUserWidget
{
	GENERATED_BODY()

public:
	UFableMainMenuWidget(const FObjectInitializer& ObjectInitializer);

	virtual TSharedRef<SWidget> RebuildWidget() override;
	virtual void NativeConstruct() override;
	virtual void NativeDestruct() override;

	void OpenMainMenu();
	virtual FReply NativeOnMouseButtonDown(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual FReply NativeOnMouseButtonUp(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual FReply NativeOnMouseMove(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual FReply NativeOnKeyDown(const FGeometry& Geometry, const FKeyEvent& Event) override;
	virtual FReply NativeOnMouseWheel(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual FReply NativeOnMouseButtonDoubleClick(const FGeometry& Geometry, const FPointerEvent& Event) override;
	virtual void NativeOnMouseCaptureLost(const FCaptureLostEvent& Event) override;

private:
	enum class EMainMenuState : uint8
	{
		Main,
		CharacterSelect,
		SlotSelect,
		RaceSelect,
		Customization,
		Appearance
	};

	void Rebuild();
	void BuildMainState();
	void BuildCharacterSelectState();
	void BuildSlotSelectState();
	void BuildRaceSelectState();
	void BuildCustomizationState();
	void BuildAppearanceControls(UVerticalBox* Parent);
	void BuildPreviewPane(UVerticalBox* Parent);
	void AddChoiceSelector(UVerticalBox* Parent, const FString& Label, const FString& Value, int32 Index, int32 Count, const FString& ActionPrefix, const FLinearColor* Swatch = nullptr);
	UFableActionButton* AddCompactButton(UHorizontalBox* Row, const FString& Label, FName Action, bool bSelected = false);
	void UpdatePreviewHair();
	void AddBodyTypeButton(UHorizontalBox* Row, bool Female);
	void RefreshAppearanceChoices();
	void RefreshAppearanceSection();
	void RefreshSelectionButtons();

	void CreateHeader(UVerticalBox* Parent, const FString& Text, int32 FontSize = 34) const;
	void CreateSubheader(UVerticalBox* Parent, const FString& Text) const;
	void AddSpacer(UVerticalBox* Parent, float Height) const;

	UFableActionButton* CreateActionButton(UVerticalBox* Parent, const FString& Label, FName ActionId, bool bEnabled = true, float Height = 46.0f);

	FName RegisterCharacterAction(const FGuid& CharacterId);
	FName RegisterRaceAction(const FString& RaceId);
	FName RegisterSlotAction(int32 SlotIndex);
	FName MakeActionName(const FString& Prefix);

	void ApplyCharacterCreation();
	void UpdatePreviewMesh();
	void ResetAppearance(bool bResetColors = false);
	void ApplyPreviewAppearance();
	void UpdatePreviewCamera();
	bool IsOverPreview(const FPointerEvent& Event) const;
	void SetPreviewZoom(float Zoom);
	void ResetPreviewView();
	UFUNCTION()
	void HandlePreviewZoomChanged(float Value);
	UFUNCTION()
	void HandleAppearanceChanged(float Value);
	bool EnsurePreviewActor();
	void ApplyRotationDelta(float DeltaYaw);
	void BeginRotateHold(float DeltaYaw);
	void EndRotateHold();

	UFUNCTION()
	void HandleRotateLeftPressed();

	UFUNCTION()
	void HandleRotateRightPressed();

	UFUNCTION()
	void HandleRotateReleased();

	UFUNCTION()
	void TickRotateHold();

	FString BuildSlotLabel(const FFableSaveSlotMeta& SlotMeta) const;

	UFUNCTION()
	void HandleActionClicked(FName ActionId);

private:
	EMainMenuState CurrentState = EMainMenuState::Main;
	bool bIsSlotLoadMode = true;

	FGuid PendingCharacterId;
	FString PendingCharacterName = TEXT("Adventurer");
	FString PendingRaceId = TEXT("human");
	EFableGender PendingGender = EFableGender::Male;

	TMap<FName, float> PendingBodyMorphs;
	float PendingHeightScale = 1.0f;
	int32 AppearanceCategory = 0;
	float PreviewZoom = 0.f;
	float PreviewPanOffset = 0.f;
	bool bDraggingPreview = false;
	FVector2D PreviewDragPosition = FVector2D::ZeroVector;
	UPROPERTY(Transient)
	TObjectPtr<USlider> PreviewZoomSlider;
	FLinearColor PendingSkinColor = FLinearColor::White;
	FLinearColor PendingHairColor = FLinearColor::White;
	FLinearColor PendingEyeColor = FLinearColor::White;
	FString PendingHairStyle = TEXT("none");
	FString PendingBeardStyle = TEXT("none");
	UPROPERTY(Transient)
	TObjectPtr<UStaticMeshComponent> PreviewHair;
	UPROPERTY(Transient)
	TObjectPtr<UStaticMeshComponent> PreviewBeard;
	UPROPERTY(Transient)
	TMap<FName, TObjectPtr<USlider>> AppearanceSliders;
	UPROPERTY(Transient)
	TMap<FName, TObjectPtr<UTextBlock>> AppearanceValues;

	UPROPERTY(Transient)
	TObjectPtr<UVerticalBox> AppearanceColumn;
	UPROPERTY(Transient)
	TMap<FString, TObjectPtr<UTextBlock>> ChoiceLabels;
	UPROPERTY(Transient)
	TMap<FString, TObjectPtr<UTextBlock>> ChoiceCounters;
	UPROPERTY(Transient)
	TMap<FString, TObjectPtr<UBorder>> ChoiceSwatches;
	UPROPERTY(Transient)
	TMap<FName, TObjectPtr<UFableActionButton>> SelectionButtons;
	UPROPERTY(Transient)
	TObjectPtr<UTextBlock> RaceDescriptionText;
	int32 ActionCounter = 0;
	TMap<FName, FGuid> CharacterActionMap;
	TMap<FName, FString> RaceActionMap;
	TMap<FName, int32> SlotActionMap;

	UPROPERTY(Transient)
	TObjectPtr<UVerticalBox> MenuContent;

	UPROPERTY(Transient)
	TObjectPtr<UEditableTextBox> CharacterNameTextBox;

	UPROPERTY(Transient)
	TObjectPtr<UViewport> PreviewViewport;

	UPROPERTY(Transient)
	TObjectPtr<AActor> PreviewActor;

	UPROPERTY(Transient)
	TObjectPtr<USkeletalMeshComponent> PreviewMeshComponent;

	UPROPERTY(Transient)
	TObjectPtr<UPointLightComponent> PreviewKeyLightComponent;

	float PreviewYawDegrees = -90.0f;
	float PreviewHoldDeltaYaw = 0.0f;
	FTimerHandle PreviewRotateTimerHandle;
};
