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
    Q_PROPERTY(int count READ count NOTIFY countChanged)

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

    int count() const { return m_cards.size(); }
    void setCards(const QJsonArray &cardsArray);

signals:
    void countChanged();

private:
    QList<CardData> m_cards;
};
