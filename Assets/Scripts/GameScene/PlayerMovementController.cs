using UnityEngine;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem;
#endif

public class PlayerMovementController : MonoBehaviour
{
    [SerializeField] private float tilesPerSecond = 4f;
    [Tooltip("Max deltaTime per frame to avoid movement jump after frame spikes (e.g. block loading).")]
    [SerializeField] private float maxDeltaTime = 0.05f;
    private float tileScale = 1f;
    private Vector3 lastPosition;
    private Vector2 lastMovementInput;

    /// <summary>Used by CharacterWalkAnimator to know if the character is moving.</summary>
    public float LastMovementInputSqrMagnitude => lastMovementInput.sqrMagnitude;

    public void SetTileScale(float scale)
    {
        tileScale = Mathf.Max(0.01f, scale);
    }

    private void Update()
    {
#if ENABLE_INPUT_SYSTEM || ENABLE_LEGACY_INPUT_MANAGER
        var sceneController = GameSceneController.Instance;
        if (sceneController != null && sceneController.IsInBattle)
        {
            return;
        }
#endif
#if ENABLE_INPUT_SYSTEM
        var input = ReadInputFromInputSystem();
#elif ENABLE_LEGACY_INPUT_MANAGER
        var input = new Vector2(Input.GetAxisRaw("Horizontal"), Input.GetAxisRaw("Vertical"));
#else
        var input = Vector2.zero;
#endif
        if (input.sqrMagnitude > 1f)
        {
            input.Normalize();
        }

        if (input.sqrMagnitude > 0.01f)
        {
            lastMovementInput = input;
        }

        var startPosition = transform.position;

        var dt = Mathf.Min(Time.deltaTime, maxDeltaTime > 0f ? maxDeltaTime : 0.05f);
        var speed = tilesPerSecond * tileScale;
        var delta = (Vector3)(input * speed * dt);
        var target = transform.position + delta;

        sceneController = GameSceneController.Instance;
        if (sceneController == null || sceneController.CanMoveTo(target))
        {
            transform.position = target;
            UpdateFacingFromMovement();
            CloseChestOnMove(input, startPosition);
            return;
        }

        if (delta.sqrMagnitude <= 0f)
        {
            return;
        }

        var xOnly = transform.position + new Vector3(delta.x, 0f, 0f);
        if (sceneController.CanMoveTo(xOnly))
        {
            transform.position = xOnly;
            UpdateFacingFromMovement();
            CloseChestOnMove(input, startPosition);
            return;
        }

        var yOnly = transform.position + new Vector3(0f, delta.y, 0f);
        if (sceneController.CanMoveTo(yOnly))
        {
            transform.position = yOnly;
            UpdateFacingFromMovement();
            CloseChestOnMove(input, startPosition);
        }
        else
        {
            CloseChestOnMove(input, startPosition);
        }
    }

    private void UpdateFacingFromMovement()
    {
        var customizer = GetComponent<CharacterCustomizer>();
        if (customizer != null)
        {
            customizer.SetFacingFromMovement(lastMovementInput);
        }
    }

    private void CloseChestOnMove(Vector2 input, Vector3 startPosition)
    {
        if (input.sqrMagnitude <= 0f)
        {
            return;
        }

        if ((transform.position - startPosition).sqrMagnitude <= 0.0001f)
        {
            return;
        }

        var ui = FindFirstObjectByType<FableForge.UI.RuntimeGameUIBootstrap>();
        if (ui != null && ui.IsChestOpen)
        {
            ui.CloseChestIfOpen();
        }
    }

#if ENABLE_INPUT_SYSTEM
    private Vector2 ReadInputFromInputSystem()
    {
        var input = Vector2.zero;

        if (Keyboard.current != null)
        {
            if (Keyboard.current.aKey.isPressed || Keyboard.current.leftArrowKey.isPressed)
            {
                input.x -= 1f;
            }
            if (Keyboard.current.dKey.isPressed || Keyboard.current.rightArrowKey.isPressed)
            {
                input.x += 1f;
            }
            if (Keyboard.current.sKey.isPressed || Keyboard.current.downArrowKey.isPressed)
            {
                input.y -= 1f;
            }
            if (Keyboard.current.wKey.isPressed || Keyboard.current.upArrowKey.isPressed)
            {
                input.y += 1f;
            }
        }

        if (input == Vector2.zero && Gamepad.current != null)
        {
            input = Gamepad.current.leftStick.ReadValue();
        }

        return input;
    }
#endif
}
