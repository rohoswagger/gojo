//
//  PermissionsRequestView.swift
//  Gojo
//
//  Created by Alexander on 2025-06-23.
//

import SwiftUI

struct PermissionRequestView: View {
    let icon: Image
    let title: String
    let description: String
    let privacyNote: String?
    let onAllow: () -> Void
    let onSkip: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            SunsetBackground()

            VStack(spacing: 24) {
                iconBadge
                    .padding(.top, 32)
                    .scaleEffect(appeared ? 1 : 0.8)
                    .opacity(appeared ? 1 : 0)

                VStack(spacing: 16) {
                    Text(title)
                        .font(.title)
                        .fontWeight(.semibold)

                    Text(description)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                    if let privacyNote = privacyNote {
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.secondary)
                            Text(privacyNote)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                HStack {
                    Button("Not Now") { onSkip() }
                        .buttonStyle(.bordered)
                    Button("Allow Access") { onAllow() }
                        .buttonStyle(GlassButtonStyle())
                }
                .padding(.top, 6)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.1)) {
                appeared = true
            }
        }
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.effectiveAccent.opacity(0.28), .clear],
                        center: .center, startRadius: 0, endRadius: 70
                    )
                )
                .frame(width: 150, height: 150)

            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().stroke(Color.effectiveAccent.opacity(0.35), lineWidth: 1))
                .frame(width: 96, height: 96)

            icon
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 38)
                .foregroundColor(.effectiveAccent)
        }
    }
}
