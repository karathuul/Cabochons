// MARK: - GuideView
// Renders the copy in Guide.swift. Four pieces:
//
//   GuideSheet      – what Settings presents. Matches DataSheet's shape:
//                     a NavigationStack with a Done button.
//   GuideView       – the list itself. Rows expand in place rather than
//                     pushing a detail view, so it reads as one page.
//   GuideTopicCard  – one topic, standalone. Shared with the ⓘ sheet so the
//                     two surfaces can't drift apart.
//   GuideExampleList – worked examples as "trigger ↳ action" pairs. Used by
//                     both the expanded row and the card.
//   GuideInfoButton – a small ⓘ presenting a single topic. This is the
//                     layer-two primitive; nothing calls it yet.
//
// Holds no reference to LogStore on purpose. The Guide is static content and
// has no business touching the data layer.
//
// TARGET MEMBERSHIP: app target only.

internal import SwiftUI

// MARK: - Sheet

struct GuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GuideView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - The list

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
        .scrollContentBackground(.hidden)
        .background(Chrome.panel)
        .navigationTitle("Guide")
        #if os(iOS)
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

    private var hasDetail: Bool { topic.hasMore }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: topic.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(Chrome.steelHi)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(topic.title)
                        .font(.system(.body, design: .rounded, weight: .medium))

                    Text(topic.blurb)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                if hasDetail {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    if let detail = topic.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !topic.examples.isEmpty {
                        GuideExampleList(examples: topic.examples)
                    }
                }
                .padding(.leading, 38)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 3)
        // Without this the row only answers taps on the glyphs themselves.
        .contentShape(Rectangle())
        .onTapGesture { if hasDetail { toggle() } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(hasDetail ? .isButton : [])
        .accessibilityHint(hasDetail ? (isExpanded ? "Collapse" : "Expand") : "")
    }
}

// MARK: - Standalone card, shared with the ⓘ sheet

struct GuideTopicCard: View {
    let topic: GuideTopic

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: topic.symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(Chrome.steelHi)

                Text(topic.title)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
            }

            Text(topic.blurb)
                .font(.system(.body, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            if let detail = topic.detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !topic.examples.isEmpty {
                GuideExampleList(examples: topic.examples)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Worked examples

struct GuideExampleList: View {
    let examples: [GuideExample]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(examples, id: \.self) { example in
                VStack(alignment: .leading, spacing: 2) {
                    Text(example.trigger)
                        .font(.system(.caption, design: .rounded, weight: .semibold))

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Chrome.steelHi)
                        Text(example.action)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                // "When you Sunday, 8 PM" was the first draft. Keep it dumb.
                .accessibilityLabel("\(example.trigger), then \(example.action)")
            }
        }
    }
}

// MARK: - Inline ⓘ — layer two, not yet wired to any call site

struct GuideInfoButton: View {
    let id: GuideTopicID
    @State private var isPresented = false

    init(_ id: GuideTopicID) { self.id = id }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
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
                .scrollContentBackground(.hidden)
                .background(Chrome.panel)
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
    GuideSheet()
}

#Preview("Single topic") {
    GuideTopicCard(topic: GuideContent.topic(.glint))
        .padding()
}
