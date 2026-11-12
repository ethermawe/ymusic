cmake_minimum_required(VERSION 3.20)
project(ymusic_qt LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Quick Qml QuickControls2)

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
    ymusic_core.h
)

set(QML_FILES
    qml/Main.qml
    qml/design/Appearance.qml
    qml/components/MaterialSymbol.qml
    qml/components/IconButton.qml
    qml/components/PlayHeroButton.qml
    qml/components/StyledSlider.qml
    qml/player/FloatingPlayerBar.qml
    qml/player/EqualizerBars.qml
    qml/library/TrackRow.qml
    qml/library/CardItem.qml
    qml/library/CollectionHero.qml
    qml/sidebar/Sidebar.qml
    qml/immersive/ImmersivePlayer.qml
)

set_source_files_properties(qml/design/Appearance.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(ymusic-qml
    URI ymusic.ui
    VERSION 1.0
    QML_FILES ${QML_FILES}
)

target_include_directories(ymusic-qml PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_directories(ymusic-qml PRIVATE ${RUST_LIB_DIR})
target_link_libraries(ymusic-qml PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Qml
    Qt6::QuickControls2
    ymusic_core
    pthread
    dl
    m
)

set_target_properties(ymusic-qml PROPERTIES
    BUILD_RPATH "${RUST_LIB_DIR}"
    INSTALL_RPATH "$ORIGIN;${RUST_LIB_DIR}"
)
