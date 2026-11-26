import QtQuick
import ymusic.ui

WheelHandler {
    id: root

    property real pixelsPerNotch: 220
    // Distance (px of content) per 1px of pixelDelta for discrete pixel steps, at 1.0x speed.
    property real pixelScale: 5.0
    property real lastEventMs: 0
    readonly property real speedMultiplier: AppSettings ? AppSettings.scrollSpeed : 1.8
    // One wheel event never moves more than this share of the viewport, and the queued
    // (not yet travelled) distance never exceeds maxQueuedViewports, so fast spinning
    // does not skip whole screens or keep gliding long after the wheel stops.
    property real maxStepViewports: 0.9
    property real maxQueuedViewports: 4.5
    property real wheelOmega: 18.0
    property Flickable activeFlick: null
    property real targetY: 0
    property real scrollVelocity: 0
    property real springOmega: 18.0
    property real lastWheelMs: 0
    property int lastWheelSign: 0
    property int wheelChain: 0
    signal wheelScrolled(Flickable target)
    // Flickable reparents default-property children onto contentItem, so check parent.parent too.
    readonly property Flickable flickTarget: (root.target as Flickable)
        ?? (root.parent as Flickable)
        ?? ((root.parent ? root.parent.parent : null) as Flickable)

    acceptedDevices: PointerDevice.AllDevices
    // Keep blocking true so Flickable's built-in wheel handler never overrides FastWheel;
    // smooth wheel animation, pixelDelta panning, and ancestor propagation are handled directly below.
    blocking: true

    function minContentY(flick: Flickable): real {
        return flick.originY - flick.topMargin;
    }

    function maxContentY(flick: Flickable): real {
        const minY = minContentY(flick);
        return Math.max(minY, flick.originY + flick.contentHeight + flick.bottomMargin - flick.height);
    }

    function stopSmooth(): void {
        activeFlick = null;
        scrollVelocity = 0;
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
        stopSmooth();
        flick.cancelFlick();
        const minY = minContentY(flick);
        const maxY = maxContentY(flick);
        flick.contentY = Math.max(minY, Math.min(maxY, flick.contentY - dy));
        root.wheelScrolled(flick);
        return true;
    }

    function smoothScrollByDelta(flick: Flickable, step: real, omega: real): bool {
        if (!flick || step === 0) return false;
        const minY = minContentY(flick);
        const maxY = maxContentY(flick);

        if (Appearance.performanceMode) {
            return panFlickable(flick, step);
        }

        const continuing = root.activeFlick === flick && root.glide.running;
        const baseTarget = continuing ? root.targetY : flick.contentY;
        const viewport = Math.max(1, flick.height);
        const cappedStep = Math.max(-viewport * root.maxStepViewports,
                                    Math.min(viewport * root.maxStepViewports, step));
        const queueLimit = viewport * root.maxQueuedViewports;
        let nextTarget = baseTarget - cappedStep;
        nextTarget = Math.max(flick.contentY - queueLimit, Math.min(flick.contentY + queueLimit, nextTarget));
        nextTarget = Math.max(minY, Math.min(maxY, nextTarget));
        if (Math.abs(nextTarget - baseTarget) < 0.25
            && (!continuing || Math.abs(flick.contentY - nextTarget) < 0.5)) {
            return false;
        }

        if (!continuing) {
            root.scrollVelocity = 0;
        }
        flick.cancelFlick();
        root.springOmega = omega;
        root.targetY = nextTarget;
        root.activeFlick = flick;
        root.wheelScrolled(flick);
        return true;
    }

    readonly property Connections dragWatcher: Connections {
        target: root.activeFlick
        function onDraggingChanged() {
            if (root.activeFlick && root.activeFlick.dragging) {
                root.stopSmooth();
            }
        }
    }

    readonly property FrameAnimation glide: FrameAnimation {
        running: root.activeFlick !== null && root.activeFlick.visible
        onTriggered: {
            const flick = root.activeFlick;
            if (!flick || flick.dragging) {
                root.stopSmooth();
                return;
            }
            const minY = root.minContentY(flick);
            const maxY = root.maxContentY(flick);
            const clampedTarget = Math.max(minY, Math.min(maxY, root.targetY));
            root.targetY = clampedTarget;

            const dt = Math.min(0.05, Math.max(0.001, root.glide.frameTime));
            const omega = root.springOmega;
            const decay = Math.exp(-omega * dt);
            const disp = flick.contentY - clampedTarget;
            const temp = (root.scrollVelocity + omega * disp) * dt;
            let nextVel = (root.scrollVelocity - omega * temp) * decay;
            let nextY = clampedTarget + (disp + temp) * decay;

            if (nextY <= minY) {
                nextY = minY;
                nextVel = 0;
            } else if (nextY >= maxY) {
                nextY = maxY;
                nextVel = 0;
            }

            flick.contentY = nextY;
            root.scrollVelocity = nextVel;

            if (Math.abs(clampedTarget - nextY) < 0.35 && Math.abs(nextVel) < 4.0) {
                flick.contentY = clampedTarget;
                root.stopSmooth();
            }
        }
    }

    onWheel: (event) => {
        let flick = root.flickTarget;
        const now = Date.now();
        const gap = now - root.lastEventMs;
        root.lastEventMs = now;

        const phase = event.phase;
        const hasAngle = event.angleDelta.y !== 0;
        const hasPixel = event.pixelDelta.y !== 0;

        // A genuine touchpad gesture stream carries scroll phases (Begin / Update / Momentum).
        // NB: the device type alone is NOT enough: some setups (e.g. Hyprland) expose scrolling
        // as a "TouchPad" yet deliver discrete 15px / 120-unit events with NoScrollPhase.
        const isStream = phase === Qt.ScrollBegin
            || phase === Qt.ScrollMomentum
            || (phase === Qt.ScrollUpdate && gap < 25);

        let dy = 0;
        let direct = false;
        if (isStream && (hasPixel || hasAngle)) {
            // Phased touchpad: the compositor / ScrollMomentum already shape the motion, so follow
            // the fingers 1:1 instead of chasing them with a spring (double smoothing felt laggy).
            direct = true;
            dy = hasPixel
                ? event.pixelDelta.y * (root.speedMultiplier / 1.8)
                : (event.angleDelta.y / 120.0) * root.pixelsPerNotch * root.speedMultiplier;
        } else if (hasPixel) {
            // Discrete steps (pixel step paired with a whole 120-unit angle, e.g. 15px / 120 from a
            // mouse wheel) accumulate into the spring target so a burst becomes one smooth glide.
            // Arbitrary pixel values (precision touchpads without scroll phases, e.g. on Windows)
            // are followed 1:1 so fingers are not magnified.
            const discrete = hasAngle && Math.abs(event.angleDelta.y) % 120 === 0;
            dy = discrete
                ? event.pixelDelta.y * root.pixelScale * root.speedMultiplier
                : event.pixelDelta.y * (root.speedMultiplier / 1.8);
        } else if (hasAngle) {
            // Plain wheel notch (120 units) or fractional high-res angleDelta.
            const absAngle = Math.abs(event.angleDelta.y);
            const notches = event.angleDelta.y / 120.0;
            let accel = 1.0;
            if (absAngle >= 120) {
                const sign = notches > 0 ? 1 : -1;
                if (sign === root.lastWheelSign && now - root.lastWheelMs < 160) {
                    root.wheelChain = Math.min(root.wheelChain + 1, 6);
                } else {
                    root.wheelChain = 0;
                }
                root.lastWheelSign = sign;
                root.lastWheelMs = now;
                // Slow notches stay precise; quick spinning accelerates up to 2.5x.
                accel = 1.0 + root.wheelChain * 0.25;
            } else {
                root.wheelChain = 0;
            }
            dy = notches * root.pixelsPerNotch * root.speedMultiplier * accel;
        }

        while (flick) {
            if (flick.interactive) {
                const handled = direct
                    ? root.panFlickable(flick, dy)
                    : root.smoothScrollByDelta(flick, dy, root.wheelOmega);
                if (handled) {
                    event.accepted = true;
                    return;
                }
            }
            flick = root.parentFlickable(flick);
        }
        event.accepted = false;
    }
}
