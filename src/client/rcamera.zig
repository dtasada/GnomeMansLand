//! Raylib camera implementation
const std = @import("std");
const rl = @import("raylib");

pub const MIN_FOV = 1;
pub const MAX_FOV = 512;

const CAMERA_MOVE_SPEED = 5.4; // Units per second
const CAMERA_ROTATION_SPEED = 0.03;
const CAMERA_PAN_SPEED = 0.2;
const CAMERA_MOUSE_MOVE_SENSITIVITY = 0.003; // Camera mouse movement sensitivity

// Camera orbital speed in CAMERA_ORBITAL mode
const CAMERA_ORBITAL_SPEED = 0.5; // Radians per second

pub fn getForward(camera: *rl.Camera) rl.Vector3 {
    return camera.target.subtract(camera.position).normalize();
}

pub fn getUp(camera: *rl.Camera) rl.Vector3 {
    return camera.up.normalize();
}

// Returns the cameras right vector (normalized)
pub fn getRight(camera: *rl.Camera) rl.Vector3 {
    const forward = getForward(camera);
    const up = getUp(camera);

    return forward.crossProduct(up).normalize();
}

// Rotates the camera around its right vector, pitch is "looking up and down"
//  - lockView prevents camera overrotation (aka "somersaults")
//  - rotateAroundTarget defines if rotation is around target or around its position
//  - rotateUp rotates the up direction as well (typically only usefull in CAMERA_FREE)
// NOTE: angle must be provided in radians
fn pitch(camera: *rl.Camera, angle_: f32, lockView: bool, rotateAroundTarget: bool, rotateUp: bool) void {
    // Up direction
    const up = getUp(camera);
    var angle = angle_;

    // View vector
    var targetPosition = camera.target.subtract(camera.position);

    if (lockView) {
        // In these camera modes we clamp the Pitch angle
        // to allow only viewing straight up or down.

        // Clamp view up

        var maxAngleUp = up.angle(targetPosition);
        maxAngleUp -= 0.001; // avoid numerical errors
        if (angle > maxAngleUp) angle = maxAngleUp;

        // Clamp view down
        var maxAngleDown = up.negate().angle(targetPosition);
        maxAngleDown *= -1.0; // downwards angle is negative
        maxAngleDown += 0.001; // avoid numerical errors
        if (angle < maxAngleDown) angle = maxAngleDown;
    }

    // Rotation axis
    const right = getRight(camera);

    // Rotate view vector around right axis
    targetPosition = targetPosition.rotateByAxisAngle(right, angle);

    if (rotateAroundTarget) {
        // Move position relative to target
        camera.position = camera.target.subtract(targetPosition);
    } else // rotate around camera.position
    {
        // Move target relative to position
        camera.target = camera.position.add(targetPosition);
    }

    if (rotateUp) {
        // Rotate up direction around right axis
        camera.up = camera.up.rotateByAxisAngle(right, angle);
    }
}

// Rotates the camera around its up vector
// Yaw is "looking left and right"
// If rotateAroundTarget is false, the camera rotates around its position
// Note: angle must be provided in radians
fn yaw(camera: *rl.Camera, angle: f32, rotateAroundTarget: bool) void {
    // Rotation axis
    const up = getUp(camera);

    // View vector
    const targetPosition = camera.target.subtract(camera.position).rotateByAxisAngle(up, angle);

    if (rotateAroundTarget) {
        camera.position = camera.target.subtract(targetPosition);
    } else // rotate around camera.position
    {
        // Move target relative to position
        camera.target = camera.position.add(targetPosition);
    }
}

// Rotates the camera around its forward vector
// Roll is "turning your head sideways to the left or right"
// Note: angle must be provided in radians
fn roll(camera: *rl.Camera, angle: f32) void {
    // Rotation axis
    const forward = getForward(camera);

    // Rotate up direction around forward axis
    camera.up = camera.up.rotateByAxisAngle(forward, angle);
}

// Moves the camera target in its current right direction
fn moveRight(camera: *rl.Camera, distance: f32, moveInWorldPlane: bool) void {
    var right = getRight(camera);

    if (moveInWorldPlane) {
        // Project vector onto world plane
        right.y = 0;
        right = right.normalize();
    }

    // Scale by distance
    right = right.scale(distance);

    // Move position and target
    camera.position = camera.position.add(right);
    camera.target = camera.target.add(right);
}

// Moves the camera in its up direction
fn moveUp(camera: *rl.Camera, distance: f32) void {
    const up = getUp(camera).scale(distance);

    // Move position and target
    camera.position = camera.position.add(up);
    camera.target = camera.target.add(up);
}

// Moves the camera in its forward direction
fn moveForward(camera: *rl.Camera, distance: f32, moveInWorldPlane: bool) void {
    var forward = getForward(camera);

    if (moveInWorldPlane) {
        // Project vector onto world plane
        forward.y = 0;
        forward = forward.normalize();
    }

    // Scale by distance
    forward = forward.scale(distance);

    // Move position and target
    camera.position = camera.position.add(forward);
    camera.target = camera.target.add(forward);
}

// Moves the camera position closer/farther to/from the camera target
fn moveToTarget(camera: *rl.Camera, delta: f32) void {
    var distance = camera.position.distance(camera.target);

    // Apply delta
    distance += delta;

    // Distance must be greater than 0
    if (distance <= 0) distance = 0.001;

    // Set new distance by moving the position along the forward vector
    const forward = getForward(camera);
    camera.position = camera.target.add(forward.scale(-distance));
}

pub fn update(camera: *rl.Camera, mode: rl.CameraMode) void {
    const mousePositionDelta = rl.getMouseDelta();

    const moveInWorldPlane = ((mode == .first_person) or (mode == .third_person));
    const rotateAroundTarget = ((mode == .third_person) or (mode == .orbital));
    const lockView = ((mode == .free) or (mode == .first_person) or (mode == .third_person) or (mode == .orbital));
    const rotateUp = false;

    // Camera speeds based on frame time
    const cameraMoveSpeed = CAMERA_MOVE_SPEED * rl.getFrameTime();
    const cameraRotationSpeed = CAMERA_ROTATION_SPEED * rl.getFrameTime();
    const cameraPanSpeed = CAMERA_PAN_SPEED * rl.getFrameTime();
    const cameraOrbitalSpeed = CAMERA_ORBITAL_SPEED * rl.getFrameTime();

    if (mode == .custom) {} else if (mode == .orbital) {
        // Orbital can just orbit
        const rotation = rl.Matrix.rotate(getUp(camera), cameraOrbitalSpeed);
        const view = camera.position.subtract(camera.target).transform(rotation);
        camera.position = camera.target.add(view);
    } else {
        // Camera rotation
        if (rl.isKeyDown(.down)) pitch(camera, -cameraRotationSpeed, lockView, rotateAroundTarget, rotateUp);
        if (rl.isKeyDown(.up)) pitch(camera, cameraRotationSpeed, lockView, rotateAroundTarget, rotateUp);
        if (rl.isKeyDown(.right)) yaw(camera, -cameraRotationSpeed, rotateAroundTarget);
        if (rl.isKeyDown(.left)) yaw(camera, cameraRotationSpeed, rotateAroundTarget);
        if (rl.isKeyDown(.q)) roll(camera, -cameraRotationSpeed);
        if (rl.isKeyDown(.e)) roll(camera, cameraRotationSpeed);

        // Camera movement
        // Camera pan (for CAMERA_FREE)
        if ((mode == .free) and (rl.isMouseButtonDown(.middle))) {
            const mouseDelta = rl.getMouseDelta();
            if (mouseDelta.x > 0.0) moveRight(camera, cameraPanSpeed, moveInWorldPlane);
            if (mouseDelta.x < 0.0) moveRight(camera, -cameraPanSpeed, moveInWorldPlane);
            if (mouseDelta.y > 0.0) moveUp(camera, -cameraPanSpeed);
            if (mouseDelta.y < 0.0) moveUp(camera, cameraPanSpeed);
        } else {
            // Mouse support
            yaw(camera, -mousePositionDelta.x * CAMERA_MOUSE_MOVE_SENSITIVITY, rotateAroundTarget);
            pitch(camera, -mousePositionDelta.y * CAMERA_MOUSE_MOVE_SENSITIVITY, lockView, rotateAroundTarget, rotateUp);
        }

        // Keyboard support
        if (rl.isKeyDown(.w)) moveForward(camera, cameraMoveSpeed, moveInWorldPlane);
        if (rl.isKeyDown(.a)) moveRight(camera, -cameraMoveSpeed, moveInWorldPlane);
        if (rl.isKeyDown(.s)) moveForward(camera, -cameraMoveSpeed, moveInWorldPlane);
        if (rl.isKeyDown(.d)) moveRight(camera, cameraMoveSpeed, moveInWorldPlane);

        // Gamepad movement
        if (rl.isGamepadAvailable(0)) {
            // Gamepad controller support
            yaw(camera, -(rl.getGamepadAxisMovement(0, .right_x) * 2) * CAMERA_MOUSE_MOVE_SENSITIVITY, rotateAroundTarget);
            pitch(camera, -(rl.getGamepadAxisMovement(0, .right_y) * 2) * CAMERA_MOUSE_MOVE_SENSITIVITY, lockView, rotateAroundTarget, rotateUp);

            if (rl.getGamepadAxisMovement(0, .left_y) <= -0.25) moveForward(camera, cameraMoveSpeed, moveInWorldPlane);
            if (rl.getGamepadAxisMovement(0, .left_x) <= -0.25) moveRight(camera, -cameraMoveSpeed, moveInWorldPlane);
            if (rl.getGamepadAxisMovement(0, .left_y) >= 0.25) moveForward(camera, -cameraMoveSpeed, moveInWorldPlane);
            if (rl.getGamepadAxisMovement(0, .left_x) >= 0.25) moveRight(camera, cameraMoveSpeed, moveInWorldPlane);
        }

        if (mode == .free) {
            if (rl.isKeyDown(.space)) moveUp(camera, cameraMoveSpeed);
            if (rl.isKeyDown(.left_control)) moveUp(camera, -cameraMoveSpeed);
        }
    }

    if ((mode == .third_person) or (mode == .orbital) or (mode == .free)) {
        // Zoom target distance
        if (rl.isKeyPressed(.kp_subtract)) moveToTarget(camera, 2.0);
        if (rl.isKeyPressed(.kp_add)) moveToTarget(camera, -2.0);
    }
}
