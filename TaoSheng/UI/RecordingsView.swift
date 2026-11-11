import SwiftUI
import UIKit

struct RecordingsView: View {
    @EnvironmentObject var app: AppState

    @State private var query = ""
    @State private var results: [Segment] = []
    @State private var selectedDay: String?
    @State private var daySegments: [Segment] = []
    @State private var showExport = false
    @State private var exportText = ""

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    dayList
                } else {
                    searchList
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("记录")
            .searchable(text: $query, prompt: "搜原话，比如「报告」「周三」")
            .onChange(of: query) { newValue in
                results = newValue.isEmpty ? [] : Store.shared.search(newValue)
            }
            .sheet(item: Binding<DayBox?>(
                get: { selectedDay.map { DayBox(day: $0) } },
                set: { if $0 == nil { selectedDay = nil } }
            )) { box in
                dayDetail(day: box.day)
            }
        }
    }

    private var dayList: some View {
        List {
            ForEach(app.days, id: \.self) { day in
                Button {
                    selectedDay = day
                    daySegments = Store.shared.segments(day: day, limit: 800).sorted { $0.startedAt < $1.startedAt }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(DayKey.display(day))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.text)
                            let segs = Store.shared.segments(day: day, limit: 300)
                            let total = segs.reduce(0) { $0 + $1.duration }
                            Text("\(segs.count) 段 · \(Int(total / 60)) 分钟人声")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.dim.opacity(0.6))
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private var searchList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if results.isEmpty {
                    EmptyHint(symbol: "magnifyingglass",
                              title: "没找到",
                              detail: "换个词试试，或者去「今天」看看正在录的内容。")
                } else {
                    ForEach(results) { seg in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(DayKey.display(seg.day)) \(seg.timeText)")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                            Text(seg.transcript)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.text)
                                .lineSpacing(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                        Divider().overlay(Theme.line)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func dayDetail(day: String) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(daySegments) { seg in
                        SegmentRow(segment: seg)
                        if seg.id != daySegments.last?.id { Divider().overlay(Theme.line) }
                    }
                }
                .card(padding: 12)
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(DayKey.display(day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        exportText = app.exportMarkdown(day: day)
                        showExport = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .tint(Theme.accent)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { selectedDay = nil }
                        .tint(Theme.dim)
                }
            }
            .sheet(isPresented: $showExport) {
                ShareSheet(text: exportText)
            }
        }
    }
}

struct DayBox: Identifiable {
    let day: String
    var id: String { day }
}

struct ShareSheet: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
