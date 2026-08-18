import AppKit

@main
struct AppKitInteractionTests {
    private static var failures: [String] = []
    private static var assertionCount = 0

    static func main() {
        testNativeTableMapsSelectionToExactAccount()
        testNativeTableOffersDeleteOnlyForInactiveAccount()
        testNativeTableMapsDeleteToExactAccount()
        testNativeTableProvidesFinalCellWidth()

        if failures.isEmpty {
            print("AppKit interaction tests passed (\(assertionCount) assertions).")
            return
        }
        for failure in failures {
            FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
        }
        exit(1)
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
