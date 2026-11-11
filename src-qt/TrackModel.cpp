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
    case AlbumRole: return t.album;
    case DurationRole: return t.duration;
    case DurationMsRole: return t.durationMs;
    case AvailableRole: return t.available;
    case LikedRole: return t.liked;
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
    roles[AlbumRole] = "album";
    roles[DurationRole] = "duration";
    roles[DurationMsRole] = "durationMs";
    roles[AvailableRole] = "available";
    roles[LikedRole] = "liked";
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
    beginResetModel();
    m_tracks.clear();
    m_tracks.reserve(tracksArray.size());

    for (const QJsonValue &val : tracksArray) {
        QJsonObject obj = val.toObject();
        TrackData t;
        t.id = obj["id"].toString();
        t.title = obj["title"].toString();
        t.artists = obj["artists"].toString();
        t.album = obj["album"].toString();
        t.duration = obj["duration"].toString();
        t.durationMs = obj["duration_ms"].toInteger();
        t.available = obj["available"].toBool();
        t.liked = obj["liked"].toBool();
        t.coverUrl = obj["cover_url"].toString();
        t.hasCover = obj["has_cover"].toBool();
        t.hasArtist = obj["has_artist"].toBool();
        t.hasAlbum = obj["has_album"].toBool();
        m_tracks.append(t);
    }
    m_currentIndex = currentIndex;
    endResetModel();
    emit currentIndexChanged();
}
