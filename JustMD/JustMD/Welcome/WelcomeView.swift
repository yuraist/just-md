//
//  WelcomeView.swift
//  JustMD
//
//  Created by Yuri Istomin on 4/18/26.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct WelcomeView: View {
    let onNew: () -> Void
    let onOpen: () -> Void
    let onOpenURL: (URL) -> Void
    var onSupport: (() -> Void)? = nil

    @State private var recents: [URL] = []
    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 32) {
            Text("just.md")
                .font(.system(size: 48, weight: .light, design: .serif))
                .foregroundStyle(.primary)

            HStack(spacing: 16) {
                actionButton("New", systemImage: "doc.text", action: onNew)
                actionButton("Open", systemImage: "folder", action: onOpen)
                dropZone
            }

            if !recents.isEmpty {
                recentsList
            }

            if let onSupport {
                Button("Support JustMD", action: onSupport)
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
        .frame(minWidth: 520, minHeight: 360)
        .onAppear { reloadRecents() }
        // The window stays alive between showings, so `onAppear` fires once;
        // refresh whenever it comes back to the front.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            reloadRecents()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            reloadRecents()
        }
    }

    @ViewBuilder
    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 24))
                Text(title).font(.system(size: 13))
            }
            .frame(width: 120, height: 80)
        }
        .buttonStyle(.plain)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.3)))
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "arrow.down.doc")
                .font(.system(size: 24))
            Text("Drop").font(.system(size: 13))
        }
        .frame(width: 120, height: 80)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(
            isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
            style: StrokeStyle(lineWidth: 1, dash: [4])
        ))
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                if ["md", "markdown", "mdown", "mkd"].contains(url.pathExtension.lowercased()) {
                    DispatchQueue.main.async {
                        self.onOpenURL(url)
                    }
                }
            }
        }
        return true
    }

    private var recentsList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(recents.prefix(8), id: \.self) { url in
                Button {
                    onOpenURL(url)
                } label: {
                    HStack {
                        Text(url.lastPathComponent).lineLimit(1)
                        Spacer()
                        Text(relativeDate(url)).foregroundStyle(.secondary).font(.system(size: 11))
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 400)
    }

    private func relativeDate(_ url: URL) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mod = attrs[.modificationDate] as? Date else {
            return ""
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: mod, relativeTo: Date())
    }

    private func reloadRecents() {
        recents = NSDocumentController.shared.recentDocumentURLs
    }
}
