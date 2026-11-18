import AppKit

public class HeaderCardView: NSView {
    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    public var stats: DiskStats {
        didSet {
            needsDisplay = true
        }
    }

    public override var isFlipped: Bool {
        return true
    }

    public init(stats: DiskStats) {
        self.stats = stats
        super.init(frame: NSRect(x: 0, y: 0, width: 296, height: 126))
        self.wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(stats: DiskStats) {
        self.stats = stats
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let padX: CGFloat = 16
        let totalW = bounds.width

        // 1. Sürücü İkonu & Başlık (Sağ rozetle çakışmayı önleyen sınırlı alan)
        let iconRect = NSRect(x: padX, y: 12, width: 18, height: 16)
        let symbolName = stats.volumePath == "/" ? "internaldrive.fill" : "externaldrive.fill"
        if let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            icon.isTemplate = true
            NSColor.labelColor.set()
            icon.draw(in: iconRect)
        }

        // Sağ Üst: Doluluk Oranı Rozeti
        let percentStr = NSString(string: "\(stats.percentUsedFormatted) Dolu")
        let badgeColor: NSColor
        if stats.isCriticalSpace {
            badgeColor = .systemRed
        } else if stats.isLowSpace {
            badgeColor = .systemOrange
        } else {
            badgeColor = .secondaryLabelColor
        }

        let badgeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: badgeColor
        ]
        let badgeSize = percentStr.size(withAttributes: badgeAttrs)
        let badgeX = totalW - padX - badgeSize.width
        percentStr.draw(at: NSPoint(x: badgeX, y: 13), withAttributes: badgeAttrs)

        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.lineBreakMode = .byTruncatingTail
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: titleParagraph
        ]
        let titleX = padX + 24
        let maxTitleW = max(60, badgeX - titleX - 8)
        let titleRect = NSRect(x: titleX, y: 11, width: maxTitleW, height: 18)
        NSString(string: stats.volumeName).draw(in: titleRect, withAttributes: titleAttrs)

        // 2. İlerleme Çubuğu (Progress Bar)
        let barY: CGFloat = 38
        let barH: CGFloat = 8
        let barW = totalW - (padX * 2)
        let barBgRect = NSRect(x: padX, y: barY, width: barW, height: barH)

        let bgPath = NSBezierPath(roundedRect: barBgRect, xRadius: 4, yRadius: 4)
        NSColor.separatorColor.withAlphaComponent(0.4).setFill()
        bgPath.fill()

        if stats.usedFraction > 0 {
            let fillW = max(barH, min(barW, barW * CGFloat(stats.usedFraction)))
            let barFillRect = NSRect(x: padX, y: barY, width: fillW, height: barH)
            let fillPath = NSBezierPath(roundedRect: barFillRect, xRadius: 4, yRadius: 4)

            if stats.isCriticalSpace {
                NSColor.systemRed.setFill()
            } else if stats.isLowSpace {
                NSColor.systemOrange.setFill()
            } else {
                NSColor.systemBlue.setFill()
            }
            fillPath.fill()
        }

        // 3. İstatistik Tablosu
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let valFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let col2X: CGFloat = 156

        let freeColor: NSColor
        if stats.isCriticalSpace {
            freeColor = .systemRed
        } else if stats.isLowSpace {
            freeColor = .systemOrange
        } else {
            freeColor = .systemGreen
        }

        // Satır 1: Boş Alan & Kullanılan
        let row1Y: CGFloat = 58
        drawStat(label: "Boş:", value: stats.freeFormatted, valueColor: freeColor, at: NSPoint(x: padX, y: row1Y), labelFont: labelFont, valFont: valFont)
        drawStat(label: "Dolu:", value: stats.usedFormatted, valueColor: .labelColor, at: NSPoint(x: col2X, y: row1Y), labelFont: labelFont, valFont: valFont)

        // Satır 2: Toplam & Boş Yüzde
        let row2Y: CGFloat = 78
        drawStat(label: "Toplam:", value: stats.totalFormatted, valueColor: .labelColor, at: NSPoint(x: padX, y: row2Y), labelFont: labelFont, valFont: valFont)
        drawStat(label: "Boşluk:", value: stats.percentFreeFormatted, valueColor: .secondaryLabelColor, at: NSPoint(x: col2X, y: row2Y), labelFont: labelFont, valFont: valFont)

        // Satır 3: APFS Temizlenebilir & Son Güncelleme Saati
        let row3Y: CGFloat = 98
        let purgeValue = stats.purgeableBytes > 0 ? stats.purgeableFormatted : "0 MB"
        drawStat(label: "Temizlenebilir:", value: purgeValue, valueColor: .secondaryLabelColor, at: NSPoint(x: padX, y: row3Y), labelFont: labelFont, valFont: valFont)
        let timeStr = HeaderCardView.timeFormatter.string(from: stats.timestamp)
        drawStat(label: "Saat:", value: timeStr, valueColor: .tertiaryLabelColor, at: NSPoint(x: col2X, y: row3Y), labelFont: labelFont, valFont: valFont)
    }

    private func drawStat(label: String, value: String, valueColor: NSColor, at point: NSPoint, labelFont: NSFont, valFont: NSFont) {
        let lblAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: valFont,
            .foregroundColor: valueColor
        ]

        let lblStr = NSString(string: label)
        lblStr.draw(at: point, withAttributes: lblAttrs)
        let lblSize = lblStr.size(withAttributes: lblAttrs)

        let valStr = NSString(string: " " + value)
        valStr.draw(at: NSPoint(x: point.x + lblSize.width, y: point.y), withAttributes: valAttrs)
    }
}
