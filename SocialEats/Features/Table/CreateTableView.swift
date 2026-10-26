//
//  CreateTableView.swift
//  SocialEats
//
//  Table Creator form opened from the + button (Feature 9).
//

import SwiftUI

struct CreateTableView: View {
    @EnvironmentObject private var navigation: NavigationModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CreateTableViewModel

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: CreateTableViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Host a Community Table")
                    .font(AppFont.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("You'll take Seat #1. Guests near you get a notification as soon as it's live.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColors.textSecondary)

                basicsCard
                venueCard
                timeAndSeatsCard
                extrasCard

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error) { viewModel.errorMessage = nil }
                }

                LoadingButton(title: "Open My Table", systemImage: "fork.knife",
                              isLoading: viewModel.isSaving, isEnabled: viewModel.isValid) {
                    Task { await viewModel.createTable() }
                }
            }
            .padding(AppLayout.screenPadding)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("Table Creator")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.createdTableId) { _, newId in
            // Replace this form with the new table's detail screen
            guard let newId else { return }
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                navigation.open(.table(newId), on: navigation.selectedTab)
            }
        }
    }

    // MARK: - Cards

    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineText(text: "The basics")
            TextField("Table name, e.g. Taco Tuesday & Startup Chat", text: $viewModel.title)
                .inputFieldStyle()
                .accessibilityLabel("Table name")
            if let error = viewModel.titleError {
                Text(error).font(AppFont.caption).foregroundStyle(AppColors.danger)
            }
            TextField("What's the vibe? (optional)", text: $viewModel.about, axis: .vertical)
                .lineLimit(3...5)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.surfaceMuted))
                .accessibilityLabel("Description")

            Text("Category").font(AppFont.footnote).foregroundStyle(AppColors.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TableCategory.allCases) { category in
                        ChipView(title: category.title, icon: category.emoji,
                                 isSelected: viewModel.category == category) {
                            viewModel.category = category
                        }
                    }
                }
            }
        }
        .cardStyle()
    }

    private var venueCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            OverlineText(text: "Venue")
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(AppColors.textSecondary)
                TextField("Search restaurants & cafes", text: $viewModel.venueQuery)
                    .autocorrectionDisabled()
                if viewModel.isSearchingVenues {
                    ProgressView()
                } else if viewModel.selectedVenue != nil {
                    Button { viewModel.clearVenue() } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityLabel("Clear venue")
                }
            }
            .inputFieldStyle()

            if let venue = viewModel.selectedVenue {
                Label {
                    VStack(alignment: .leading) {
                        Text(venue.name).font(AppFont.subheadline.weight(.semibold))
                        Text(venue.address).font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.success)
                }
            }

            ForEach(viewModel.venueResults) { venue in
                Button {
                    viewModel.selectVenue(venue)
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(AppColors.primary)
                        VStack(alignment: .leading) {
                            Text(venue.name).font(AppFont.subheadline).foregroundStyle(AppColors.textPrimary)
                            Text(venue.address).font(AppFont.caption).foregroundStyle(AppColors.textSecondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }

            Button {
                viewModel.useCurrentLocationAsVenue()
            } label: {
                Label("Use my current location", systemImage: "location.fill")
            }
            .font(AppFont.footnote.weight(.semibold))
            .foregroundStyle(AppColors.primary)
            .frame(minHeight: AppLayout.minTapTarget)
        }
        .cardStyle()
    }

    private var timeAndSeatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            OverlineText(text: "When & how many")
            DatePicker("Meal time", selection: $viewModel.startTime,
                       in: Date()..., displayedComponents: [.date, .hourAndMinute])
                .font(AppFont.body)
            if let error = viewModel.timeError {
                Text(error).font(AppFont.caption).foregroundStyle(AppColors.danger)
            }
            Stepper(value: $viewModel.capacity, in: CreateTableViewModel.capacityRange) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total seats: \(viewModel.capacity)").font(AppFont.body)
                    Text(viewModel.seatsSummary).font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .cardStyle()
    }

    private var extrasCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            OverlineText(text: "Dietary tags")
            ChipGrid {
                ForEach(DietaryTag.allCases.filter { !$0.isAllergy }) { tag in
                    ChipView(title: tag.title, icon: tag.emoji, isSelected: viewModel.dietaryTags.contains(tag)) {
                        viewModel.toggle(tag)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Approx. cost per person: LKR \(Int(viewModel.pricePerPerson))")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                Slider(value: $viewModel.pricePerPerson, in: 500...10_000, step: 250)
                    .accessibilityValue("LKR \(Int(viewModel.pricePerPerson))")
            }
            TextField("Perk (optional), e.g. 20% Student Discount", text: $viewModel.perk)
                .inputFieldStyle()
        }
        .cardStyle()
    }
}
