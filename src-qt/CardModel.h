#pragma once

#include <QAbstractListModel>
#include <QJsonArray>
#include <QJsonObject>
#include <QList>
#include <QString>

struct CardData {
    QString title;
    QString subtitle;
    QString kind;
    QString coverUrl;
    bool hasCover = false;
};

class CardModel : public QAbstractListModel {
    Q_OBJECT

public:
    enum CardRoles {
        TitleRole = Qt::UserRole + 1,
        SubtitleRole,
        KindRole,
        CoverUrlRole,
        HasCoverRole
    };

    explicit CardModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setCards(const QJsonArray &cardsArray);

private:
    QList<CardData> m_cards;
};
