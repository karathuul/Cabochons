//
//  GuideView.swift
//
//  MARK: - Overview
//  Renders the copy in Guide.swift. Three pieces:
//
//    GuideView       – the full browsable Guide screen. Rows expand in place
//                      rather than pushing a detail view, so the whole thing
//                      reads as one page on both platforms.
//    GuideTopicCard  – one topic, standalone. Reused by the ⓘ sheet so the
//                      two surfaces can never drift apart.
//    GuideInfoButton – a small ⓘ that presents a single topic as a sheet.
//                      This is the layer-2 primitive; nothing calls it yet.
//
//  Deliberately holds no reference to LogStore. The Guide is static content
//  and has no business touching the data layer.
//
//  TARGET MEMBERSHIP: app target only.
//

internal import SwiftUI

// MARK: - Guide screen

struct GuideView: View {
    @State private var expanded: Set<GuideTopicID> = []

    var body: some View {
        List {
            ForEach(GuideContent.sections) { section in
                Section(section.title) {
                    ForEach(section.topics) { id in
                        GuideRow(
                            topic: GuideContent.topic(id),
                            isExpanded: expanded.contains(id),
                            toggle: { toggle(id) }
                        )
                    }
                }
            }
        }
        .navigationTitle("Guide")
        #if os(iOS)
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func toggle(_ id: GuideTopicID) {
        withAnimation(.snappy(duration: 0.22)) {
            if expanded.contains(id) {
                expanded.remove(id)
            } else {
                expanded.insert(id)
            }
        }
    }
}

// MARK: - Row

private struct GuideRow: View {
    let topic: GuideTopic
    let isExpanded: Bool
    let toggle: () -> Void

    private var hasDetail: Bool { topic.detail != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: topic.symbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .center)

                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title)
                        .font(.headline)
                    Text(topic.blurb)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if hasDetail {
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .accessibilityHidden(true)
                }
            }

            if isExpanded, let detail = topic.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 34)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { if hasDetail { toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(hasDetail ? .isButton : [])
        .accessibilityHint(hasDetail ? (isExpanded ? "Collapse" : "Expand") : "")
    }
}

// MARK: - Standalone card (shared with the ⓘ sheet)

struct GuideTopicCard: View {
    let topic: GuideTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: topic.symbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(topic.title)
                    .font(.title3.weight(.semibold))
            }

            Text(topic.blurb)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = topic.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Inline ⓘ button (layer 2 — not yet wired to any call site)

struct GuideInfoButton: View {
    let id: GuideTopicID
    @State private var isPresented = false

    init(_ id: GuideTopicID) { self.id = id }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About \(GuideContent.topic(id).title)")
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                ScrollView {
                    GuideTopicCard(topic: GuideContent.topic(id))
                        .padding(20)
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isPresented = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Previews

#Preview("Guide") {
    NavigationStack { GuideView() }
}

#Preview("Single topic") {
    GuideTopicCard(topic: GuideContent.topic(.glint))
        .padding()
}
