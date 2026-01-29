using UnityEngine;

public class CompanionFollower : MonoBehaviour
{
    public Transform target;
    public Vector3 offset = new Vector3(-0.6f, -0.4f, 0f);
    public float followSpeed = 3f;

    private void Update()
    {
        if (target == null)
        {
            return;
        }

        var desired = target.position + offset;
        transform.position = Vector3.Lerp(transform.position, desired, Time.deltaTime * followSpeed);
    }
}
