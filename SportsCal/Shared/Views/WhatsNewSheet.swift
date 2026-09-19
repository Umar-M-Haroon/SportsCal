//
//  WhatsNewSheet.swift
//  SportsCal
//
//  Post-update "What's New" sheet. Content and CTAs live in `WhatsNew.swift`.
//

import SwiftUI
import SportsCalModel

struct WhatsNewSheet: View {
    let release: WhatsNewRelease

    @Environment(UserDefaultStorage.self) private var storage
    @Environment(GameViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showSportPicker = false
    @State private var lastApplied: WhatsNewAction?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    ForEach(release.features) { feature in
                        featureRow(feature)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 16)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: 480)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(.bar)
            }
            .sensoryFeedback(.success, trigger: lastApplied)
            .sheet(isPresented: $showSportPicker) {
                SportPickerSheet()
                    .environment(storage)
                    .environment(viewModel)
            }
        }
        .frame(minWidth: 400, minHeight: 500)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What's New")
                .font(.largeTitle.bold())
            Text("Scoreline \(release.version)")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func featureRow(_ feature: WhatsNewFeature) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: feature.systemImage)
                .font(.title)
                .foregroundStyle(feature.tint)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = feature.action {
                    actionButton(action, tint: feature.tint)
                        .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButton(_ action: WhatsNewAction, tint: Color) -> some View {
        if action.isSatisfied(in: storage) {
            Label(action.doneTitle, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.vertical, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else {
            Button {
                perform(action)
            } label: {
                Text(action.title)
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(tint)
            .transition(.opacity)
        }
    }

    private func perform(_ action: WhatsNewAction) {
        MonetizationTelemetry.whatsNewAction(action.telemetryName, version: release.version)
        if case .manageSports = action {
            showSportPicker = true
            return
        }
        withAnimation(.snappy) {
            action.apply(storage: storage, viewModel: viewModel)
        }
        lastApplied = action
    }
}

#Preview {
    @Previewable @State var storage = UserDefaultStorage()
    @Previewable @State var viewModel = GameViewModel(appStorage: UserDefaultStorage(), favorites: Favorites())

    Color.clear
        .sheet(isPresented: .constant(true)) {
            WhatsNewSheet(release: WhatsNewRelease.all[0])
                .environment(storage)
                .environment(viewModel)
        }
}
