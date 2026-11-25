#include "app/QrImageProvider.h"

#include <QColor>
#include <QUrl>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <limits>
#include <vector>

namespace ymusic {

namespace {

struct QrVersionSpec {
    int version;
    int size;
    int totalDataBytes;
    int ecBytesPerBlock;
    int numBlocks;
    int alignPos; // 0 if none (v1), else single alignment center coord
};

// ISO/IEC 18004 ECC Level M (00) for Versions 1..6 (up to 106 UTF-8 bytes)
constexpr std::array<QrVersionSpec, 6> kSpecs = {{
    {1, 21, 16, 10, 1, 0},
    {2, 25, 28, 16, 1, 18},
    {3, 29, 44, 26, 1, 22},
    {4, 33, 64, 18, 2, 26},
    {5, 37, 86, 24, 2, 30},
    {6, 41, 108, 16, 4, 34},
}};

uint8_t gfMul(uint8_t a, uint8_t b) {
    uint8_t p = 0;
    for (int i = 0; i < 8; ++i) {
        if (b & 1) p ^= a;
        const bool hi = (a & 0x80) != 0;
        a <<= 1;
        if (hi) a ^= 0x1D;
        b >>= 1;
    }
    return p;
}

std::vector<uint8_t> rsGenerator(int degree) {
    std::vector<uint8_t> poly = {1};
    uint8_t root = 1;
    for (int i = 0; i < degree; ++i) {
        std::vector<uint8_t> next(poly.size() + 1, 0);
        for (size_t j = 0; j < poly.size(); ++j) {
            next[j] ^= poly[j];
            next[j + 1] ^= gfMul(poly[j], root);
        }
        poly = std::move(next);
        root = gfMul(root, 2);
    }
    return poly;
}

std::vector<uint8_t> rsRemainder(const std::vector<uint8_t> &data, const std::vector<uint8_t> &gen) {
    const size_t ecLen = gen.size() - 1;
    std::vector<uint8_t> rem(ecLen, 0);
    for (uint8_t b : data) {
        const uint8_t factor = b ^ rem[0];
        std::rotate(rem.begin(), rem.begin() + 1, rem.end());
        rem.back() = 0;
        for (size_t i = 0; i < ecLen; ++i) {
            rem[i] ^= gfMul(gen[i + 1], factor);
        }
    }
    return rem;
}

struct QrMatrix {
    int size = 0;
    std::vector<uint8_t> modules;    // 0 = light, 1 = dark
    std::vector<uint8_t> isFunction; // 1 = reserved/function pattern

    explicit QrMatrix(int n)
        : size(n)
        , modules(static_cast<size_t>(n * n), 0)
        , isFunction(static_cast<size_t>(n * n), 0) {}

    bool get(int x, int y) const { return modules[static_cast<size_t>(y * size + x)] != 0; }
    void setFunc(int x, int y, bool dark) {
        if (x < 0 || y < 0 || x >= size || y >= size) return;
        const auto idx = static_cast<size_t>(y * size + x);
        modules[idx] = dark ? 1 : 0;
        isFunction[idx] = 1;
    }
    void setData(int x, int y, bool dark) {
        modules[static_cast<size_t>(y * size + x)] = dark ? 1 : 0;
    }
    bool func(int x, int y) const { return isFunction[static_cast<size_t>(y * size + x)] != 0; }
};

void drawFinder(QrMatrix &m, int cx, int cy) {
    for (int dy = -4; dy <= 4; ++dy) {
        for (int dx = -4; dx <= 4; ++dx) {
            const int dist = std::max(std::abs(dx), std::abs(dy));
            const bool dark = (dist != 2 && dist != 4);
            m.setFunc(cx + dx, cy + dy, dark);
        }
    }
}

void drawAlignment(QrMatrix &m, int cx, int cy) {
    for (int dy = -2; dy <= 2; ++dy) {
        for (int dx = -2; dx <= 2; ++dx) {
            const int dist = std::max(std::abs(dx), std::abs(dy));
            m.setFunc(cx + dx, cy + dy, dist != 1);
        }
    }
}

uint16_t formatBitsLevelM(int mask) {
    // ECC Level M = 00, mask = 3 bits
    const uint16_t data = static_cast<uint16_t>((0 << 3) | (mask & 7));
    uint16_t rem = static_cast<uint16_t>(data << 10);
    for (int i = 4; i >= 0; --i) {
        if (rem & (1u << (i + 10))) {
            rem ^= static_cast<uint16_t>(0x537u << i);
        }
    }
    return static_cast<uint16_t>(((data << 10) | rem) ^ 0x5412u);
}

void writeFormatBits(QrMatrix &m, int mask) {
    const uint16_t bits = formatBitsLevelM(mask);
    // Around top-left finder
    for (int i = 0; i <= 5; ++i) m.setFunc(8, i, ((bits >> i) & 1) != 0);
    m.setFunc(8, 7, ((bits >> 6) & 1) != 0);
    m.setFunc(8, 8, ((bits >> 7) & 1) != 0);
    m.setFunc(7, 8, ((bits >> 8) & 1) != 0);
    for (int i = 9; i < 15; ++i) m.setFunc(14 - i, 8, ((bits >> i) & 1) != 0);

    // Split between top-right and bottom-left finders
    for (int i = 0; i < 8; ++i) m.setFunc(m.size - 1 - i, 8, ((bits >> i) & 1) != 0);
    for (int i = 8; i < 15; ++i) m.setFunc(8, m.size - 15 + i, ((bits >> i) & 1) != 0);
    m.setFunc(8, m.size - 8, true); // Dark module
}

bool maskBit(int mask, int x, int y) {
    switch (mask) {
    case 0: return ((x + y) % 2) == 0;
    case 1: return (y % 2) == 0;
    case 2: return (x % 3) == 0;
    case 3: return ((x + y) % 3) == 0;
    case 4: return (((y / 2) + (x / 3)) % 2) == 0;
    case 5: return (((x * y) % 2) + ((x * y) % 3)) == 0;
    case 6: return ((((x * y) % 2) + ((x * y) % 3)) % 2) == 0;
    default: return ((((x + y) % 2) + ((x * y) % 3)) % 2) == 0;
    }
}

int penaltyScore(const QrMatrix &m) {
    int score = 0;
    const int n = m.size;
    // Rule 1: adjacent runs >= 5
    for (int y = 0; y < n; ++y) {
        int run = 1;
        for (int x = 1; x < n; ++x) {
            if (m.get(x, y) == m.get(x - 1, y)) {
                ++run;
                if (run == 5) score += 3;
                else if (run > 5) score += 1;
            } else {
                run = 1;
            }
        }
    }
    for (int x = 0; x < n; ++x) {
        int run = 1;
        for (int y = 1; y < n; ++y) {
            if (m.get(x, y) == m.get(x, y - 1)) {
                ++run;
                if (run == 5) score += 3;
                else if (run > 5) score += 1;
            } else {
                run = 1;
            }
        }
    }
    // Rule 2: 2x2 blocks
    for (int y = 0; y < n - 1; ++y) {
        for (int x = 0; x < n - 1; ++x) {
            const bool c = m.get(x, y);
            if (c == m.get(x + 1, y) && c == m.get(x, y + 1) && c == m.get(x + 1, y + 1)) {
                score += 3;
            }
        }
    }
    // Rule 4: dark/light balance
    int dark = 0;
    for (uint8_t v : m.modules) dark += v;
    const int total = n * n;
    const int k = std::abs(dark * 20 - total * 10) / total;
    score += k * 10;
    return score;
}

QrMatrix encodeQr(const QByteArray &payload) {
    const int len = payload.size();
    const QrVersionSpec *spec = nullptr;
    for (const auto &s : kSpecs) {
        // 4-bit mode + 8-bit length = 12 bits -> 2 bytes overhead
        if (len + 2 <= s.totalDataBytes) {
            spec = &s;
            break;
        }
    }
    if (!spec) {
        spec = &kSpecs.back();
    }

    const int maxBytes = std::min(len, spec->totalDataBytes - 2);
    std::vector<uint8_t> bits;
    auto pushBits = [&](uint32_t val, int count) {
        for (int i = count - 1; i >= 0; --i) {
            bits.push_back(static_cast<uint8_t>((val >> i) & 1u));
        }
    };

    pushBits(0b0100, 4); // Byte mode
    pushBits(static_cast<uint32_t>(maxBytes), 8);
    for (int i = 0; i < maxBytes; ++i) {
        pushBits(static_cast<uint8_t>(payload.at(i)), 8);
    }

    const int totalDataBits = spec->totalDataBytes * 8;
    const int term = std::min(4, totalDataBits - static_cast<int>(bits.size()));
    pushBits(0, term);
    while (bits.size() % 8 != 0) bits.push_back(0);

    std::vector<uint8_t> dataCodewords;
    dataCodewords.reserve(static_cast<size_t>(spec->totalDataBytes));
    for (size_t i = 0; i < bits.size(); i += 8) {
        uint8_t byte = 0;
        for (int b = 0; b < 8; ++b) byte = static_cast<uint8_t>((byte << 1) | bits[i + b]);
        dataCodewords.push_back(byte);
    }
    constexpr uint8_t kPads[2] = {0xEC, 0x11};
    int padIdx = 0;
    while (static_cast<int>(dataCodewords.size()) < spec->totalDataBytes) {
        dataCodewords.push_back(kPads[padIdx++ & 1]);
    }

    // Split into blocks & compute RS ECC
    const int blockDataLen = spec->totalDataBytes / spec->numBlocks;
    const std::vector<uint8_t> gen = rsGenerator(spec->ecBytesPerBlock);
    std::vector<std::vector<uint8_t>> dataBlocks;
    std::vector<std::vector<uint8_t>> ecBlocks;
    for (int b = 0; b < spec->numBlocks; ++b) {
        std::vector<uint8_t> blk(
            dataCodewords.begin() + b * blockDataLen,
            dataCodewords.begin() + (b + 1) * blockDataLen);
        ecBlocks.push_back(rsRemainder(blk, gen));
        dataBlocks.push_back(std::move(blk));
    }

    std::vector<uint8_t> finalCodewords;
    for (int i = 0; i < blockDataLen; ++i) {
        for (int b = 0; b < spec->numBlocks; ++b) finalCodewords.push_back(dataBlocks[b][i]);
    }
    for (int i = 0; i < spec->ecBytesPerBlock; ++i) {
        for (int b = 0; b < spec->numBlocks; ++b) finalCodewords.push_back(ecBlocks[b][i]);
    }

    QrMatrix base(spec->size);
    drawFinder(base, 3, 3);
    drawFinder(base, spec->size - 4, 3);
    drawFinder(base, 3, spec->size - 4);
    if (spec->alignPos > 0) {
        drawAlignment(base, spec->alignPos, spec->alignPos);
    }
    for (int i = 8; i < spec->size - 8; ++i) {
        base.setFunc(6, i, (i % 2) == 0);
        base.setFunc(i, 6, (i % 2) == 0);
    }
    writeFormatBits(base, 0); // Reserve format info areas

    // Zig-zag data placement
    size_t bitIndex = 0;
    const size_t totalFinalBits = finalCodewords.size() * 8;
    for (int right = spec->size - 1; right >= 1; right -= 2) {
        if (right == 6) right = 5;
        for (int vert = 0; vert < spec->size; ++vert) {
            const bool upward = (((right + 1) & 2) == 0);
            const int y = upward ? (spec->size - 1 - vert) : vert;
            for (int j = 0; j < 2; ++j) {
                const int x = right - j;
                if (!base.func(x, y)) {
                    bool dark = false;
                    if (bitIndex < totalFinalBits) {
                        const uint8_t cw = finalCodewords[bitIndex >> 3];
                        dark = ((cw >> (7 - (bitIndex & 7))) & 1u) != 0;
                        ++bitIndex;
                    }
                    base.setData(x, y, dark);
                }
            }
        }
    }

    int bestMask = 0;
    int bestPenalty = std::numeric_limits<int>::max();
    QrMatrix best(spec->size);
    for (int mask = 0; mask < 8; ++mask) {
        QrMatrix cand = base;
        for (int y = 0; y < spec->size; ++y) {
            for (int x = 0; x < spec->size; ++x) {
                if (!cand.func(x, y) && maskBit(mask, x, y)) {
                    cand.setData(x, y, !cand.get(x, y));
                }
            }
        }
        writeFormatBits(cand, mask);
        const int pen = penaltyScore(cand);
        if (pen < bestPenalty) {
            bestPenalty = pen;
            bestMask = mask;
            best = std::move(cand);
        }
    }
    Q_UNUSED(bestMask);
    return best;
}

} // namespace

QrImageProvider::QrImageProvider()
    : QQuickImageProvider(QQuickImageProvider::Image) {}

QImage QrImageProvider::renderQr(const QByteArray &payload, int targetPx) {
    if (payload.isEmpty()) {
        return {};
    }
    const QrMatrix qr = encodeQr(payload);
    constexpr int kQuiet = 4;
    const int totalModules = qr.size + kQuiet * 2;
    const int scale = std::max(4, targetPx / totalModules);
    const int imgSize = totalModules * scale;

    QImage img(imgSize, imgSize, QImage::Format_RGB32);
    img.fill(Qt::white);

    const QRgb black = qRgb(18, 18, 22);
    for (int y = 0; y < qr.size; ++y) {
        for (int x = 0; x < qr.size; ++x) {
            if (!qr.get(x, y)) continue;
            const int px0 = (x + kQuiet) * scale;
            const int py0 = (y + kQuiet) * scale;
            for (int dy = 0; dy < scale; ++dy) {
                auto *scan = reinterpret_cast<QRgb *>(img.scanLine(py0 + dy));
                std::fill(scan + px0, scan + px0 + scale, black);
            }
        }
    }
    return img;
}

QImage QrImageProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize) {
    const QString decoded = QUrl::fromPercentEncoding(id.toUtf8());
    const int target = requestedSize.isValid() && requestedSize.width() > 0
        ? std::clamp(requestedSize.width(), 128, 512)
        : 256;
    QImage img = renderQr(decoded.toUtf8(), target);
    if (size) {
        *size = img.size();
    }
    return img;
}

} // namespace ymusic
