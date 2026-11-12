#pragma once

#include <QObject>
#include <QString>
#include <QPointer>
#include <QUrl>
#include <QVariantList>
#include "TrackModel.h"
#include "CardModel.h"
#include "ymusic_core.h"

class YMusicBackend : public QObject {
    Q_OBJECT

    // Auth
    Q_PROPERTY(bool loggedIn READ loggedIn NOTIFY authChanged)
    Q_PROPERTY(bool authReady READ authReady NOTIFY authChanged)
    Q_PROPERTY(bool loginBusy READ loginBusy NOTIFY authChanged)
    Q_PROPERTY(QString loginCode READ loginCode NOTIFY authChanged)
    Q_PROPERTY(QString loginUrl READ loginUrl NOTIFY authChanged)
    Q_PROPERTY(QString userName READ userName NOTIFY authChanged)
    Q_PROPERTY(QString userAvatar READ userAvatar NOTIFY authChanged)
    Q_PROPERTY(bool userHasAvatar READ userHasAvatar NOTIFY authChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusChanged)

    // View / Header
    Q_PROPERTY(int page READ page NOTIFY viewHeaderChanged)
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY viewHeaderChanged)
    Q_PROPERTY(QString listTitle READ listTitle NOTIFY viewHeaderChanged)
    Q_PROPERTY(QString listCover READ listCover NOTIFY viewHeaderChanged)
    Q_PROPERTY(QString listSubtitle READ listSubtitle NOTIFY viewHeaderChanged)
    Q_PROPERTY(bool listLoading READ listLoading NOTIFY viewHeaderChanged)
    Q_PROPERTY(bool isArtistView READ isArtistView NOTIFY viewHeaderChanged)
    Q_PROPERTY(QString artistName READ artistName NOTIFY viewHeaderChanged)
    Q_PROPERTY(QString artistGenres READ artistGenres NOTIFY viewHeaderChanged)
    Q_PROPERTY(QString artistStats READ artistStats NOTIFY viewHeaderChanged)
    Q_PROPERTY(QString artistAvatar READ artistAvatar NOTIFY viewHeaderChanged)
    Q_PROPERTY(bool artistHasAvatar READ artistHasAvatar NOTIFY viewHeaderChanged)
    Q_PROPERTY(bool canStartArtistWave READ canStartArtistWave NOTIFY viewHeaderChanged)

    // Now Playing
    Q_PROPERTY(bool hasTrack READ hasTrack NOTIFY nowPlayingChanged)
    Q_PROPERTY(QString nowId READ nowId NOTIFY nowPlayingChanged)
    Q_PROPERTY(QString nowTitle READ nowTitle NOTIFY nowPlayingChanged)
    Q_PROPERTY(QString nowArtists READ nowArtists NOTIFY nowPlayingChanged)
    Q_PROPERTY(QString nowAlbum READ nowAlbum NOTIFY nowPlayingChanged)
    Q_PROPERTY(QString nowCover READ nowCover NOTIFY nowPlayingChanged)
    Q_PROPERTY(bool hasCover READ hasCover NOTIFY nowPlayingChanged)
    Q_PROPERTY(QString durationText READ durationText NOTIFY nowPlayingChanged)
    Q_PROPERTY(bool nowLiked READ nowLiked NOTIFY nowPlayingChanged)
    Q_PROPERTY(bool nowHasArtist READ nowHasArtist NOTIFY nowPlayingChanged)
    Q_PROPERTY(bool nowHasAlbum READ nowHasAlbum NOTIFY nowPlayingChanged)

    // Progress
    Q_PROPERTY(qreal progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString positionText READ positionText NOTIFY progressChanged)

    // Playback State
    Q_PROPERTY(bool playing READ playing NOTIFY playbackStateChanged)
    Q_PROPERTY(bool buffering READ buffering NOTIFY playbackStateChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool shuffle READ shuffle NOTIFY playbackStateChanged)
    Q_PROPERTY(int repeatMode READ repeatMode NOTIFY playbackStateChanged)

    // Models
    Q_PROPERTY(TrackModel* tracks READ tracks CONSTANT)
    Q_PROPERTY(TrackModel* queue READ queue CONSTANT)
    Q_PROPERTY(CardModel* cards READ cards CONSTANT)

public:
    explicit YMusicBackend(QObject *parent = nullptr);
    ~YMusicBackend() override;

    bool loggedIn() const { return m_loggedIn; }
    bool authReady() const { return m_authReady; }
    bool loginBusy() const { return m_loginBusy; }
    QString loginCode() const { return m_loginCode; }
    QString loginUrl() const { return m_loginUrl; }
    QString userName() const { return m_userName; }
    QString userAvatar() const { return m_userAvatar; }
    bool userHasAvatar() const { return m_userHasAvatar; }
    QString statusMessage() const { return m_statusMessage; }

    int page() const { return m_page; }
    bool canGoBack() const { return m_page == 6; }
    QString listTitle() const { return m_listTitle; }
    QString listCover() const { return m_listCover; }
    QString listSubtitle() const { return m_listSubtitle; }
    bool listLoading() const { return m_listLoading; }
    bool isArtistView() const { return m_isArtistView; }
    QString artistName() const { return m_artistName; }
    QString artistGenres() const { return m_artistGenres; }
    QString artistStats() const { return m_artistStats; }
    QString artistAvatar() const { return m_artistAvatar; }
    bool artistHasAvatar() const { return m_artistHasAvatar; }
    bool canStartArtistWave() const { return m_canStartArtistWave; }

    bool hasTrack() const { return m_hasTrack; }
    QString nowId() const { return m_nowId; }
    QString nowTitle() const { return m_nowTitle; }
    QString nowArtists() const { return m_nowArtists; }
    QString nowAlbum() const { return m_nowAlbum; }
    QString nowCover() const { return m_nowCover; }
    bool hasCover() const { return m_hasCover; }
    QString durationText() const { return m_durationText; }
    bool nowLiked() const { return m_nowLiked; }
    bool nowHasArtist() const { return m_nowHasArtist; }
    bool nowHasAlbum() const { return m_nowHasAlbum; }

    qreal progress() const { return m_progress; }
    QString positionText() const { return m_positionText; }

    bool playing() const { return m_playing; }
    bool buffering() const { return m_buffering; }
    qreal volume() const { return m_volume; }
    bool shuffle() const { return m_shuffle; }
    int repeatMode() const { return m_repeatMode; }

    TrackModel* tracks() { return &m_trackModel; }
    TrackModel* queue() { return &m_queueModel; }
    CardModel* cards() { return &m_cardModel; }

    // Q_INVOKABLE Actions
    Q_INVOKABLE void loginDevice();
    Q_INVOKABLE void loginToken(const QString &token);
    Q_INVOKABLE void logout();

    Q_INVOKABLE void loadHome();
    Q_INVOKABLE void loadLikes();
    Q_INVOKABLE void loadDownloads();
    Q_INVOKABLE void loadPlaylistChoices(const QString &id);
    Q_INVOKABLE void addToPlaylist(const QString &id, const QString &kind);
    Q_INVOKABLE void removeDownload(const QString &id);
    Q_INVOKABLE bool isDownloaded(const QString &id) const;
    Q_INVOKABLE void loadPlaylists();
    Q_INVOKABLE void loadAlbums();
    Q_INVOKABLE void loadArtists();
    Q_INVOKABLE void goBack();

    Q_INVOKABLE void startWave();
    Q_INVOKABLE void startArtistWave();
    Q_INVOKABLE void search(const QString &query);

    Q_INVOKABLE void openCard(int index);
    Q_INVOKABLE void openTrackArtist(int index);
    Q_INVOKABLE void openTrackAlbum(int index);
    Q_INVOKABLE void openNowArtist();
    Q_INVOKABLE void openNowAlbum();

    Q_INVOKABLE void play(int index);
    Q_INVOKABLE void trackAction(const QString &id, int action);
    Q_INVOKABLE void saveOffline(const QString &id);
    Q_INVOKABLE void downloadTrack(const QString &id, const QUrl &destination);
    Q_INVOKABLE void copyText(const QString &text);
    Q_INVOKABLE void requestTrackMenu(const QString &id, const QString &title, bool available, qreal x, qreal y) {
        emit trackMenuRequested(id, title, available, x, y);
    }
    Q_INVOKABLE void toggle();
    Q_INVOKABLE void next();
    Q_INVOKABLE void prev();
    Q_INVOKABLE void seek(qreal fraction);
    Q_INVOKABLE void setVolume(qreal vol);
    Q_INVOKABLE void toggleMute();
    Q_INVOKABLE void toggleShuffle();
    Q_INVOKABLE void toggleRepeat();

    Q_INVOKABLE void toggleLike(int index);
    Q_INVOKABLE void toggleNowLike();
    Q_INVOKABLE void dislikeNow();
    Q_INVOKABLE void clearStatus();

signals:
    void playlistPickerResult(const QString &id, const QString &stage, const QVariantList &playlists, const QString &message);
    void trackMenuRequested(const QString &id, const QString &title, bool available, qreal x, qreal y);
    void authChanged();
    void statusChanged();
    void viewHeaderChanged();
    void nowPlayingChanged();
    void progressChanged();
    void playbackStateChanged();
    void volumeChanged();

private:
    void handleEvent(int eventType, const QString &jsonData);
    static void cCallback(int32_t eventType, const char *jsonData, void *userData);

    CoreHandle *m_core = nullptr;
    TrackModel m_trackModel;
    TrackModel m_queueModel;
    CardModel m_cardModel;

    bool m_loggedIn = false;
    bool m_authReady = false;
    bool m_loginBusy = false;
    QString m_loginCode;
    QString m_loginUrl;
    QString m_userName;
    QString m_userAvatar;
    bool m_userHasAvatar = false;
    QString m_statusMessage;

    int m_page = 0;
    int m_previousPage = 0;
    QString m_listTitle;
    QString m_listCover;
    QString m_listSubtitle;
    bool m_listLoading = false;
    bool m_isArtistView = false;
    QString m_artistName;
    QString m_artistGenres;
    QString m_artistStats;
    QString m_artistAvatar;
    bool m_artistHasAvatar = false;
    bool m_canStartArtistWave = false;

    bool m_hasTrack = false;
    QString m_nowId;
    QString m_nowTitle;
    QString m_nowArtists;
    QString m_nowAlbum;
    QString m_nowCover;
    bool m_hasCover = false;
    QString m_durationText = "0:00";
    bool m_nowLiked = false;
    bool m_nowHasArtist = false;
    bool m_nowHasAlbum = false;

    qreal m_progress = 0.0;
    QString m_positionText = "0:00";

    bool m_playing = false;
    bool m_buffering = false;
    qreal m_volume = 0.7;
    bool m_shuffle = false;
    int m_repeatMode = 0;
};
