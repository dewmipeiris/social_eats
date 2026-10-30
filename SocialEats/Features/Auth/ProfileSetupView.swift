//
//  ProfileSetupView.swift
//  SocialEats
//
//  Prototype Figure 3 — "What's Your Dining Vibe?" (Taste Profile, Step 1 of 2)
//  Used twice:
//   • .onboarding -> before sign-in, choices are kept as a draft
//   • .edit       -> from Profile, choices are saved to Firestore straight away
//

import SwiftUI

@MainActor
final class ProfileSetupViewModel: ObservableObject {
    @Published var ambiences: Set<Ambience>
    @Published var cuisines: Set<Cuisine>
    @Published var diningStyle: DiningStyle

    init(draft: TasteProfileDraft) {
        ambiences = Set(draft.ambiences)
        cuisines = Set(draft.cuisines)
        diningStyle = draft.diningStyle
    }

    func toggle(_ ambience: Ambience) {
        if ambiences.contains(ambience) { ambiences.remove(ambience) } else { ambiences.insert(ambience) }
    }

    func toggle(_ cuisine: Cuisine) {
        if cuisines.contains(cuisine) { cuisines.remove(cuisine) } else { cuisines.insert(cuisine) }
    }

    /// Fake-but-friendly "34 foodie tables matching your taste" count,
    /// based on how many live tables match the chosen cuisines.
    func matchingCount(in tables: [CommunityTable]) -> Int {
        guard !cuisines.isEmpty else { return tables.count }
        let categories = Set(cuisines.flatMap(\.matchingCategories))
        return tables.filter { categories.contains($0.category) }.count
    }

    /// Keeps the order the options appear in on screen.
    func makeDraft(dietary: [DietaryTag]) -> TasteProfileDraft {
        TasteProfileDraft(
            ambiences: Ambience.allCases.filter { ambiences.contains($0) },
            cuisines: Cuisine.allCases.filter { cuisines.contains($0) },
            diningStyle: diningStyle,
            dietaryTags: dietary
        )
    }
}

struct ProfileSetupView: View {
    enum Mode { case onboarding, edit }
    let mode: Mode

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var tablesStore: TablesStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ProfileSetupViewModel
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(mode: Mode, draft: TasteProfileDraft = TasteProfileDraft()) {
        self.mode = mode
        _viewModel = StateObject(wrappedValue: ProfileSetupViewModel(draft: draft))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: < [logo] Taste Profile Setup   (Step 1 of 2)
            HStack(spacing: 0) {

                if mode == .edit {
                    SidebarToggleButton()
                }
                AppHeader(title: "Taste Profile Setup",
                          showsBack: true,
                          onBack: {
                              if mode == .onboarding { session.showOnboarding() } else { dismiss() }
                          })
                if mode == .onboarding {
                    Text("Step 1 of 2")
                        .font(AppFont.caption)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .overlay(Capsule().stroke(AppColors.primary, lineWidth: 1))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.trailing, AppLayout.screenPadding)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if mode == .onboarding {
                        HStack {
                            BadgeView(text: "Step 1 of 2", foreground: AppColors.primary,
                                      background: AppColors.primarySoft, showsDot: true)
                            Spacer()
                            ProgressView(value: 0.5)
                                .tint(AppColors.primary)
                                .frame(width: 70)
                                .accessibilityLabel("Setup progress, step 1 of 2")
                        }
                    }

                    Text("What's Your Dining Vibe?")
                        .font(AppFont.largeTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Select your favorite dining vibes and cuisines so we can seat you at the best local tables.")
                        .font(AppFont.subheadline)
                        .foregroundStyle(AppColors.textSecondary)

                    ambienceCard
                    cuisineCard
                    diningStyleCard
                    matchingCard

                    if let errorMessage {
                        ErrorBanner(message: errorMessage) { self.errorMessage = nil }
                    }
                }
                .padding(AppLayout.screenPadding)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }

            // Bottom button
            VStack(spacing: 8) {
                LoadingButton(title: mode == .onboarding ? "Continue to Table Discovery" : "Save Taste Profile",
                              systemImage: "arrow.right",
                              isLoading: isSaving) {
                    Task { await continueTapped() }
                }
                Text("You can change these dietary & taste tags anytime in Settings.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(AppLayout.screenPadding)
            .frame(maxWidth: 640)
            .background(AppColors.background)
        }
        .screenBackground()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Cards

    private var ambienceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Dining Ambience", systemImage: "face.smiling")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                OverlineText(text: "Multi-select")
            }
            Text("Pick how you prefer your restaurant atmospheres to feel.")
                .font(AppFont.footnote)
                .foregroundStyle(AppColors.textSecondary)
            ChipGrid {
                ForEach(Ambience.allCases) { ambience in
                    ChipView(title: ambience.title, icon: ambience.emoji,
                             isSelected: viewModel.ambiences.contains(ambience)) {
                        Haptics.selection()
                        viewModel.toggle(ambience)
                    }
                }
            }
        }
        .cardStyle()
    }

    private var cuisineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Favorite Cuisines", systemImage: "fork.knife")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                OverlineText(text: "Quick picks", color: AppColors.amber)
            }
            ForEach(Cuisine.allCases) { cuisine in
                let isOn = viewModel.cuisines.contains(cuisine)
                Button {
                    Haptics.selection()
                    viewModel.toggle(cuisine)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: cuisine.systemImage)
                            .frame(width: 28)
                            .foregroundStyle(AppColors.textPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cuisine.title)
                                .font(AppFont.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(cuisine.subtitle)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle.fill")
                            .font(.title3)
                            .foregroundStyle(isOn ? AppColors.primary : AppColors.border)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isOn ? AppColors.primarySoft.opacity(0.5) : AppColors.surfaceMuted.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isOn ? AppColors.primary : AppColors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : [.isButton])
            }
        }
        .cardStyle()
    }

    private var diningStyleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Dining Style", systemImage: "person.3")
                .font(AppFont.headline)
                .foregroundStyle(AppColors.textPrimary)
            Text("Helps us curate table sizes and communal reservations.")
                .font(AppFont.footnote)
                .foregroundStyle(AppColors.textSecondary)

            // Custom segmented control (coral selected segment like the design)
            HStack(spacing: 4) {
                ForEach(DiningStyle.allCases) { style in
                    let isOn = viewModel.diningStyle == style
                    Button {
                        Haptics.selection()
                        viewModel.diningStyle = style
                    } label: {
                        Text(style.title)
                            .font(AppFont.footnote.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(isOn ? AppColors.onPrimary : AppColors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 10).fill(isOn ? AppColors.primary : Color.clear))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : [.isButton])
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.surfaceMuted))
        }
        .cardStyle()
    }

    private var matchingCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(AppColors.amber)
                .frame(width: 40, height: 40)
                .background(Circle().fill(AppColors.amberSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text("Curating Live Seatings")
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("\(viewModel.matchingCount(in: tablesStore.tables)) foodie tables matching your selected taste profile nearby.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(AppColors.amberSoft.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.amber.opacity(0.3), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Actions

    private func continueTapped() async {
        let draft = viewModel.makeDraft(dietary: settings.dietaryTags)
        switch mode {
        case .onboarding:
            session.completeTasteProfile(draft)
        case .edit:
            guard var user = session.currentUser else { return }
            user.ambiences = draft.ambiences
            user.cuisines = draft.cuisines
            user.diningStyle = draft.diningStyle
            isSaving = true
            do {
                try await session.updateProfile(user)
                Haptics.success()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

