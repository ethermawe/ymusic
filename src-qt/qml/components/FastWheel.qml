import QtQuick

WheelHandler {
    id: root

    property real pixelsPerNotch: 320
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

    Component.onCompleted: {
        const flick = root.target as Flickable;
        if (flick) {
            if (flick.maximumFlickVelocity < 7000) flick.maximumFlickVelocity = 7000;
            if (flick.flickDeceleration < 2400) flick.flickDeceleration = 2400;
        }
    }

    onWheel: (event) => {
        const flick = root.target as Flickable;
        if (!flick) {
            event.accepted = false;
            return;
        }
        // Let touchpads and ScrollMomentum's synthetic pixelDelta events pan 1:1 natively.
        if (event.angleDelta.y === 0 || (event.device && event.device.type === PointerDevice.TouchPad)) {
            event.accepted = false;
            return;
        }
        const notches = event.angleDelta.y / 120.0;
        if ((notches > 0 && flick.atYBeginning) || (notches < 0 && flick.atYEnd)) {
            flick.cancelFlick();
            event.accepted = false;
            return;
        }
        const decel = Math.max(800, flick.flickDeceleration);
        const vCur = Math.abs(flick.verticalVelocity) > 1 ? -flick.verticalVelocity : 0;
        const sCur = (vCur >= 0 ? 1 : -1) * (vCur * vCur) / (2.0 * decel);
        const sNew = sCur + notches * root.pixelsPerNotch;
        const vMax = Math.max(3000, flick.maximumFlickVelocity);
        const vMag = Math.min(vMax, Math.sqrt(2.0 * decel * Math.abs(sNew)));
        const vNew = sNew >= 0 ? vMag : -vMag;
        flick.flick(0, vNew);
        event.accepted = true;
    }
}
