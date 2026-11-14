pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import ymusic.ui

QtObject {
    id: root

    property bool immersiveOpen: false
    property bool showingLyrics: false
    property bool showingQueue: false

    function openImmersive() {
        immersiveOpen = true
        ensureLyrics(false)
    }

    function closeImmersive() {
        immersiveOpen = false
    }

    function toggleLyricsPanel() {
        showingLyrics = !showingLyrics
        if (showingLyrics) {
            showingQueue = false
            ensureLyrics(true)
        }
    }

    function toggleQueuePanel() {
        showingQueue = !showingQueue
        if (showingQueue) {
            showingLyrics = false
        }
    }

    /// Music plays and the window is active/open: squiggles and spinning shapes follow this.
    property bool spinning: false
    property real spinSpeed: spinning && !Appearance.reduceMotion ? 0.9 : 0
    Behavior on spinSpeed {
        NumberAnimation { duration: 900; easing.type: Easing.InOutSine }
    }
    readonly property real spin: spinClock.value
    readonly property Binding spinDrive: Binding {
        target: spinClock
        property: "speed"
        value: root.spinSpeed
    }

    /// True once pointer settles still inside the immersive player.
    property bool pointerResting: false

    // Shared lyrics state used by both LyricsPanel and ImmersiveLyrics
    property string lyricsTrackId: ""
    property bool lyricsLoading: false
    property bool lyricsSynced: false
    property var lyricsLines: []
    property string lyricsMessage: ""
    // Smooth 60fps playback position interpolation while synced lyrics are visible
    property real smoothPositionSecs: backend.positionSecs
    readonly property bool karaokeClockActive: backend.playing && lyricsSynced && (showingLyrics || immersiveOpen)

    readonly property Connections lyricsPosSync: Connections {
        target: backend
        function onProgressChanged() {
            if (!root.karaokeClockActive || Math.abs(root.smoothPositionSecs - backend.positionSecs) > 0.35) {
                root.smoothPositionSecs = backend.positionSecs
            }
        }
        function onNowPlayingChanged() {
            root.smoothPositionSecs = 0
        }
    }

    readonly property FrameAnimation karaokeFrame: FrameAnimation {
        running: root.karaokeClockActive
        onTriggered: {
            const nextPos = root.smoothPositionSecs + frameTime
            const cap = backend.durationSecs > 0 ? Math.min(backend.durationSecs, backend.positionSecs + 0.35) : backend.positionSecs + 0.35
            root.smoothPositionSecs = Math.min(cap, Math.max(backend.positionSecs - 0.15, nextPos))
        }
    }

    readonly property int activeLyricIndex: {
        if (!lyricsSynced || !lyricsLines || lyricsLines.length === 0) {
            return -1
        }
        const pos = smoothPositionSecs + 0.15
        let idx = -1
        for (let i = 0; i < lyricsLines.length; ++i) {
            const rawTime = lyricsLines[i] ? lyricsLines[i].time : undefined
            if (rawTime === undefined || rawTime === null) {
                continue
            }
            const t = Number(rawTime)
            if (!isNaN(t) && t <= pos) {
                idx = i
            } else if (!isNaN(t) && t > pos) {
                break
            }
        }
        return idx
    }

    readonly property real firstLyricTimeSecs: {
        if (!lyricsSynced || !lyricsLines || lyricsLines.length === 0) {
            return -1
        }
        for (let i = 0; i < lyricsLines.length; ++i) {
            const raw = lyricsLines[i] ? lyricsLines[i].time : undefined
            if (raw !== undefined && raw !== null) {
                const t = Number(raw)
                if (!isNaN(t)) {
                    return t
                }
            }
        }
        return -1
    }

    readonly property real activeLyricProgress: {
        if (!lyricsSynced || !lyricsLines || lyricsLines.length === 0) {
            return 0
        }
        const idx = activeLyricIndex
        if (idx < 0) {
            if (firstLyricTimeSecs <= 0.1) {
                return 0
            }
            return Math.max(0, Math.min(1, smoothPositionSecs / firstLyricTimeSecs))
        }
        const start = Number(lyricsLines[idx].time)
        let end = backend.durationSecs > start ? backend.durationSecs : start + 4.0
        for (let i = idx + 1; i < lyricsLines.length; ++i) {
            const raw = lyricsLines[i] ? lyricsLines[i].time : undefined
            if (raw !== undefined && raw !== null) {
                const nextT = Number(raw)
                if (!isNaN(nextT) && nextT > start) {
                    end = nextT
                    break
                }
            }
        }
        const span = Math.max(0.25, end - start)
        return Math.max(0, Math.min(1, (smoothPositionSecs + 0.15 - start) / span))
    }

    function formatLyricTime(secs: real): string {
        if (isNaN(secs) || secs < 0) {
            return ""
        }
        const total = Math.floor(secs)
        const m = Math.floor(total / 60)
        const s = total % 60
        return m + ":" + (s < 10 ? "0" + s : "" + s)
    }

    function ensureLyrics(forceCheck: bool) {
        if (!backend.hasTrack || backend.nowId === "") {
            return
        }
        if (!forceCheck && !immersiveOpen && !showingLyrics) {
            return
        }
        if (lyricsTrackId === backend.nowId) {
            if (!forceCheck || lyricsLoading || (lyricsLines && lyricsLines.length > 0)) {
                return
            }
        }
        lyricsTrackId = backend.nowId
        lyricsLoading = true
        lyricsSynced = false
        lyricsLines = []
        lyricsMessage = ""
        backend.feature({ action: "lyrics", id: backend.nowId })
    }

    readonly property Connections lyricsWatcher: Connections {
        target: backend
        function onNowPlayingChanged() { root.ensureLyrics(false) }
        function onFeatureResult(result) {
            if (result.type === "toast" && result.message) {
                root.showToast(String(result.message))
            } else if (result.type === "lyrics" && result.trackId === root.lyricsTrackId) {
                root.lyricsLoading = false
                root.lyricsSynced = Boolean(result.synced)
                root.lyricsLines = result.lines || []
                root.lyricsMessage = result.message || ""
            }
        }
    }

    /// Hero artwork flight between CardItem and CollectionHero
    property rect heroFrom
    property real heroBaseSize: 0
    property url heroSource
    property bool heroCircular: false
    property bool heroArmed: false
    property var heroCover: null
    property real heroFromRadius: Appearance.sizes.artworkRadius
    property real heroToRadius: Appearance.sizes.artworkRadius
    property Item heroTarget: null
    property bool heroReady: false
    readonly property Timer heroExpiry: Timer {
        interval: 600
        onTriggered: root.heroArmed = false
    }

    function launchHero(cover: var, source: url, circular: bool) {
        if (Appearance.performanceMode || !cover || cover.width <= 0 || source.toString().length === 0) {
            return
        }
        heroFrom = cover.mapToItem(null, 0, 0, cover.width, cover.height)
        heroBaseSize = cover.width
        heroSource = source
        heroCircular = circular
        heroCover = cover
        heroFromRadius = cover.radius
        heroToRadius = Appearance.sizes.artworkRadius
        heroArmed = true
        heroExpiry.restart()
    }

    function launchReturn(from: rect, cover: var, source: url, circular: bool) {
        if (Appearance.performanceMode || !cover) {
            return
        }
        heroArmed = false
        heroExpiry.stop()
        heroFrom = from
        heroBaseSize = cover.width
        heroSource = source
        heroCircular = circular
        heroFromRadius = Appearance.sizes.artworkRadius
        heroToRadius = cover.radius
        heroReady = true
        heroTarget = cover
    }

    function claimHero(box: Item): bool {
        if (!heroArmed) {
            return false
        }
        heroArmed = false
        heroExpiry.stop()
        heroReady = false
        heroTarget = box
        return true
    }

    signal toastRequested(string message)
    signal burstRequested(Item item, string kind)
    signal createPlaylistRequested()
    signal settingsRequested()

    function burst(item: Item, kind: string) {
        if (item !== null && !Appearance.performanceMode) {
            burstRequested(item, kind)
        }
    }

    function showToast(message: string) {
        if (message && message.length > 0) {
            toastRequested(message)
        }
    }

    function goToAlbum() {
        immersiveOpen = false
        backend.openNowAlbum()
    }

    function goToArtist(artistId: string, artistName: string) {
        immersiveOpen = false
        if (artistId && artistId.length > 0) {
            backend.openArtist(artistId)
        } else {
            backend.openNowArtist()
        }
    }
}
