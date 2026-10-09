import SwiftUI
import MorrowCore

/// Shared menu geometry keeps every service equally compact.
enum MenuLayout {
    static let width: CGFloat = 300
    static let horizontalInset: CGFloat = 12
    static let headerHeight: CGFloat = 36
    static let footerHeight: CGFloat = 32
    static let rowHeight: CGFloat = 46
    static let iconSize: CGFloat = 24
    static let actionSize: CGFloat = 24
    static let rowSpacing: CGFloat = 8
    static let actionSpacing: CGFloat = 2
    static let separatorHeight: CGFloat = 0.5
    static let emptyHeight: CGFloat = 124
    static let visibleRows = 6

    static func listHeight(_ count: Int) -> CGFloat {
        let rows = min(count, visibleRows)
        return CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) * separatorHeight
    }
    static func height(_ count: Int) -> CGFloat {
        headerHeight + (count == 0 ? emptyHeight : listHeight(count)) + separatorHeight + footerHeight
    }
}

struct MenuServiceRow<Actions: View>: View {
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let status: InstanceStatus
    @ViewBuilder var actions: Actions
    var body: some View {
        HStack(spacing: MenuLayout.rowSpacing) {
            IconTile(symbol: symbol, color: color, size: MenuLayout.iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ServiceStatusView(status: status, compact: true)
            HStack(spacing: MenuLayout.actionSpacing) { actions }
        }
        .padding(.horizontal, MenuLayout.horizontalInset)
        .frame(height: MenuLayout.rowHeight)
    }
}
