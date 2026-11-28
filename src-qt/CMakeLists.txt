cmake_minimum_required(VERSION 3.20)
project(ymusic_qt LANGUAGES CXX)
include(GNUInstallDirs)

set(YMUSIC_VERSION "0.3.1" CACHE STRING "Application version")
string(REGEX REPLACE "^v" "" YMUSIC_VERSION_CLEAN "${YMUSIC_VERSION}")
string(REGEX MATCHALL "[0-9]+" YMUSIC_VERSION_PARTS "${YMUSIC_VERSION_CLEAN}")
list(LENGTH YMUSIC_VERSION_PARTS _ymusic_ver_len)
if(_ymusic_ver_len GREATER 0)
    list(GET YMUSIC_VERSION_PARTS 0 YMUSIC_VER_MAJOR)
else()
    set(YMUSIC_VER_MAJOR 0)
endif()
if(_ymusic_ver_len GREATER 1)
    list(GET YMUSIC_VERSION_PARTS 1 YMUSIC_VER_MINOR)
else()
    set(YMUSIC_VER_MINOR 0)
endif()
if(_ymusic_ver_len GREATER 2)
    list(GET YMUSIC_VERSION_PARTS 2 YMUSIC_VER_PATCH)
else()
    set(YMUSIC_VER_PATCH 0)
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

if(WIN32)
    add_compile_definitions(NOMINMAX _USE_MATH_DEFINES)
endif()
if(MSVC)
    add_compile_options(/utf-8)
endif()

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Widgets Quick Qml QuickControls2 Network ShaderTools Svg Concurrent)
find_package(Qt6 6.5 QUIET COMPONENTS CorePrivate GuiPrivate)

if(Qt6_VERSION VERSION_GREATER_EQUAL "6.8")
    qt_policy(SET QTP0004 NEW)
endif()

# --- fonts -------------------------------------------------------------------
include(cmake/DownloadAsset.cmake)
set(YMUSIC_FONT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/fonts")
set(YMUSIC_ICON_FONT "${YMUSIC_FONT_DIRECTORY}/MaterialSymbolsRounded.ttf")
ymusic_download_asset(
    "https://raw.githubusercontent.com/google/material-design-icons/737e3324305806514d7909874fa1818ae1808232/variablefont/MaterialSymbolsRounded%5BFILL,GRAD,opsz,wght%5D.ttf"
    "${YMUSIC_ICON_FONT}"
    95b24392bb49efd1bc3e92cff4e2452ad094461bab7c97e7d8723fab97e330ca
    YMUSIC_HAS_ICON_FONT)

set(YMUSIC_INTERFACE_FONT "${YMUSIC_FONT_DIRECTORY}/GoogleSansFlex.ttf")
set(YMUSIC_INTERFACE_FONT_LICENSE "${YMUSIC_FONT_DIRECTORY}/GoogleSansFlex-OFL.txt")
set(YMUSIC_GOOGLE_FONTS "https://raw.githubusercontent.com/google/fonts/a0e3dbcdc3a3ecfafff3f071159ae0221628922d/ofl/googlesansflex")
ymusic_download_asset(
    "${YMUSIC_GOOGLE_FONTS}/GoogleSansFlex%5BGRAD,ROND,opsz,slnt,wdth,wght%5D.ttf"
    "${YMUSIC_INTERFACE_FONT}"
    c31a482fbecbf2e07e6890134d20078723aadf732c9b9c6c9a44f86f8265b6fe
    YMUSIC_HAS_INTERFACE_FONT)
ymusic_download_asset(
    "${YMUSIC_GOOGLE_FONTS}/OFL.txt"
    "${YMUSIC_INTERFACE_FONT_LICENSE}"
    fc13d69f63e36d284b6e383d4d1463d8ad404f0aa065e57cf961252d51063137
    YMUSIC_HAS_INTERFACE_FONT_LICENSE)

# --- material-color-utilities ------------------------------------------------
file(GLOB_RECURSE MCU_SOURCES CONFIGURE_DEPENDS
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/material-color-utilities/cpp/*.cc")
add_library(material_color_utilities STATIC ${MCU_SOURCES})
target_include_directories(material_color_utilities PUBLIC
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/material-color-utilities")
set_target_properties(material_color_utilities PROPERTIES POSITION_INDEPENDENT_CODE ON)

# --- shape_atlas generator ---------------------------------------------------
set(YMUSIC_SHAPE_ATLAS_TOOL "" CACHE FILEPATH "Optional host-built shape_atlas executable for cross builds")
if(YMUSIC_SHAPE_ATLAS_TOOL)
    set(YMUSIC_SHAPE_ATLAS_COMMAND "${YMUSIC_SHAPE_ATLAS_TOOL}")
else()
    add_executable(shape_atlas tools/shape_atlas/main.cpp tools/shape_atlas/ShapeAtlasLayout.h)
    target_include_directories(shape_atlas PRIVATE tools/shape_atlas)
    target_link_libraries(shape_atlas PRIVATE Qt6::Core Qt6::Gui Qt6::Qml)
    target_compile_options(shape_atlas PRIVATE $<$<CXX_COMPILER_ID:Clang,AppleClang,GNU>:-O2>)
    set(YMUSIC_SHAPE_ATLAS_COMMAND shape_atlas)
endif()

set(YMUSIC_SHAPE_LIBRARY "${CMAKE_CURRENT_SOURCE_DIR}/third_party/rounded-polygon-qmljs")
file(GLOB_RECURSE YMUSIC_SHAPE_SOURCES CONFIGURE_DEPENDS "${YMUSIC_SHAPE_LIBRARY}/*.js")
set(YMUSIC_SHAPE_ATLAS "${CMAKE_CURRENT_BINARY_DIR}/shapes/shape_atlas.png")
add_custom_command(OUTPUT "${YMUSIC_SHAPE_ATLAS}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/shapes"
    COMMAND "${YMUSIC_SHAPE_ATLAS_COMMAND}" "${YMUSIC_SHAPE_LIBRARY}" "${YMUSIC_SHAPE_ATLAS}"
    DEPENDS "${YMUSIC_SHAPE_ATLAS_COMMAND}" ${YMUSIC_SHAPE_SOURCES}
    COMMENT "Generating Material 3 shape SDF atlas")

# --- executable & QML module -------------------------------------------------
set(RUST_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../target/release")

set(YMUSIC_CPP_SOURCES
    main.cpp
    YMusicBackend.h
    YMusicBackend.cpp
    TrackModel.h
    TrackModel.cpp
    CardModel.h
    CardModel.cpp
    ThemeManager.h
    ThemeManager.cpp
    AppSettings.h
    ymusic_core.h
    app/Fonts.h
    app/Fonts.cpp
    app/Paths.h
    app/Paths.cpp
    app/QrImageProvider.h
    app/QrImageProvider.cpp
    app/UpdateChecker.h
    app/UpdateChecker.cpp
    app/WindowController.h
    app/WindowController.cpp
    artwork/ArtworkCache.h
    artwork/ArtworkCache.cpp
    artwork/ArtworkColors.h
    artwork/ArtworkColors.cpp
    artwork/ArtworkPalette.h
    artwork/ArtworkPalette.cpp
    artwork/PlaylistCovers.h
    artwork/PlaylistCovers.cpp
    motion/AmbientClock.h
    motion/AmbientClock.cpp
    motion/FrameTicker.h
    motion/FrameTicker.cpp
    motion/Reveal.h
    motion/Reveal.cpp
    motion/ScrollMomentum.h
    motion/ScrollMomentum.cpp
    playback/ImmersiveLayout.h
    playback/ImmersiveLayout.cpp
    playback/InteractionState.h
    render/BackdropClock.h
    render/BackdropClock.cpp
    render/MaterialShapeItem.h
    render/MaterialShapeItem.cpp
    render/MaterialSymbolItem.h
    render/MaterialSymbolItem.cpp
    render/SoftShadowItem.h
    render/SoftShadowItem.cpp
    render/SpectrumItem.h
    render/SpectrumItem.cpp
    render/SpectrumShaping.h
    render/SpectrumShaping.cpp
    render/SpectrumSource.h
    render/SpectrumSource.cpp
    render/SpectrumStyle.h
    render/WavyLineItem.h
    render/WavyLineItem.cpp
    mods/ModApi.h
    mods/ModApi.cpp
    mods/ModManager.h
    mods/ModManager.cpp
    mods/ModManifest.h
    mods/ModManifest.cpp
    mods/ModNetworkAccessManager.h
    mods/ModNetworkAccessManager.cpp
    mods/ModScriptHost.h
    mods/ModScriptHost.cpp
    mods/ModSlotItem.h
    mods/ModSlotItem.cpp
    mods/ModUrlInterceptor.h
    mods/ModUrlInterceptor.cpp
    theme/ColorMath.h
    theme/MaterialScheme.h
    theme/MaterialScheme.cpp
    theme/PlayerStyle.h
    theme/PlayerStyle.cpp
    theme/Theme.h
    theme/Theme.cpp
    theme/Themes.h
    theme/Themes.cpp
)

qt_add_executable(ymusic-qml ${YMUSIC_CPP_SOURCES})

set(QML_FILES
    qml/Main.qml
    qml/design/Appearance.qml
    qml/design/Format.qml
    qml/design/Shapes.qml
    qml/design/UiState.qml
    qml/motion/Bounce.qml
    qml/motion/ClickBounce.qml
    qml/motion/Drift.qml
    qml/motion/ElementMove.qml
    qml/motion/ElementMoveEnter.qml
    qml/motion/ElementMoveExit.qml
    qml/motion/ElementMoveFast.qml
    qml/motion/ElementMoveFastColor.qml
    qml/motion/ElementMoveSmall.qml
    qml/motion/ElementResize.qml
    qml/motion/HeroFlight.qml
    qml/motion/HoverFade.qml
    qml/motion/PageTransition.qml
    qml/motion/ShapeBurst.qml
    qml/motion/SidebarSlideEnter.qml
    qml/motion/SidebarSlideExit.qml
    qml/components/AiBadge.qml
    qml/components/ArtistLinks.qml
    qml/components/ArtworkImage.qml
    qml/components/CornerCaps.qml
    qml/components/EmptyState.qml
    qml/components/FastWheel.qml
    qml/components/HomeShortcut.qml
    qml/components/IconButton.qml
    qml/components/KaraokeLyricLine.qml
    qml/components/LikeBurst.qml
    qml/components/LoadingSpinner.qml
    qml/components/MenuLoader.qml
    qml/components/ModSlotHost.qml
    qml/components/OutlinedTextField.qml
    qml/components/PlayButton.qml
    qml/components/PlayHeroButton.qml
    qml/components/Ripple.qml
    qml/components/RippleButton.qml
    qml/components/RollingText.qml
    qml/components/RoundedImage.qml
    qml/components/SearchField.qml
    qml/components/SectionHeader.qml
    qml/components/SeekBar.qml
    qml/components/Segment.qml
    qml/components/SegmentedControl.qml
    qml/components/ShapeButton.qml
    qml/components/ShapeIcon.qml
    qml/components/Snackbar.qml
    qml/components/SquiggleRing.qml
    qml/components/Stickers.qml
    qml/components/StyledButton.qml
    qml/components/StyledCheckBox.qml
    qml/components/StyledComboBox.qml
    qml/components/StyledDialog.qml
    qml/components/StyledMenu.qml
    qml/components/StyledMenuItem.qml
    qml/components/StyledMenuSeparator.qml
    qml/components/StyledScrollBar.qml
    qml/components/StyledSlider.qml
    qml/components/StyledSwitch.qml
    qml/components/StyledText.qml
    qml/components/StyledToolTip.qml
    qml/components/TextButton.qml
    qml/components/ThemeSwatch.qml
    qml/components/TitleText.qml
    qml/components/Toast.qml
    qml/components/ToolbarButton.qml
    qml/components/TransportButton.qml
    qml/components/WavyClip.qml
    qml/components/WavyPill.qml
    qml/components/WhatsNewDialog.qml
    qml/shell/NavigationItem.qml
    qml/shell/PlaybackMenu.qml
    qml/shell/SectionLabel.qml
    qml/shell/TopBar.qml
    qml/shell/WindowControls.qml
    qml/sidebar/Sidebar.qml
    qml/visualizers/CompactMeter.qml
    qml/player/EqualizerBars.qml
    qml/player/FloatingPlayerBar.qml
    qml/player/LyricsPanel.qml
    qml/player/QueuePanel.qml
    qml/player/QueueRow.qml
    qml/player/VolumeControl.qml
    qml/library/ArtworkGlow.qml
    qml/library/CardItem.qml
    qml/library/CollectionHero.qml
    qml/library/CreatePlaylistDialog.qml
    qml/library/MediaArtwork.qml
    qml/library/PlaylistPicker.qml
    qml/library/TrackMenu.qml
    qml/library/TrackRow.qml
    qml/settings/ConfigSelection.qml
    qml/settings/ConfigSlider.qml
    qml/settings/ConfigSwitch.qml
    qml/settings/ContentSection.qml
    qml/settings/NoteText.qml
    qml/settings/SettingsPages.qml
    qml/views/HomeView.qml
    qml/views/LoginView.qml
    qml/views/SearchView.qml
    qml/views/SettingsDialog.qml
    qml/views/WaveHero.qml
    qml/immersive/ImmersiveLyrics.qml
    qml/immersive/ImmersiveNowPlaying.qml
    qml/immersive/ImmersivePlayer.qml
    qml/immersive/ImmersiveQueue.qml
    qml/immersive/ImmersiveQueueRow.qml
    qml/immersive/LiquidBackdrop.qml
    qml/immersive/ScrollingText.qml
    qml/immersive/SleepTimerPanel.qml
    qml/immersive/SoundPanel.qml
)

set_source_files_properties(
    qml/design/Appearance.qml
    qml/design/Format.qml
    qml/design/Shapes.qml
    qml/design/UiState.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(ymusic-qml
    URI ymusic.ui
    RESOURCE_PREFIX /qt/qml
    VERSION 1.0
    QML_FILES ${QML_FILES}
)

set(YMUSIC_SDK_QML_FILES
    sdk/qml/Badge.qml
    sdk/qml/Card.qml
    sdk/qml/Chip.qml
    sdk/qml/ConfigSwitch.qml
    sdk/qml/ContentSection.qml
    sdk/qml/IconButton.qml
    sdk/qml/MaterialSymbol.qml
    sdk/qml/NoteText.qml
    sdk/qml/OutlinedTextField.qml
    sdk/qml/RoundedImage.qml
    sdk/qml/SpectrumBars.qml
    sdk/qml/StyledMenu.qml
    sdk/qml/StyledMenuItem.qml
    sdk/qml/StyledMenuSeparator.qml
    sdk/qml/StyledSlider.qml
    sdk/qml/StyledText.qml
    sdk/qml/TextButton.qml
    sdk/qml/TitleText.qml
)

qt_add_qml_module(ymusic_sdk
    URI ymusic.sdk
    RESOURCE_PREFIX /qt/qml
    OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/ymusic/sdk"
    VERSION 1.0
    STATIC
    SOURCES
        sdk/ModTheme.h
        sdk/ModTheme.cpp
    QML_FILES ${YMUSIC_SDK_QML_FILES}
)
target_include_directories(ymusic_sdk PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/app"
    "${CMAKE_CURRENT_SOURCE_DIR}/artwork"
    "${CMAKE_CURRENT_SOURCE_DIR}/sdk"
    "${CMAKE_CURRENT_SOURCE_DIR}/theme"
)
target_link_libraries(ymusic_sdk PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
)

qt_add_shaders(ymusic-qml "ymusic_shaders"
    BATCHABLE
    PREFIX "/shaders"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
    FILES
        shaders/arc.frag
        shaders/artwork_backdrop.frag
        shaders/backdrop_blur.frag
        shaders/backdrop_composite.frag
        shaders/edge_fade.frag
        shaders/gleam.frag
        shaders/horizontal_edge_fade.frag
        shaders/liquid_backdrop.frag
        shaders/lyric_karaoke.frag
        shaders/material_shape.frag
        shaders/material_shape.vert
        shaders/material_symbol.frag
        shaders/material_symbol.vert
        shaders/ripple.frag
        shaders/rounded_image.frag
        shaders/shape_mask.frag
        shaders/soft_shadow.frag
        shaders/soft_shadow.vert
        shaders/spectrum_bars.frag
        shaders/spectrum_bars.vert
        shaders/spectrum_halo.frag
        shaders/spectrum_halo.vert
        shaders/squiggle_ring.frag
        shaders/wave_aurora.frag
        shaders/wavy_line.frag
        shaders/wavy_line.vert
        shaders/wavy_pill.frag
        shaders/wavy_progress.frag
)

qt_add_resources(ymusic-qml "ymusic_shape_atlas"
    PREFIX "/shapes"
    BASE "${CMAKE_CURRENT_BINARY_DIR}/shapes"
    FILES "${YMUSIC_SHAPE_ATLAS}"
)

set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/../icons/hicolor/scalable/apps/ymusic.svg" PROPERTIES
    QT_RESOURCE_ALIAS "icons/ymusic.svg"
)
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/../icons/hicolor/256x256/apps/ymusic.png" PROPERTIES
    QT_RESOURCE_ALIAS "icons/ymusic.png"
)
qt_add_resources(ymusic-qml "ymusic_icons"
    PREFIX "/"
    FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/../icons/hicolor/scalable/apps/ymusic.svg"
        "${CMAKE_CURRENT_SOURCE_DIR}/../icons/hicolor/256x256/apps/ymusic.png"
)

target_include_directories(ymusic-qml PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/app"
    "${CMAKE_CURRENT_SOURCE_DIR}/artwork"
    "${CMAKE_CURRENT_SOURCE_DIR}/motion"
    "${CMAKE_CURRENT_SOURCE_DIR}/mods"
    "${CMAKE_CURRENT_SOURCE_DIR}/playback"
    "${CMAKE_CURRENT_SOURCE_DIR}/render"
    "${CMAKE_CURRENT_SOURCE_DIR}/theme"
    "${CMAKE_CURRENT_SOURCE_DIR}/tools/shape_atlas"
)

target_compile_definitions(ymusic-qml PRIVATE
    YMUSIC_BUILD_FONT_DIRECTORY="${YMUSIC_FONT_DIRECTORY}"
    YMUSIC_APP_VERSION="${YMUSIC_VERSION_CLEAN}"
)

if(WIN32)
    set(YMUSIC_WIN_ICON_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../icons/ymusic.ico")
    configure_file(
        "${CMAKE_CURRENT_SOURCE_DIR}/app/ymusic.rc.in"
        "${CMAKE_CURRENT_BINARY_DIR}/ymusic.rc"
        @ONLY
    )
    target_sources(ymusic-qml PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/ymusic.rc")
endif()

target_link_directories(ymusic-qml PRIVATE ${RUST_LIB_DIR})
target_link_libraries(ymusic-qml PRIVATE
    Qt6::Core
    $<$<TARGET_EXISTS:Qt6::CorePrivate>:Qt6::CorePrivate>
    Qt6::Gui
    $<$<TARGET_EXISTS:Qt6::GuiPrivate>:Qt6::GuiPrivate>
    Qt6::Widgets
    Qt6::Quick
    Qt6::Qml
    Qt6::QuickControls2
    Qt6::Network
    Qt6::Concurrent
    Qt6::Svg
    material_color_utilities
    ymusic_sdk
    ymusic_sdkplugin
)

if(WIN32)
    if(MSVC)
        target_link_libraries(ymusic-qml PRIVATE "${RUST_LIB_DIR}/ymusic_core.dll.lib")
    else()
        target_link_libraries(ymusic-qml PRIVATE ymusic_core)
    endif()
    target_link_libraries(ymusic-qml PRIVATE comctl32 dwmapi user32)
    set_target_properties(ymusic-qml PROPERTIES WIN32_EXECUTABLE TRUE)
    add_custom_command(TARGET ymusic-qml POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${RUST_LIB_DIR}/ymusic_core.dll"
            "$<TARGET_FILE_DIR:ymusic-qml>/ymusic_core.dll"
    )
    install(TARGETS ymusic-qml RUNTIME DESTINATION .)
    install(FILES "${RUST_LIB_DIR}/ymusic_core.dll" DESTINATION .)
    if(YMUSIC_HAS_ICON_FONT)
        install(FILES "${YMUSIC_ICON_FONT}" DESTINATION fonts)
    endif()
    if(YMUSIC_HAS_INTERFACE_FONT)
        install(FILES "${YMUSIC_INTERFACE_FONT}" DESTINATION fonts)
    endif()
    if(YMUSIC_HAS_INTERFACE_FONT_LICENSE)
        install(FILES "${YMUSIC_INTERFACE_FONT_LICENSE}" DESTINATION fonts)
    endif()
else()
    target_link_libraries(ymusic-qml PRIVATE
        ymusic_core
        pthread
        dl
        m
    )
    set_target_properties(ymusic-qml PROPERTIES
        BUILD_RPATH "${RUST_LIB_DIR}"
        INSTALL_RPATH "$ORIGIN/../${CMAKE_INSTALL_LIBDIR}/ymusic"
    )

    install(TARGETS ymusic-qml RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
    install(FILES "${RUST_LIB_DIR}/libymusic_core.so" DESTINATION ${CMAKE_INSTALL_LIBDIR}/ymusic)
    if(YMUSIC_HAS_ICON_FONT)
        install(FILES "${YMUSIC_ICON_FONT}" DESTINATION ${CMAKE_INSTALL_DATADIR}/ymusic/fonts)
    endif()
    if(YMUSIC_HAS_INTERFACE_FONT)
        install(FILES "${YMUSIC_INTERFACE_FONT}" DESTINATION ${CMAKE_INSTALL_DATADIR}/ymusic/fonts)
    endif()
    if(YMUSIC_HAS_INTERFACE_FONT_LICENSE)
        install(FILES "${YMUSIC_INTERFACE_FONT_LICENSE}" DESTINATION ${CMAKE_INSTALL_DATADIR}/ymusic/fonts)
    endif()
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../ymusic.desktop" DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../icons/hicolor" DESTINATION ${CMAKE_INSTALL_DATADIR}/icons)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../icons/hicolor/scalable/apps/ymusic.svg" DESTINATION ${CMAKE_INSTALL_DATADIR}/pixmaps RENAME ymusic.svg)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../icons/hicolor/256x256/apps/ymusic.png" DESTINATION ${CMAKE_INSTALL_DATADIR}/pixmaps)

    install(CODE "
        file(CREATE_LINK \"ymusic-qml\" \"\$ENV{DESTDIR}${CMAKE_INSTALL_FULL_BINDIR}/ymusic\" SYMBOLIC)
    ")
endif()

include(CTest)
if(BUILD_TESTING)
    add_executable(update_checker_test
        tests/UpdateCheckerTest.cpp
        app/UpdateChecker.h
        app/UpdateChecker.cpp
    )
    target_include_directories(update_checker_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_link_libraries(update_checker_test PRIVATE Qt6::Core Qt6::Gui Qt6::Network)
    target_compile_definitions(update_checker_test PRIVATE YMUSIC_APP_VERSION="${YMUSIC_VERSION_CLEAN}")
    add_test(NAME update_checker_test COMMAND update_checker_test)

    add_executable(theme_test
        tests/ThemeTest.cpp
        AppSettings.h
        app/Fonts.h
        app/Fonts.cpp
        app/Paths.h
        app/Paths.cpp
        artwork/ArtworkPalette.h
        artwork/ArtworkPalette.cpp
        theme/ColorMath.h
        theme/MaterialScheme.h
        theme/MaterialScheme.cpp
        theme/Theme.h
        theme/Theme.cpp
        theme/Themes.h
        theme/Themes.cpp
    )
    target_include_directories(theme_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_link_libraries(theme_test PRIVATE Qt6::Core Qt6::Gui Qt6::Qml material_color_utilities)
    add_test(NAME theme_test COMMAND theme_test)
    set_tests_properties(theme_test PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")

    add_executable(mod_manager_test
        tests/ModManagerTest.cpp
        AppSettings.h
        app/Fonts.h
        app/Fonts.cpp
        app/Paths.h
        app/Paths.cpp
        artwork/ArtworkPalette.h
        artwork/ArtworkPalette.cpp
        theme/ColorMath.h
        theme/MaterialScheme.h
        theme/MaterialScheme.cpp
        theme/Theme.h
        theme/Theme.cpp
        theme/Themes.h
        theme/Themes.cpp
        mods/ModApi.h
        mods/ModApi.cpp
        mods/ModManager.h
        mods/ModManager.cpp
        mods/ModManifest.h
        mods/ModManifest.cpp
        mods/ModNetworkAccessManager.h
        mods/ModNetworkAccessManager.cpp
        mods/ModScriptHost.h
        mods/ModScriptHost.cpp
        mods/ModSlotItem.h
        mods/ModSlotItem.cpp
        mods/ModUrlInterceptor.h
        mods/ModUrlInterceptor.cpp
    )
    target_include_directories(mod_manager_test PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
    target_compile_definitions(mod_manager_test PRIVATE YMUSIC_MOD_TEST_NO_BACKEND=1)
    target_link_libraries(mod_manager_test PRIVATE
        Qt6::Core
        $<$<TARGET_EXISTS:Qt6::CorePrivate>:Qt6::CorePrivate>
        Qt6::Gui
        $<$<TARGET_EXISTS:Qt6::GuiPrivate>:Qt6::GuiPrivate>
        Qt6::Qml
        Qt6::Quick
        Qt6::QuickControls2
        Qt6::Network
        material_color_utilities
        ymusic_sdk
        ymusic_sdkplugin
    )
    add_test(NAME mod_manager_test COMMAND mod_manager_test)
    set_tests_properties(mod_manager_test PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
