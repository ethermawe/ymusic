#include "CardModel.h"

CardModel::CardModel(QObject *parent)
    : QAbstractListModel(parent) {}

int CardModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid()) return 0;
    return m_cards.size();
}

QVariant CardModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_cards.size())
        return QVariant();

    const CardData &c = m_cards.at(index.row());
    switch (role) {
    case TitleRole: return c.title;
    case SubtitleRole: return c.subtitle;
    case KindRole: return c.kind;
    case CoverUrlRole: return c.coverUrl;
    case HasCoverRole: return c.hasCover;
    default: return QVariant();
    }
}

QHash<int, QByteArray> CardModel::roleNames() const {
    QHash<int, QByteArray> roles;
    roles[TitleRole] = "title";
    roles[SubtitleRole] = "subtitle";
    roles[KindRole] = "kind";
    roles[CoverUrlRole] = "coverUrl";
    roles[HasCoverRole] = "hasCover";
    return roles;
}

void CardModel::setCards(const QJsonArray &cardsArray) {
    const int oldCount = m_cards.size();
    beginResetModel();
    m_cards.clear();
    m_cards.reserve(cardsArray.size());

    for (const QJsonValue &val : cardsArray) {
        QJsonObject obj = val.toObject();
        CardData c;
        c.title = obj["title"].toString();
        c.subtitle = obj["subtitle"].toString();
        c.kind = obj["kind"].toString();
        c.coverUrl = obj["cover_url"].toString();
        c.hasCover = obj["has_cover"].toBool();
        m_cards.append(c);
    }
    endResetModel();
    if (oldCount != m_cards.size()) emit countChanged();
}
