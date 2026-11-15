#pragma once

#include <QAbstractListModel>
#include <QJsonArray>
#include <QJsonObject>
#include <QList>
#include <QString>

struct CardData {
    QString key;
    QString title;
    QString subtitle;
    QString kind;
    QString section;
    QString coverUrl;
    bool hasCover = false;
    bool pinned = false;
};

class CardModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int revision READ revision NOTIFY cardsUpdated)

public:
    enum CardRoles {
        KeyRole = Qt::UserRole + 1,
        TitleRole,
        SubtitleRole,
        KindRole,
        SectionRole,
        CoverUrlRole,
        HasCoverRole,
        PinnedRole
    };

    explicit CardModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return m_cards.size(); }
    int revision() const { return m_revision; }
    void setCards(const QJsonArray &cardsArray);
    Q_INVOKABLE QVariantList cardsForSection(const QString &section) const;

signals:
    void countChanged();
    void cardsUpdated();

private:
    QList<CardData> m_cards;
    int m_revision = 0;
};
