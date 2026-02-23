// Copyright Epic Games, Inc. All Rights Reserved.

#include "FableForgeCharacter.h"
#include "Engine/LocalPlayer.h"
#include "Camera/CameraComponent.h"
#include "Components/CapsuleComponent.h"
#include "GameFramework/CharacterMovementComponent.h"
#include "GameFramework/SpringArmComponent.h"
#include "GameFramework/Controller.h"
#include "GameFramework/PlayerController.h"
#include "EnhancedInputComponent.h"
#include "EnhancedInputSubsystems.h"
#include "InputCoreTypes.h"
#include "InputActionValue.h"
#include "FableForgePlayerController.h"
#include "FableForge.h"

AFableForgeCharacter::AFableForgeCharacter()
{
	PrimaryActorTick.bCanEverTick = true;

	// Set size for collision capsule
	GetCapsuleComponent()->InitCapsuleSize(42.f, 96.0f);
		
	// Don't rotate when the controller rotates. Let that just affect the camera.
	bUseControllerRotationPitch = false;
	bUseControllerRotationYaw = false;
	bUseControllerRotationRoll = false;

	// Configure character movement
	GetCharacterMovement()->bOrientRotationToMovement = false;
	GetCharacterMovement()->RotationRate = FRotator(0.0f, 500.0f, 0.0f);

	// Note: For faster iteration times these variables, and many more, can be tweaked in the Character Blueprint
	// instead of recompiling to adjust them
	GetCharacterMovement()->JumpZVelocity = 500.f;
	GetCharacterMovement()->AirControl = 0.35f;
	GetCharacterMovement()->MaxWalkSpeed = 500.f;
	// Keeps animation state machines that rely on acceleration working during click-to-move path following.
	if (FNavMovementProperties* NavMovementProperties = GetCharacterMovement()->GetNavMovementProperties())
	{
		NavMovementProperties->bUseAccelerationForPaths = true;
	}
	GetCharacterMovement()->MinAnalogWalkSpeed = 20.f;
	GetCharacterMovement()->BrakingDecelerationWalking = 2000.f;
	GetCharacterMovement()->BrakingDecelerationFalling = 1500.0f;

	// Create a camera boom (pulls in towards the player if there is a collision)
	CameraBoom = CreateDefaultSubobject<USpringArmComponent>(TEXT("CameraBoom"));
	CameraBoom->SetupAttachment(RootComponent);
	CameraBoom->TargetArmLength = IdleCameraArmLength;
	CameraBoom->SocketOffset = IdleCameraSocketOffset;
	CameraBoom->bUsePawnControlRotation = true;
	CameraBoom->bEnableCameraLag = true;
	CameraBoom->bEnableCameraRotationLag = false;
	CameraBoom->CameraLagSpeed = 10.0f;
	CameraBoom->CameraRotationLagSpeed = 0.0f;

	// Create a follow camera
	FollowCamera = CreateDefaultSubobject<UCameraComponent>(TEXT("FollowCamera"));
	FollowCamera->SetupAttachment(CameraBoom, USpringArmComponent::SocketName);
	FollowCamera->bUsePawnControlRotation = false;
	FollowCamera->SetRelativeRotation(FRotator(CameraPitchOffsetDegrees, 0.0f, 0.0f));

	// Note: The skeletal mesh and anim blueprint references on the Mesh component (inherited from Character) 
	// are set in the derived blueprint asset named ThirdPersonCharacter (to avoid direct content references in C++)
}

void AFableForgeCharacter::BeginPlay()
{
	Super::BeginPlay();

	if (CameraBoom != nullptr)
	{
		CameraBoom->TargetArmLength = IdleCameraArmLength;
		CameraBoom->SocketOffset = IdleCameraSocketOffset;
	}

	if (FollowCamera != nullptr)
	{
		FollowCamera->SetRelativeRotation(FRotator(CameraPitchOffsetDegrees, 0.0f, 0.0f));
	}
}

void AFableForgeCharacter::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	UpdateShoulderCamera(DeltaSeconds);
}

void AFableForgeCharacter::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	// Set up action bindings
	if (UEnhancedInputComponent* EnhancedInputComponent = Cast<UEnhancedInputComponent>(PlayerInputComponent)) {
		
		// Jumping
		EnhancedInputComponent->BindAction(JumpAction, ETriggerEvent::Started, this, &ACharacter::Jump);
		EnhancedInputComponent->BindAction(JumpAction, ETriggerEvent::Completed, this, &ACharacter::StopJumping);

		// Moving
		EnhancedInputComponent->BindAction(MoveAction, ETriggerEvent::Triggered, this, &AFableForgeCharacter::Move);
		EnhancedInputComponent->BindAction(MouseLookAction, ETriggerEvent::Triggered, this, &AFableForgeCharacter::MouseLook);

		// Looking
		EnhancedInputComponent->BindAction(LookAction, ETriggerEvent::Triggered, this, &AFableForgeCharacter::Look);
	}
	else
	{
		UE_LOG(LogFableForge, Error, TEXT("'%s' Failed to find an Enhanced Input component! This template is built to use the Enhanced Input system. If you intend to use the legacy system, then you will need to update this C++ file."), *GetNameSafe(this));
	}
}

void AFableForgeCharacter::Move(const FInputActionValue& Value)
{
	// input is a Vector2D
	FVector2D MovementVector = Value.Get<FVector2D>();

	// Forward/back movement input should interrupt click-to-move interaction paths.
	if (FMath::Abs(MovementVector.Y) > KINDA_SMALL_NUMBER)
	{
		if (AFableForgePlayerController* ForgePlayerController = Cast<AFableForgePlayerController>(GetController()))
		{
			ForgePlayerController->NotifyManualMoveInput();
		}
	}

	if (MovementVector.SizeSquared() > FMath::Square(MovementFollowThreshold))
	{
		if (UWorld* World = GetWorld())
		{
			LastMoveInputTime = World->GetTimeSeconds();
		}
	}

	// route the input
	DoMove(MovementVector.X, MovementVector.Y);
}

void AFableForgeCharacter::Look(const FInputActionValue& Value)
{
	// input is a Vector2D
	FVector2D LookAxisVector = Value.Get<FVector2D>();

	if (LookAxisVector.SizeSquared() > KINDA_SMALL_NUMBER)
	{
		if (UWorld* World = GetWorld())
		{
			LastManualLookTime = World->GetTimeSeconds();
		}
	}

	// route the input
	DoLook(LookAxisVector.X, LookAxisVector.Y);
}

void AFableForgeCharacter::MouseLook(const FInputActionValue& Value)
{
	if (!bRequireMouseButtonForMouseLook)
	{
		Look(Value);
		return;
	}

	const APlayerController* PlayerController = Cast<APlayerController>(GetController());
	if (PlayerController == nullptr)
	{
		return;
	}

	const bool bLeftMouseHeld = bUseLeftMouseButtonForLook && PlayerController->IsInputKeyDown(EKeys::LeftMouseButton);
	const bool bRightMouseHeld = bUseRightMouseButtonForLook && PlayerController->IsInputKeyDown(EKeys::RightMouseButton);

	if (!bLeftMouseHeld && !bRightMouseHeld)
	{
		return;
	}

	Look(Value);
}

void AFableForgeCharacter::UpdateShoulderCamera(float DeltaSeconds)
{
	if (CameraBoom == nullptr || Controller == nullptr)
	{
		return;
	}

	const bool bShouldFollow = IsMovementActive() && !IsManualLookActive();
	float TargetArmLength = IdleCameraArmLength;
	if (bAdjustArmLengthWithMovement)
	{
		TargetArmLength = bShouldFollow ? MovingCameraArmLength : IdleCameraArmLength;
	}
	FVector TargetSocketOffset = IdleCameraSocketOffset;
	if (bAdjustSocketOffsetWithMovement)
	{
		TargetSocketOffset = bShouldFollow ? MovingCameraSocketOffset : IdleCameraSocketOffset;
	}

	CameraBoom->TargetArmLength = FMath::FInterpTo(CameraBoom->TargetArmLength, TargetArmLength, DeltaSeconds, CameraFollowInterpSpeed);
	CameraBoom->SocketOffset = FMath::VInterpTo(CameraBoom->SocketOffset, TargetSocketOffset, DeltaSeconds, CameraOffsetInterpSpeed);

	if (bShouldFollow && !bWasAutoFollowActive)
	{
		const FRotator CurrentControlRotation = Controller->GetControlRotation();
		const float YawDeltaDegrees = FMath::Abs(FMath::FindDeltaAngleDegrees(CurrentControlRotation.Yaw, GetActorRotation().Yaw));
		bCameraRecentering = YawDeltaDegrees > CameraRecenterMinYawDelta;
	}
	else if (!bShouldFollow)
	{
		bCameraRecentering = false;
	}

	if (bShouldFollow)
	{
		const FRotator CurrentControlRotation = Controller->GetControlRotation();
		FRotator TargetControlRotation = CurrentControlRotation;
		TargetControlRotation.Yaw = GetActorRotation().Yaw;
		TargetControlRotation.Roll = 0.0f;

		if (bCameraRecentering)
		{
			const FRotator RecenteredRotation = FMath::RInterpTo(CurrentControlRotation, TargetControlRotation, DeltaSeconds, CameraYawFollowInterpSpeed);
			Controller->SetControlRotation(RecenteredRotation);

			const float YawDeltaDegrees = FMath::Abs(FMath::FindDeltaAngleDegrees(RecenteredRotation.Yaw, TargetControlRotation.Yaw));
			if (YawDeltaDegrees <= 1.5f)
			{
				bCameraRecentering = false;
			}
		}
		else
		{
			Controller->SetControlRotation(TargetControlRotation);
		}
	}

	bWasAutoFollowActive = bShouldFollow;
}

bool AFableForgeCharacter::IsMovementActive() const
{
	const UWorld* World = GetWorld();
	if (World == nullptr)
	{
		return false;
	}

	const bool bRecentlyMoved = (World->GetTimeSeconds() - LastMoveInputTime) <= 0.15f;
	const float HorizontalSpeed = GetVelocity().Size2D();

	return bRecentlyMoved || HorizontalSpeed > VelocityFollowThreshold;
}

bool AFableForgeCharacter::IsManualLookActive() const
{
	const UWorld* World = GetWorld();
	if (World == nullptr)
	{
		return false;
	}

	return (World->GetTimeSeconds() - LastManualLookTime) <= CameraAutoFollowDelay;
}

void AFableForgeCharacter::DoMove(float Right, float Forward)
{
	if (GetController() != nullptr)
	{
		// WoW-style movement: A/D turn character yaw, W/S move along facing direction.
		if (!FMath::IsNearlyZero(Right))
		{
			const float DeltaSeconds = GetWorld() ? GetWorld()->GetDeltaSeconds() : 0.0f;
			AddActorLocalRotation(FRotator(0.0f, Right * KeyboardTurnRate * DeltaSeconds, 0.0f));
		}

		if (!FMath::IsNearlyZero(Forward))
		{
			AddMovementInput(GetActorForwardVector(), Forward);
		}
	}
}

void AFableForgeCharacter::DoLook(float Yaw, float Pitch)
{
	if (GetController() != nullptr)
	{
		// add yaw and pitch input to controller
		AddControllerYawInput(Yaw);
		AddControllerPitchInput(Pitch);
	}
}

void AFableForgeCharacter::DoJumpStart()
{
	// signal the character to jump
	Jump();
}

void AFableForgeCharacter::DoJumpEnd()
{
	// signal the character to stop jumping
	StopJumping();
}
