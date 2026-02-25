// Copyright Epic Games, Inc. All Rights Reserved.

#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Character.h"
#include "Logging/LogMacros.h"
#include "FableForgeCharacter.generated.h"

class USpringArmComponent;
class UCameraComponent;
class UInputAction;
class USceneComponent;
struct FInputActionValue;

DECLARE_LOG_CATEGORY_EXTERN(LogTemplateCharacter, Log, All);

/**
 *  A simple player-controllable third person character
 *  Implements a controllable orbiting camera
 */
UCLASS(abstract)
class AFableForgeCharacter : public ACharacter
{
	GENERATED_BODY()

	/** Camera boom positioning the camera behind the character */
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category="Components", meta = (AllowPrivateAccess = "true"))
	USpringArmComponent* CameraBoom;

	/** Follow camera */
	UPROPERTY(VisibleAnywhere, BlueprintReadOnly, Category="Components", meta = (AllowPrivateAccess = "true"))
	UCameraComponent* FollowCamera;
	
protected:

	/** Jump Input Action */
	UPROPERTY(EditAnywhere, Category="Input")
	UInputAction* JumpAction;

	/** Move Input Action */
	UPROPERTY(EditAnywhere, Category="Input")
	UInputAction* MoveAction;

	/** Look Input Action */
	UPROPERTY(EditAnywhere, Category="Input")
	UInputAction* LookAction;

	/** Mouse Look Input Action */
	UPROPERTY(EditAnywhere, Category="Input")
	UInputAction* MouseLookAction;

	/** If true, mouse camera look is only applied while a mouse button is held */
	UPROPERTY(EditAnywhere, Category="Input")
	bool bRequireMouseButtonForMouseLook = true;

	/** Enables left-click + drag mouse look */
	UPROPERTY(EditAnywhere, Category="Input")
	bool bUseLeftMouseButtonForLook = true;

	/** Enables right-click + drag mouse look */
	UPROPERTY(EditAnywhere, Category="Input")
	bool bUseRightMouseButtonForLook = true;

	/** Degrees per second applied to left/right turn input when using keyboard-style turn controls */
	UPROPERTY(EditAnywhere, Category="Input", meta=(ClampMin=10.0, ClampMax=720.0, Units="deg/s"))
	float KeyboardTurnRate = 220.0f;

	/** Camera distance while moving so the view sits farther back over the shoulder */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow", meta=(ClampMin=0.0, ClampMax=1000.0, Units="cm"))
	float MovingCameraArmLength = 445.0f;

	/** Camera distance while idle so players can inspect the character more easily */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow", meta=(ClampMin=0.0, ClampMax=1000.0, Units="cm"))
	float IdleCameraArmLength = 345.0f;

	/** Fixed camera pitch offset so the view is lifted slightly */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow", meta=(ClampMin=-30.0, ClampMax=30.0, Units="deg"))
	float CameraPitchOffsetDegrees = -5.0f;

	/** Camera shoulder offset while moving */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow")
	FVector MovingCameraSocketOffset = FVector(0.0f, 70.0f, 80.0f);

	/** Camera socket offset while idle */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow")
	FVector IdleCameraSocketOffset = FVector(0.0f, 70.0f, 80.0f);

	/** Camera interpolation speed for distance and turn-to-follow */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow", meta=(ClampMin=0.1, ClampMax=30.0))
	float CameraFollowInterpSpeed = 7.0f;

	/** Camera interpolation speed used when re-centering from manual drag back to behind the character */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow", meta=(ClampMin=0.1, ClampMax=20.0))
	float CameraYawFollowInterpSpeed = 2.0f;

	/** Minimum yaw gap required to use smooth re-center instead of immediate lock-to-facing */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow", meta=(ClampMin=0.0, ClampMax=180.0, Units="deg"))
	float CameraRecenterMinYawDelta = 12.0f;

	/** Camera interpolation speed for shoulder offset changes */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow", meta=(ClampMin=0.1, ClampMax=30.0))
	float CameraOffsetInterpSpeed = 8.0f;

	/** If true, arm length changes between idle and moving; disabled by default to prevent zoom shifts */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow")
	bool bAdjustArmLengthWithMovement = false;

	/** If true, shoulder offset changes between idle and moving; disabled by default to prevent positional shifts */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow")
	bool bAdjustSocketOffsetWithMovement = false;

	/** How long to wait after manual look input before auto-follow resumes */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow", meta=(ClampMin=0.0, ClampMax=2.0, Units="s"))
	float CameraAutoFollowDelay = 0.4f;

	/** Movement input magnitude threshold to activate follow behavior */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow", meta=(ClampMin=0.0, ClampMax=1.0))
	float MovementFollowThreshold = 0.1f;

	/** Minimum horizontal speed to consider the character as moving */
	UPROPERTY(EditAnywhere, Category="Camera|Shoulder Follow", meta=(ClampMin=0.0, ClampMax=500.0, Units="cm/s"))
	float VelocityFollowThreshold = 10.0f;

	/** Last time look input was received so click-drag can temporarily override auto-follow */
	float LastManualLookTime = -1000.0f;

	/** Last time move input was received */
	float LastMoveInputTime = -1000.0f;

	/** Tracks whether auto-follow was active in the previous update */
	bool bWasAutoFollowActive = false;

	/** True while blending camera yaw back behind the character after manual drag */
	bool bCameraRecentering = false;

public:

	/** Constructor */
	AFableForgeCharacter();	

protected:

	/** Runtime initialization */
	virtual void BeginPlay() override;
	virtual void EndPlay(const EEndPlayReason::Type EndPlayReason) override;

	/** Character tick */
	virtual void Tick(float DeltaSeconds) override;

	/** Initialize input action bindings */
	virtual void SetupPlayerInputComponent(class UInputComponent* PlayerInputComponent) override;

protected:

	/** Called for movement input */
	void Move(const FInputActionValue& Value);

	/** Called for looking input */
	void Look(const FInputActionValue& Value);

	/** Called for mouse look input (can require click-drag) */
	void MouseLook(const FInputActionValue& Value);

	/** Updates camera follow/shoulder behavior */
	void UpdateShoulderCamera(float DeltaSeconds);

	/** Returns true if movement input or velocity indicates the character is actively moving */
	bool IsMovementActive() const;

	/** Returns true if the player has recently provided look input */
	bool IsManualLookActive() const;

public:

	/** Handles move inputs from either controls or UI interfaces */
	UFUNCTION(BlueprintCallable, Category="Input")
	virtual void DoMove(float Right, float Forward);

	/** Handles look inputs from either controls or UI interfaces */
	UFUNCTION(BlueprintCallable, Category="Input")
	virtual void DoLook(float Yaw, float Pitch);

	/** Handles jump pressed inputs from either controls or UI interfaces */
	UFUNCTION(BlueprintCallable, Category="Input")
	virtual void DoJumpStart();

	/** Handles jump pressed inputs from either controls or UI interfaces */
	UFUNCTION(BlueprintCallable, Category="Input")
	virtual void DoJumpEnd();

	/** Rebuilds visible equipped item meshes from the active save profile equipment slots */
	UFUNCTION(BlueprintCallable, Category="Equipment")
	void RefreshEquipmentVisualsFromSave();

public:

	/** Returns CameraBoom subobject **/
	FORCEINLINE class USpringArmComponent* GetCameraBoom() const { return CameraBoom; }

	/** Returns FollowCamera subobject **/
	FORCEINLINE class UCameraComponent* GetFollowCamera() const { return FollowCamera; }

private:
	void HandleActiveInventoryChanged(const TArray<FString>& InInventorySlots, const TArray<FString>& InEquippedSlots);
	void ApplyEquipmentVisuals(const TArray<FString>& InEquippedSlots);
	void ClearEquipmentVisual(int32 SlotIndex);
	void CreateEquipmentVisualForSlot(int32 SlotIndex, const FString& ItemId);
	FName GetEquipmentAttachSocket(int32 SlotIndex) const;
	FTransform GetEquipmentSlotRelativeTransform(int32 SlotIndex, const FString& ItemId) const;
	bool ResolveEquipmentMeshPath(const FString& ItemId, int32 SlotIndex, FString& OutAssetPath) const;

	UPROPERTY(Transient)
	TArray<TObjectPtr<USceneComponent>> EquipmentVisualComponents;
};
