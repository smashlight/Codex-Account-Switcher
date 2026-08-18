import AppKit
import SwiftUI

@main
struct AppKitInteractionTests {
    private static var failures: [String] = []
    private static var assertionCount = 0

    static func main() {
        testNativeTableMapsSelectionToExactAccount()
        testNativeTableOffersDeleteOnlyForInactiveAccount()
        testNativeTableMapsDeleteToExactAccount()
        testNativeTableProvidesFinalCellWidth()
        testAccountRowHostingViewFollowsTableWidth()
        testAccountRowHostingViewPreservesTableGestures()
        testAccountTableUsesCompactSpacing()
        testTenCompactRowsFitViewport()

        if failures.isEmpty {
            print("AppKit interaction tests passed (\(assertionCount) assertions).")
            return
        }
        for failure in failures {
            FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
        }
        exit(1)
    }

    private static func testAccountTableUsesCompactSpacing() {
        expect(makeTable().intercellSpacing.height == 4, "account table should use compact row spacing")
    }

    private static func testTenCompactRowsFitViewport() {
        let accounts = (0..<10).map {
            account(email: "account-\($0)@example.com", active: $0 == 0)
        }
        let viewportHeight: CGFloat = 426 + CGFloat(UsagePanelLayoutMetrics.accountListEdgeAllowance)
        let table = AccountListTableView(
            frame: NSRect(x: 0, y: 0, width: 480, height: viewportHeight),
            accounts: accounts,
            isInteractionEnabled: true,
            armedEmail: nil,
            deleteTitle: "Delete",
            rowSpacing: 4,
            rowHeightProvider: { _ in 39 },
            rowViewProvider: { _, frame in NSView(frame: frame) },
            onSelect: { _ in },
            onDelete: { _ in }
        )
        table.reloadData()
        table.layoutSubtreeIfNeeded()
        let finalCellFrame = table.frameOfCell(atColumn: 0, row: 9)
        expect(
            finalCellFrame.maxY <= viewportHeight,
            "the tenth compact account cell must fit fully (maxY \(finalCellFrame.maxY), viewport \(viewportHeight))"
        )
    }

    private static func testNativeTableMapsSelectionToExactAccount() {
        var selected = ""
        let table = makeTable(onSelect: { selected = $0.email })
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        table.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification, object: table))
        expect(selected == "second@example.com", "selecting row 1 must invoke the second account, not the first")
    }

    private static func testNativeTableOffersDeleteOnlyForInactiveAccount() {
        let table = makeTable()
        let activeActions = table.tableView(table, rowActionsForRow: 0, edge: .trailing)
        let inactiveActions = table.tableView(table, rowActionsForRow: 1, edge: .trailing)
        expect(activeActions.isEmpty, "the active account must not expose a delete swipe action")
        expect(inactiveActions.count == 1, "an inactive account must expose one native trailing delete action")
    }

    private static func testNativeTableMapsDeleteToExactAccount() {
        var deleted = ""
        let table = makeTable(onDelete: { deleted = $0.email })
        table.deleteAccount(at: 1)
        expect(deleted == "second@example.com", "deleting row 1 must remove exactly the second account")
        table.deleteAccount(at: 0)
        expect(deleted == "second@example.com", "requesting deletion of the active row must do nothing")
    }

    private static func testNativeTableProvidesFinalCellWidth() {
        var suppliedWidth: CGFloat = 0
        let table = makeTable(rowViewProvider: { account, frame in
            suppliedWidth = frame.width
            let view = NSView(frame: frame)
            view.identifier = NSUserInterfaceItemIdentifier(account.email)
            return view
        })
        table.tableColumns[0].width = 440
        table.reloadData()
        let cell = table.view(atColumn: 0, row: 1, makeIfNecessary: true)
        expect(cell != nil, "the native table must create the requested account cell")
        expect(
            suppliedWidth == cell?.frame.width,
            "row content must be laid out with the final AppKit cell width (supplied \(suppliedWidth), final \(cell?.frame.width ?? -1))"
        )
    }

    private static func testAccountRowHostingViewFollowsTableWidth() {
        let host = AccountRowHostingView(
            frame: NSRect(x: 0, y: 0, width: 492, height: 48),
            rootView: Color.clear,
            passesGesturesToTable: true
        )
        host.frame.size.width = 440
        host.layoutSubtreeIfNeeded()
        expect(host.frame.width == 440, "SwiftUI account content must follow the final table cell width")
        expect(host.sizingOptions.isEmpty, "SwiftUI account content must not impose intrinsic sizing on its table cell")
    }

    private static func testAccountRowHostingViewPreservesTableGestures() {
        let passiveHost = AccountRowHostingView(
            frame: NSRect(x: 0, y: 0, width: 440, height: 48),
            rootView: Color.clear,
            passesGesturesToTable: true
        )
        let interactiveHost = AccountRowHostingView(
            frame: NSRect(x: 0, y: 0, width: 440, height: 78),
            rootView: Color.clear,
            passesGesturesToTable: false
        )
        expect(passiveHost.hitTest(NSPoint(x: 10, y: 10)) == nil, "normal rows must leave click and swipe handling to NSTableView")
        expect(interactiveHost.hitTest(NSPoint(x: 10, y: 10)) != nil, "confirmation rows must deliver clicks to their SwiftUI buttons")
    }

    private static func makeTable(
        onSelect: @escaping (CodexAccount) -> Void = { _ in },
        onDelete: @escaping (CodexAccount) -> Void = { _ in },
        rowViewProvider: AccountListTableView.RowViewProvider? = nil
    ) -> AccountListTableView {
        AccountListTableView(
            frame: NSRect(x: 0, y: 0, width: 480, height: 102),
            accounts: [account(email: "first@example.com", active: true), account(email: "second@example.com", active: false)],
            isInteractionEnabled: true,
            armedEmail: nil,
            deleteTitle: "Delete",
            rowSpacing: 4,
            rowHeightProvider: { _ in 48 },
            rowViewProvider: rowViewProvider ?? { account, frame in
                let view = NSView(frame: frame)
                view.identifier = NSUserInterfaceItemIdentifier(account.email)
                return view
            },
            onSelect: onSelect,
            onDelete: onDelete
        )
    }

    private static func account(email: String, active: Bool) -> CodexAccount {
        CodexAccount(
            selector: active ? "01" : "02",
            email: email,
            plan: "plus",
            fiveHourUsage: "--",
            weeklyUsage: "50%",
            fiveHourUsedPercent: nil,
            weeklyUsedPercent: 50,
            lastActivity: "--",
            isActive: active
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        assertionCount += 1
        if !condition() {
            failures.append(message)
        }
    }
}
