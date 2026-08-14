# CountPaper

English · [简体中文](README.zh-CN.md)

CountPaper is a local-first, plain-text personal ledger for macOS. Your `.countpaper` file is the source of truth. The app records transactions, checks format and balance, and turns the same file into useful views and reports.

<img src="CountPaper/Assets/CountPaperIcon-v2.png" alt="CountPaper icon" width="72">

> **Current release:** [CountPaper 0.12.0](https://github.com/clancygo/CountPaper/releases/tag/v0.12.0). The project is still under active development and testing. Keep ordinary backups or cloud-provider version history for important ledger files.

## Download

Download [CountPaper-0.12.0.dmg](https://github.com/clancygo/CountPaper/releases/download/v0.12.0/CountPaper-0.12.0.dmg), open it, then drag CountPaper to Applications.

The current release is a locally signed development build and is not notarized yet. macOS may show a security notice the first time it is opened.

## Why CountPaper

- **Your file stays yours.** No private accounting database, account system, or built-in cloud service.
- **Plain text, not lock-in.** Read or edit the same file with any text editor. CountPaper detects external saves.
- **Record first.** The home screen keeps the month's totals, quick entry, and recent transactions together.
- **Simple on screen, balanced in the file.** The interface shows categories, payment accounts, and amounts. Balanced postings remain transparent in the source text.
- **Useful checks and views.** Journal, reconciliation, account balances, balance checks, trends, categories, and tag reports are calculated from the active file.

## Highlights in 0.12.0

- Account creation, renaming, deletion protection, and opening-balance or balance-adjustment entries.
- A compact, sortable reconciliation view that shows the balance after every transaction.
- A redesigned date picker with clear selected-date, Today, Yesterday, and native calendar controls.
- A clearer macOS workspace: grouped navigation, visible ledger context, and a wider record-first layout.

## A ledger file

```text
---
format: countpaper/0.2
currency: USD
---

@accounts
- Assets:Cash
- Assets:Bank
- Equity:BalanceAdjustment
- Income:Salary
- Expenses:Dining

# 2026-08-12
- Lunch
  - time: 12:35
  - Expenses:Dining  12.50
  - Assets:Cash  -12.50
```

See the complete [CountPaper plain-text format 0.2](CountPaper/FORMAT-0.2.md).

## Requirements

- Apple-silicon Mac (M-series, `arm64`)
- macOS Sonoma 14.0 or later
- No network connection is required for ordinary use. iCloud Drive, Dropbox, Nutstore, and other file providers handle any sync you choose.

Intel Macs are not currently in the supported build and test matrix.

## Development

CountPaper is written in native Swift and AppKit. To build and verify locally:

```sh
zsh CountPaper/verify.sh
```

To create a versioned DMG:

```sh
zsh CountPaper/build-dmg.sh
```

The repository currently has no open-source license. All rights are reserved unless explicitly granted otherwise.
