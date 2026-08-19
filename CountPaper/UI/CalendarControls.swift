import Cocoa

final class DateRangeSelectionBinder: NSObject {
    let picker: NSDatePicker; let mode: NSSegmentedControl; let startLabel: NSTextField; let endLabel: NSTextField
    var startDate: Date; var endDate: Date
    private let formatter: DateFormatter

    init(picker: NSDatePicker, mode: NSSegmentedControl, startLabel: NSTextField, endLabel: NSTextField, startDate: Date, endDate: Date, formatter: DateFormatter) {
        self.picker = picker; self.mode = mode; self.startLabel = startLabel; self.endLabel = endLabel
        self.startDate = startDate; self.endDate = endDate; self.formatter = formatter
        super.init(); refreshLabels()
    }
    @objc func changeMode(_ sender: NSSegmentedControl) { picker.dateValue = sender.selectedSegment == 0 ? startDate : endDate; refreshLabels() }
    @objc func chooseDate(_ sender: NSDatePicker) {
        if mode.selectedSegment == 0 { startDate = sender.dateValue; if startDate > endDate { endDate = startDate } }
        else { endDate = sender.dateValue; if endDate < startDate { startDate = endDate } }
        refreshLabels()
    }
    private func refreshLabels() {
        startLabel.stringValue = formatter.string(from: startDate); endLabel.stringValue = formatter.string(from: endDate)
        startLabel.textColor = mode.selectedSegment == 0 ? CountPaperTheme.blue : CountPaperTheme.secondaryInk
        endLabel.textColor = mode.selectedSegment == 1 ? CountPaperTheme.blue : CountPaperTheme.secondaryInk
    }
}

final class SingleDateCalendarBinder: NSObject {
    let picker: NSDatePicker; let selectedDateLabel: NSTextField; let english: Bool
    init(picker: NSDatePicker, selectedDateLabel: NSTextField, english: Bool) {
        self.picker = picker; self.selectedDateLabel = selectedDateLabel; self.english = english
        super.init(); refreshLabel()
    }
    @objc func selectShortcut(_ sender: NSSegmentedControl) {
        picker.dateValue = sender.selectedSegment == 0 ? Date() : (Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()); refreshLabel()
    }
    @objc func chooseDate(_ sender: NSDatePicker) { refreshLabel() }
    private func refreshLabel() {
        let formatter = DateFormatter(); formatter.locale = english ? Locale(identifier: "en_US") : Locale(identifier: "zh_Hans_CN")
        formatter.setLocalizedDateFormatFromTemplate(english ? "EEEE, MMMMd" : "yMMMMdEEEE")
        selectedDateLabel.stringValue = formatter.string(from: picker.dateValue)
    }
}
