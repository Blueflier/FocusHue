//
//  SettingsView.swift
//  FocusHue
//
//  Settings panel for configuring distraction domains and activation delay
//

import SwiftUI

struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var newDomain: String = ""
    @State private var showingResetConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Activation Delay Section
                    delaySection
                    
                    Divider()
                    
                    // Distraction Domains Section
                    domainsSection
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Reset to Defaults") {
                    showingResetConfirmation = true
                }
                .foregroundColor(.red)
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 350, height: 450)
        .alert("Reset Settings?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                settingsManager.resetToDefaults()
            }
        } message: {
            Text("This will restore the default distraction sites and activation delay.")
        }
    }
    
    // MARK: - Delay Section
    
    private var delaySection: some View {
        @Bindable var settings = settingsManager
        
        return VStack(alignment: .leading, spacing: 8) {
            Text("Activation Delay")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("Seconds before grayscale activates (1-120)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                TextField(
                    "Seconds",
                    value: $settings.activationDelay,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.center)
                
                Text("seconds")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Domains Section
    
    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Distraction Sites")
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Text("Grayscale will activate when you visit these domains")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Add new domain
            HStack {
                TextField("Add domain (e.g. youtube.com)", text: $newDomain)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        addDomain()
                    }
                
                Button {
                    addDomain()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(newDomain.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            
            // Domain list
            if settingsManager.distractionDomains.isEmpty {
                Text("No distraction sites configured")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                VStack(spacing: 4) {
                    ForEach(settingsManager.distractionDomains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                                .font(.system(.caption, design: .monospaced))
                            
                            Spacer()
                            
                            Button {
                                withAnimation {
                                    settingsManager.removeDomain(domain)
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func addDomain() {
        let domain = newDomain.trimmingCharacters(in: .whitespaces)
        guard !domain.isEmpty else { return }
        
        withAnimation {
            settingsManager.addDomain(domain)
        }
        newDomain = ""
    }
}
