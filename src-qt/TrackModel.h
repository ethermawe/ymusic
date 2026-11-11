#pragma once

#include <QAbstractListModel>
#include <QJsonArray>
#include <QJsonObject>
#include <QList>
#include <QString>

struct TrackData {
    QString id;
    QString title;
    QString artists;
    QString album;
    QString duration;
    qint64 durationMs = 0;
    bool available = true;
    bool liked = false;
    QString coverUrl;
    bool hasCover = false;
    bool hasArtist = false;
    bool hasAlbum = false;
};

class TrackModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int currentIndex READ currentIndex WRITE setCurrentIndex NOTIFY currentIndexChanged)
    Q_PROPERTY(bool playing READ isPlaying WRITE setPlaying NOTIFY playingChanged)

public:
    enum TrackRoles {
        IdRole = Qt::UserRole + 1,
        TitleRole,
        ArtistsRole,
        AlbumRole,
        DurationRole,
        DurationMsRole,
        AvailableRole,
        LikedRole,
        CoverUrlRole,
        HasCoverRole,
        HasArtistRole,
        HasAlbumRole,
        IsCurrentRole,
        IsPlayingRole
    };

    explicit TrackModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int currentIndex() const { return m_currentIndex; }
    void setCurrentIndex(int index);

    bool isPlaying() const { return m_playing; }
    void setPlaying(bool playing);

    void setTracks(const QJsonArray &tracksArray, int currentIndex);

signals:
    void currentIndexChanged();
    void playingChanged();

private:
    QList<TrackData> m_tracks;
    int m_currentIndex = -1;
    bool m_playing = false;
};
