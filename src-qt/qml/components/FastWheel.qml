import QtQuick

WheelHandler {
    id: root

    property real pixelsPerNotch: 320
    // Flickable reparents default-property children onto contentItem, so check parent.parent too.
    readonly property Flickable flickTarget: (root.target as Flickable)
        ?? (root.parent as Flickable)
        ?? ((root.parent ? root.parent.parent : null) as Flickable)

    acceptedDevices: PointerDevice.AllDevices
    // Keep blocking true so Flickable's built-in wheel handler never overrides FastWheel's flick impulse;
    // pixelDelta panning and ancestor Flickable propagation at bounds are handled directly below.
    blocking: true

    function tuneFlickable(): void {
        const flick = root.flickTarget;
        if (flick) {
            if (flick.maximumFlickVelocity < 7000) flick.maximumFlickVelocity = 7000;
            if (flick.flickDeceleration < 2400) flick.flickDeceleration = 2400;
        }
    }

    function parentFlickable(fromItem: Item): Flickable {
        let p = fromItem ? fromItem.parent : null;
        while (p) {
            const flick = p as Flickable;
            if (flick && flick.interactive) return flick;
            p = p.parent;
        }
        return null;
    }

    function panFlickable(flick: Flickable, dy: real): bool {
        if (!flick || dy === 0) return false;
        if ((dy > 0 && flick.atYBeginning) || (dy < 0 && flick.atYEnd)) {
            return false;
        }
        flick.cancelFlick();
        const minY = flick.originY - flick.topMargin;
        const maxY = Math.max(minY, flick.originY + flick.contentHeight + flick.bottomMargin - flick.height);
        flick.contentY = Math.max(minY, Math.min(maxY, flick.contentY - dy));
        return true;
    }

    function flickByNotches(flick: Flickable, notches: real): bool {
        if (!flick || notches === 0) return false;
        if ((notches > 0 && flick.atYBeginning) || (notches < 0 && flick.atYEnd)) {
            flick.cancelFlick();
            return false;
        }
        const decel = Math.max(800, flick.flickDeceleration);
        const vCur = Math.abs(flick.verticalVelocity) > 1 ? -flick.verticalVelocity : 0;
        const sCur = (vCur >= 0 ? 1 : -1) * (vCur * vCur) / (2.0 * decel);
        const sNew = sCur + notches * root.pixelsPerNotch;
        const vMax = Math.max(3000, flick.maximumFlickVelocity);
        const vMag = Math.min(vMax, Math.sqrt(2.0 * decel * Math.abs(sNew)));
        const vNew = sNew >= 0 ? vMag : -vMag;
        flick.flick(0, vNew);
        return true;
    }

    Component.onCompleted: tuneFlickable()
    onFlickTargetChanged: tuneFlickable()

    onWheel: (event) => {
        let flick = root.flickTarget;
        const isTouchPad = event.device && event.device.type === PointerDevice.TouchPad;
        const usePixelPan = event.angleDelta.y === 0 || (isTouchPad && event.pixelDelta.y !== 0);

        while (flick) {
            if (flick.interactive) {
                if (usePixelPan) {
                    const dy = event.pixelDelta.y !== 0 ? event.pixelDelta.y : (event.angleDelta.y / 120.0) * 60;
                    if (root.panFlickable(flick, dy)) {
                        event.accepted = true;
                        return;
                    }
                } else {
                    if (root.flickByNotches(flick, event.angleDelta.y / 120.0)) {
                        event.accepted = true;
                        return;
                    }
                }
            }
            flick = root.parentFlickable(flick);
        }
        event.accepted = false;
    }
}
