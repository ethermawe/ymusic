cmake_minimum_required(VERSION 3.20)
project(ymusic_qt LANGUAGES CXX)
include(GNUInstallDirs)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Widgets Quick Qml QuickControls2 QuickEffects Network ShaderTools Svg)

if(Qt6_VERSION VERSION_GREATER_EQUAL "6.8")
    qt_policy(SET QTP0004 NEW)
endif()

set(RUST_LIB_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../target/release")

qt_add_executable(ymusic-qml
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
)

set(QML_FILES
    qml/Main.qml
    qml/design/Appearance.qml
    qml/motion/Bounce.qml
    qml/motion/ClickBounce.qml
    qml/motion/ElementMove.qml
    qml/motion/ElementMoveSmall.qml
    qml/motion/ElementMoveFastColor.qml
    qml/motion/HoverFade.qml
    qml/components/MaterialSymbol.qml
    qml/components/StyledText.qml
    qml/components/StyledButton.qml
    qml/components/StyledComboBox.qml
    qml/components/StyledCheckBox.qml
    qml/components/TitleText.qml
    qml/components/IconButton.qml
    qml/components/LikeBurst.qml
    qml/components/PlayHeroButton.qml
    qml/components/RoundedImage.qml
    qml/components/WavyLine.qml
    qml/components/MaterialShape.qml
    qml/components/SectionHeader.qml
    qml/components/Stickers.qml
    qml/components/RollingText.qml
    qml/components/EmptyState.qml
    qml/components/TransportButton.qml
    qml/components/StyledSlider.qml
    qml/components/HomeShortcut.qml
    qml/shell/SectionLabel.qml
    qml/shell/NavigationItem.qml
    qml/player/FloatingPlayerBar.qml
    qml/player/VolumeControl.qml
    qml/player/EqualizerBars.qml
    qml/library/TrackRow.qml
    qml/library/TrackMenu.qml
    qml/library/PlaylistPicker.qml
    qml/library/CreatePlaylistDialog.qml
    qml/views/SearchView.qml
    qml/views/WaveHero.qml
    qml/views/LoginView.qml
    qml/views/SettingsDialog.qml
    qml/library/CardItem.qml
    qml/library/CollectionHero.qml
    qml/views/HomeView.qml
    qml/sidebar/Sidebar.qml
    qml/immersive/ImmersivePlayer.qml
)

set_source_files_properties(qml/design/Appearance.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(ymusic-qml
    URI ymusic.ui
    RESOURCE_PREFIX /qt/qml
    VERSION 1.0
    QML_FILES ${QML_FILES}
)

qt_add_shaders(ymusic-qml "ymusic_shaders"
    PREFIX "/shaders"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/shaders"
    FILES
        shaders/wavy_progress.frag
        shaders/rounded_image.frag
        shaders/wavy_line.frag
        shaders/artwork_backdrop.frag
        shaders/gaussian_blur.frag
)

set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/../icon.svg" PROPERTIES
    QT_RESOURCE_ALIAS "icons/ymusic.svg"
)
set_source_files_properties("${CMAKE_CURRENT_SOURCE_DIR}/../icons/hicolor/256x256/apps/ymusic.png" PROPERTIES
    QT_RESOURCE_ALIAS "icons/ymusic.png"
)
qt_add_resources(ymusic-qml "ymusic_icons"
    PREFIX "/"
    FILES
        "${CMAKE_CURRENT_SOURCE_DIR}/../icon.svg"
        "${CMAKE_CURRENT_SOURCE_DIR}/../icons/hicolor/256x256/apps/ymusic.png"
)

target_include_directories(ymusic-qml PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_directories(ymusic-qml PRIVATE ${RUST_LIB_DIR})
target_link_libraries(ymusic-qml PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Widgets
    Qt6::Quick
    Qt6::Qml
    Qt6::QuickControls2
    Qt6::QuickEffects
    Qt6::Network
    Qt6::Svg
)

if(WIN32)
    if(MSVC)
        target_link_libraries(ymusic-qml PRIVATE "${RUST_LIB_DIR}/ymusic_core.dll.lib")
    else()
        target_link_libraries(ymusic-qml PRIVATE ymusic_core)
    endif()
    set_target_properties(ymusic-qml PROPERTIES WIN32_EXECUTABLE TRUE)
    add_custom_command(TARGET ymusic-qml POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${RUST_LIB_DIR}/ymusic_core.dll"
            "$<TARGET_FILE_DIR:ymusic-qml>/ymusic_core.dll"
    )
    install(TARGETS ymusic-qml RUNTIME DESTINATION .)
    install(FILES "${RUST_LIB_DIR}/ymusic_core.dll" DESTINATION .)
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
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../ymusic.desktop" DESTINATION ${CMAKE_INSTALL_DATADIR}/applications)
    install(DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../icons/hicolor" DESTINATION ${CMAKE_INSTALL_DATADIR}/icons)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../icon.svg" DESTINATION ${CMAKE_INSTALL_DATADIR}/icons/hicolor/scalable/apps RENAME ymusic.svg)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../icon.svg" DESTINATION ${CMAKE_INSTALL_DATADIR}/pixmaps RENAME ymusic.svg)
    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../icons/hicolor/256x256/apps/ymusic.png" DESTINATION ${CMAKE_INSTALL_DATADIR}/pixmaps)

    install(CODE "
        file(CREATE_LINK \"ymusic-qml\" \"\$ENV{DESTDIR}${CMAKE_INSTALL_FULL_BINDIR}/ymusic\" SYMBOLIC)
    ")
endif()
