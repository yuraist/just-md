import SwiftUI

/// "Support JustMD": newsletter signup and, in the App Store build, the
/// repeatable "Buy me a coffee" consumable.
@MainActor
struct SupportView: View {
    @StateObject private var newsletter = NewsletterViewModel()
    #if !DIRECT_DISTRIBUTION
    @StateObject private var coffee = CoffeeStore()
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Support JustMD")
                    .font(.system(size: 28, weight: .light, design: .serif))
                Text("JustMD is free and made by one person. Here are two ways to help.")
                    .foregroundStyle(.secondary)
            }
            newsletterSection
            #if !DIRECT_DISTRIBUTION
            if coffee.state != .unavailable {
                coffeeSection
            }
            #endif
        }
        .padding(32)
        .frame(width: 440)
        .task {
            #if !DIRECT_DISTRIBUTION
            await coffee.load()
            #endif
        }
    }

    private var newsletterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Get updates").font(.headline)
            Text("Occasional emails about new versions. No spam, unsubscribe anytime.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if newsletter.state == .subscribed {
                Label("You're on the list: \(newsletter.email)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    TextField("you@example.com", text: $newsletter.email)
                        .textFieldStyle(.roundedBorder)
                        .disabled(newsletter.state == .sending)
                        .onSubmit { Task { await newsletter.subscribe() } }
                    Button(newsletter.state == .sending ? "Sending…" : "Subscribe") {
                        Task { await newsletter.subscribe() }
                    }
                    .disabled(!newsletter.canSubmit)
                    .keyboardShortcut(.defaultAction)
                }
                if case .failed(let message) = newsletter.state {
                    Text(message).font(.callout).foregroundStyle(.red)
                }
            }
        }
    }

    #if !DIRECT_DISTRIBUTION
    private var coffeeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Buy me a coffee").font(.headline)
            Text("A small thank-you that keeps the editor going. Buy as many as you like.")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    Task { await coffee.buy() }
                } label: {
                    Label(coffeeButtonTitle, systemImage: "cup.and.saucer.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(coffee.state == .loading || coffee.state == .purchasing)
                if coffee.coffeeCount > 0 {
                    Text("☕️ × \(coffee.coffeeCount), thank you!")
                        .foregroundStyle(.secondary)
                }
            }
            if case .failed(let message) = coffee.state {
                Text(message).font(.callout).foregroundStyle(.red)
            }
        }
    }

    private var coffeeButtonTitle: String {
        switch coffee.state {
        case .loading: return "Loading…"
        case .purchasing: return "Purchasing…"
        default: return "Buy me a coffee · \(coffee.product?.displayPrice ?? "")"
        }
    }
    #endif
}
