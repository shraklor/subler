//
//  ItemViewController.swift
//  Subler
//
//  Created by Damiano Galassi on 11/11/2017.
//

import Cocoa

@objc(SBItemViewDelegate) protocol ItemViewDelegate: AnyObject {
    @objc(editItem:) func edit(item: SBQueueItem)
}

@objc(SBItemViewController) class ItemViewController : NSViewController {

    @objc let item: SBQueueItem

    var delegate: ItemViewDelegate

    var statusObserver: NSKeyValueObservation?
    var actionsObserver: NSKeyValueObservation?

    @IBOutlet var editButton: NSButton!
    @IBOutlet var spinner: NSProgressIndicator!
    @IBOutlet var tableHeight: NSLayoutConstraint!

    override var nibName: NSNib.Name? {
        return NSNib.Name(rawValue: "QueueItem")
    }

    @objc init(item: SBQueueItem, delegate: ItemViewDelegate) {
        self.item = item
        self.delegate = delegate
        super.init(nibName: self.nibName, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        super.loadView()

        // Observe the item status
        statusObserver = self.observe(\.item.status, options: [.initial, .new]) { [weak self] observed, change in
            guard let s = self, let status = change.newValue else { return }
            DispatchQueue.main.async {
                if status != SBQueueItemStatus.ready && status != SBQueueItemStatus.editing {
                    s.editButton.isEnabled = false
                } else {
                    s.editButton.isEnabled = true
                }
            }
        }

        // Observe the item actions
        actionsObserver = self.observe(\.item.actions, options: [.initial, .new]) { [weak self] observed, change in
            guard let s = self, let newCount = change.newValue?.count, let oldCount = change.oldValue?.count else { return }
            let count = newCount - oldCount
            let height = 16.0 * CGFloat(count >= 0 ? count : 1)
            s.tableHeight.constant = height
        }
    }

    @IBAction func edit(_ sender: Any) {
        spinner.isHidden = false
        delegate.edit(item: item)
    }
}