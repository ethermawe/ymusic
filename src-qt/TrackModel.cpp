#include "TrackModel.h"

TrackModel::TrackModel(QObject *parent)
    : QAbstractListModel(parent) {}

int TrackModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) return 0;
    return m_tracks.size();
}

QVariant TrackModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_tracks.size())
        return QVariant();

    const TrackData &t = m_tracks.at(index.row());
    switch (role) {
    case IdRole: return t.id;
    case TitleRole: return t.title;
    case ArtistsRole: return t.artists;
    case ArtistLinksRole: return t.artistLinks;
    case AlbumRole: return t.album;
    case DurationRole: return t.duration;
    case DurationMsRole: return t.durationMs;
    case AvailableRole: return t.available;
    case LikedRole: return t.liked;
    case DownloadedRole: return t.downloaded;
    case CoverUrlRole: return t.coverUrl;
    case HasCoverRole: return t.hasCover;
    case HasArtistRole: return t.hasArtist;
    case HasAlbumRole: return t.hasAlbum;
    case IsCurrentRole: return index.row() == m_currentIndex;
    case IsPlayingRole: return (index.row() == m_currentIndex) && m_playing;
    default: return QVariant();
    }
}

QHash<int, QByteArray> TrackModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[IdRole] = "id";
    roles[TitleRole] = "title";
    roles[ArtistsRole] = "artists";
    roles[ArtistLinksRole] = "artistLinks";
    roles[AlbumRole] = "album";
    roles[DurationRole] = "duration";
    roles[DurationMsRole] = "durationMs";
    roles[AvailableRole] = "available";
    roles[LikedRole] = "liked";
    roles[DownloadedRole] = "downloaded";
    roles[CoverUrlRole] = "coverUrl";
    roles[HasCoverRole] = "hasCover";
    roles[HasArtistRole] = "hasArtist";
    roles[HasAlbumRole] = "hasAlbum";
    roles[IsCurrentRole] = "isCurrent";
    roles[IsPlayingRole] = "isPlaying";
    return roles;
}

void TrackModel::setCurrentIndex(int index) {
    if (m_currentIndex != index) {
        int oldIndex = m_currentIndex;
        m_currentIndex = index;
        if (oldIndex >= 0 && oldIndex < m_tracks.size()) {
            emit dataChanged(this->index(oldIndex), this->index(oldIndex), {IsCurrentRole, IsPlayingRole});
        }
        if (m_currentIndex >= 0 && m_currentIndex < m_tracks.size()) {
            emit dataChanged(this->index(m_currentIndex), this->index(m_currentIndex), {IsCurrentRole, IsPlayingRole});
        }
        emit currentIndexChanged();
    }
}

void TrackModel::setPlaying(bool playing) {
    if (m_playing != playing) {
        m_playing = playing;
        if (m_currentIndex >= 0 && m_currentIndex < m_tracks.size()) {
            emit dataChanged(this->index(m_currentIndex), this->index(m_currentIndex), {IsPlayingRole});
        }
        emit playingChanged();
    }
}

void TrackModel::setTracks(const QJsonArray &tracksArray, int currentIndex) {
    const int oldCount = m_tracks.size();
    bool sameOrder = oldCount == tracksArray.size();
    for (int i = 0; sameOrder && i < oldCount; ++i)
        sameOrder = m_tracks[i].id == tracksArray[i].toObject()["id"].toString();

    // Progress/like/queue refreshes must not destroy and rebuild every delegate
    // (including its image textures and multisampled icon surfaces).
    if (!sameOrder) {
        beginResetModel();
        m_tracks.clear();
        m_tracks.reserve(tracksArray.size());
    }

    int row = 0;
    for (const QJsonValue &val : tracksArray) {
        QJsonObject obj = val.toObject();
        TrackData t;
        t.id = obj["id"].toString();
        t.title = obj["title"].toString();
        t.artists = obj["artists"].toString();
        t.artistLinks = obj["artist_links"].toArray().toVariantList();
        t.album = obj["album"].toString();
        t.duration = obj["duration"].toString();
        t.durationMs = obj["duration_ms"].toInteger();
        t.available = obj["available"].toBool();
        t.liked = obj["liked"].toBool();
        t.downloaded = obj["downloaded"].toBool();
        t.coverUrl = obj["cover_url"].toString();
        t.hasCover = obj["has_cover"].toBool();
        t.hasArtist = obj["has_artist"].toBool();
        t.hasAlbum = obj["has_album"].toBool();
        if (sameOrder) m_tracks[row] = t;
        else m_tracks.append(t);
        ++row;
    }
    const int oldCurrent = m_currentIndex;
    m_currentIndex = currentIndex;
    if (!sameOrder) endResetModel();
    else if (!m_tracks.isEmpty()) emit dataChanged(index(0), index(m_tracks.size() - 1));
    if (oldCurrent != m_currentIndex) emit currentIndexChanged();
    if (oldCount != m_tracks.size()) emit countChanged();
}
