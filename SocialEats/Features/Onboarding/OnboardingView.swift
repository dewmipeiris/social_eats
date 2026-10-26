//
//  OnboardingView.swift
//  SocialEats
//
//  Prototype Figure 1 — 3-card onboarding carousel
//  ("Never Eat Alone Again" + Get Started / Sign In / Skip).
//

import SwiftUI
import UIKit

/// One page of the carousel.
struct OnboardingPage: Identifiable {
    let id: Int
    let title: String
    let message: String
    let emojis: (String, String)
    let badges: [OnboardingBadge]
}

/// Small chip under each onboarding page ("🪑 85+ Host Cafes").
struct OnboardingBadge: Hashable {
    let icon: String
    let text: String
}

/// Holds which page is showing. Tiny, but keeps logic out of the View.
@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var currentPage = 0

    let pages: [OnboardingPage] = [
        OnboardingPage(id: 0, title: "Never Eat Alone Again",
                       message: "Join open community tables at local cafes, meet new friends, and share great meals.",
                       emojis: ("🧑🏽", "👩🏻"),
                       badges: [OnboardingBadge(icon: "🪑", text: "85+ Host Cafes"), OnboardingBadge(icon: "✅", text: "Verified Foodies")]),
        OnboardingPage(id: 1, title: "Host Your Own Table",
                       message: "Pick a venue, a time and how many seats. We'll fill your table with people who love the same food.",
                       emojis: ("🍕", "🍜"),
                       badges: [OnboardingBadge(icon: "👑", text: "Become a SuperHost"), OnboardingBadge(icon: "⭐️", text: "Earn Karma")]),
        OnboardingPage(id: 2, title: "Safe, Verified Meetups",
                       message: "Face ID locks your seat, your pass works offline, and receipt scans prove every meal really happened.",
                       emojis: ("🔒", "🧾"),
                       badges: [OnboardingBadge(icon: "📱", text: "Face ID"), OnboardingBadge(icon: "📶", text: "Works Offline")])
    ]

    var isLastPage: Bool { currentPage == pages.count - 1 }

    func next() {
        if !isLastPage { currentPage += 1 }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel = OnboardingViewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 20) {
            // Top row: "● COMMUNITY PREVIEW"   Skip
            HStack {
                BadgeView(text: "COMMUNITY PREVIEW", foreground: AppColors.textSecondary,
                          background: AppColors.surfaceMuted, showsDot: true)
                Spacer()
                Button("Skip") { session.browseAsGuest() }
                    .font(AppFont.headline)
                    .foregroundStyle(AppColors.primary)
                    .frame(minWidth: AppLayout.minTapTarget, minHeight: AppLayout.minTapTarget)
                    .accessibilityHint("Browse tables as a guest without an account")
            }

            // Swipeable cards
            TabView(selection: $viewModel.currentPage) {
                ForEach(viewModel.pages) { page in
                    OnboardingPageView(page: page)
                        .tag(page.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom page dots (the active one is a wide pill)
            HStack(spacing: 6) {
                ForEach(viewModel.pages) { page in
                    Capsule()
                        .fill(page.id == viewModel.currentPage ? AppColors.primary : AppColors.border)
                        .frame(width: page.id == viewModel.currentPage ? 24 : 8, height: 8)
                }
            }
            .motionSafeAnimation(.spring(), value: viewModel.currentPage, reduceMotion: reduceMotion)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Page \(viewModel.currentPage + 1) of \(viewModel.pages.count)")

            Button {
                if viewModel.isLastPage {
                    session.startTasteProfile()
                } else {
                    withAnimation(reduceMotion ? nil : .easeInOut) { viewModel.next() }
                }
            } label: {
                Label(viewModel.isLastPage ? "Get Started" : "Next", systemImage: "arrow.right")
                    .labelStyle(TrailingIconLabelStyle())
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 4) {
                Text("Already part of a table?")
                    .foregroundStyle(AppColors.textSecondary)
                Button("Sign In") { session.goToSignIn() }
                    .fontWeight(.semibold)
                    .foregroundStyle(AppColors.primary)
            }
            .font(AppFont.subheadline)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .frame(maxWidth: 560)           // keeps it readable on iPad
        .frame(maxWidth: .infinity)
        .screenBackground()
    }
}

/// The illustration card + title + badges for one page.
private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 22) {
            // Illustration: the "onboarding_hero" picture from Assets.xcassets
            // (two friends at a table). If it's missing, draws a simple emoji version.
            if UIImage(named: "onboarding_hero") != nil {
                Image("onboarding_hero")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(AppColors.border, lineWidth: 1))
                    .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                    .accessibilityHidden(true)
            } else {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(colors: [AppColors.surface, AppColors.surfaceMuted],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.title2)
                            .foregroundStyle(AppColors.primary)
                            .padding(10)
                            .background(Circle().fill(AppColors.primarySoft))
                        HStack(spacing: 40) {
                            Text(page.emojis.0).font(.system(size: 64))
                            Text(page.emojis.1).font(.system(size: 64))
                        }
                        Capsule()
                            .fill(AppColors.border)
                            .frame(width: 200, height: 18)
                            .overlay(Text("🍽️").font(.title3))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24).stroke(AppColors.border, lineWidth: 1)
                )
                .frame(height: 240)
                .shadow(color: .black.opacity(0.05), radius: 10, y: 4)
                .accessibilityHidden(true)

            }

            Text(page.title)
                .font(AppFont.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Text(page.message)
                .font(AppFont.body)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                ForEach(page.badges, id: \.self) { badge in
                    ChipView(title: badge.text, icon: badge.icon)
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Puts the icon AFTER the text ("Get Started →").
struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppContainer.demo().session)
}
