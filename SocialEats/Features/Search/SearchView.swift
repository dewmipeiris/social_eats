//  SearchView.swift

import SwiftUI
import Combine

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query = ""
    @Published var category: TableCategory?
    @Published private(set) var results: [CommunityTable] = []
    @Published private(set) var recentSearches: [String] = []

    let speech = SpeechService()
    let chips: [TableCategory] = [.ramen, .pizza, .cafe, .sushi, .tacos]

    private let tablesStore: TablesStore
    private let location: LocationService
    private let defaults: UserDefaults
    private var cancellables = Set<AnyCancellable>()
    private static let recentKey = "search.recent"

    init(tablesStore: TablesStore, location: LocationService, defaults: UserDefaults = .standard) {
        self.tablesStore = tablesStore
        self.location = location
        self.defaults = defaults
        recentSearches = defaults.stringArray(forKey: Self.recentKey) ?? []

        speech.$transcript
            .filter { !$0.isEmpty }
            .sink { [weak self] text in self?.query = text }
            .store(in: &cancellables)

        Publishers.CombineLatest3($query.debounce(for: .milliseconds(250), scheduler: RunLoop.main),
                                  $category,
                                  tablesStore.$tables)
            .sink { [weak self] query, category, tables in
                self?.runSearch(query: query, category: category, tables: tables)
            }
            .store(in: &cancellables)

        speech.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    convenience init(container: AppContainer) {
        self.init(tablesStore: container.tablesStore, location: container.location)
    }

    var topPick: CommunityTable? { results.first }

    func distanceText(for table: CommunityTable) -> String {
        DistanceText.away(table.distance(from: location.currentLocation))
    }

    static func keywords(from query: String) -> String {
        let fillers: Set<String> = ["cozy", "spots", "spot", "nearby", "near", "me", "with", "open", "seats",
                                    "seat", "a", "the", "some", "find", "show", "places", "place", "good", "best", "for", "in"]
        return query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !fillers.contains($0) }
            .joined(separator: " ")
    }

    private func runSearch(query: String, category: TableCategory?, tables: [CommunityTable]) {
        let cleaned = Self.keywords(from: query)
        var options = TableFilterOptions()
        options.category = category ?? TableCategory.allCases.first { cleaned.contains($0.title.lowercased()) }
        options.searchText = options.category?.title.lowercased() == cleaned ? "" : cleaned
        options.hideFull = false
        results = TableFilter.apply(options, to: tables, userLocation: location.currentLocation)
    }

    func toggleVoice() async {
        if speech.isRecording {
            speech.stop()
        } else {
            await speech.start()
        }
    }

    func saveRecent() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        recentSearches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        recentSearches.insert(trimmed, at: 0)
        recentSearches = Array(recentSearches.prefix(6))
        defaults.set(recentSearches, forKey: Self.recentKey)
    }

    func removeRecent(_ text: String) {
        recentSearches.removeAll { $0 == text }
        defaults.set(recentSearches, forKey: Self.recentKey)
    }

    func clearRecent() {
        recentSearches = []
        defaults.removeObject(forKey: Self.recentKey)
    }
}

struct SearchView: View {
    @EnvironmentObject private var navigation: NavigationModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SearchViewModel
    @FocusState private var searchFocused: Bool

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                searchField

                if viewModel.speech.isRecording || !viewModel.speech.transcript.isEmpty {
                    voiceCard
                }

                if let error = viewModel.speech.errorMessage {
                    ErrorBanner(message: error) { viewModel.speech.errorMessage = nil }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ChipView(title: "All", isSelected: viewModel.category == nil) { viewModel.category = nil }
                        ForEach(viewModel.chips) { chip in
                            ChipView(title: chip.title, icon: chip.emoji, isSelected: viewModel.category == chip) {
                                viewModel.category = viewModel.category == chip ? nil : chip
                            }
                        }
                    }
                }

                if viewModel.query.isEmpty && !viewModel.recentSearches.isEmpty {
                    recentSection
                }

                if let pick = viewModel.topPick {
                    topPickCard(pick)
                }

                if viewModel.results.count > 1 {
                    SectionHeader(title: "More results")
                    ForEach(viewModel.results.dropFirst()) { table in
                        TableRowCard(table: table, distanceText: viewModel.distanceText(for: table))
                            .onTapGesture { open(table) }
                            .accessibilityAddTraits(.isButton)
                    }
                } else if viewModel.results.isEmpty {
                    EmptyStateView(systemImage: "magnifyingglass",
                                   title: "No tables found",
                                   message: "Try another dish or say it with the mic.")
                }
            }
            .padding(AppLayout.screenPadding)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("Search & Voice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { searchFocused = true }
        .onDisappear { viewModel.speech.stop() }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(AppColors.textSecondary)
                TextField("Search pizza, sushi, cafes...", text: $viewModel.query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit { viewModel.saveRecent() }
                Button {
                    Task { await viewModel.toggleVoice() }
                } label: {
                    Image(systemName: viewModel.speech.isRecording ? "stop.circle.fill" : "mic.fill")
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(viewModel.speech.isRecording ? "Stop voice search" : "Start voice search")
            }
            .inputFieldStyle()
            Button("Cancel") { dismiss() }
                .foregroundStyle(AppColors.primary)
        }
    }

    private var voiceCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .foregroundStyle(AppColors.primary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(AppColors.primarySoft))
                .symbolEffect(.variableColor.iterative, isActive: viewModel.speech.isRecording)
            VStack(alignment: .leading, spacing: 2) {
                OverlineText(text: viewModel.speech.isRecording ? "Listening…" : "Voice query")
                Text(viewModel.speech.transcript.isEmpty ? "Say something like \"cozy ramen spots nearby\"" : "\"\(viewModel.speech.transcript)\"")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent Searches").font(AppFont.subheadline).foregroundStyle(AppColors.textSecondary)
                Spacer()
                Button("Clear") { viewModel.clearRecent() }
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
            }
            VStack(spacing: 0) {
                ForEach(viewModel.recentSearches, id: \.self) { text in
                    HStack {
                        Button {
                            viewModel.query = text
                        } label: {
                            Label(text, systemImage: "clock.arrow.circlepath")
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Button {
                            viewModel.removeRecent(text)
                        } label: {
                            Image(systemName: "xmark").foregroundStyle(AppColors.textSecondary).frame(width: 36, height: 36)
                        }
                        .accessibilityLabel("Remove \(text)")
                    }
                    .padding(.horizontal, 12)
                    if text != viewModel.recentSearches.last { Divider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(AppColors.surface))
        }
    }

    private func topPickCard(_ table: CommunityTable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top Community Pick").font(AppFont.subheadline).foregroundStyle(AppColors.textSecondary)
                Spacer()
                BadgeView(text: "Best Match")
            }
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    FoodPhoto(category: table.category, emojiSize: 80)
                        .frame(height: 150)
                        .clipped()
                    Label(String(format: "%.1f", table.hostRating), systemImage: "star.fill")
                        .font(AppFont.caption.weight(.bold))
                        .foregroundStyle(AppColors.amber)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(AppColors.surface))
                        .padding(10)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(table.venueName).font(AppFont.title)
                        Spacer()
                        BadgeView(text: "Open Now")
                    }
                    HStack(spacing: 4) {
                        Text("\(table.seatsFilled) diners at table •").foregroundStyle(AppColors.textSecondary)
                        Text(table.isFull ? "Full" : "\(table.seatsLeft) seat\(table.seatsLeft == 1 ? "" : "s") left")
                            .foregroundStyle(AppColors.success)
                    }
                    .font(AppFont.subheadline)
                    HStack {
                        AvatarStack(names: table.attendeeNames, size: 26)
                        Spacer()
                        Text("View Table →").font(AppFont.subheadline.weight(.semibold)).foregroundStyle(AppColors.primary)
                    }
                }
                .padding(14)
            }
            .background(RoundedRectangle(cornerRadius: AppLayout.cardRadius).fill(AppColors.surface))
            .clipShape(RoundedRectangle(cornerRadius: AppLayout.cardRadius))
            .onTapGesture { open(table) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
    }

    private func open(_ table: CommunityTable) {
        viewModel.saveRecent()
        navigation.open(.table(table.id), on: navigation.selectedTab)
    }
}
