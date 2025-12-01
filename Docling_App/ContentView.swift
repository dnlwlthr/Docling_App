//
//  ContentView.swift
//  Docling_App
//
//  Main view for document conversion UI.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var backendManager = BackendManager.shared
    @State private var fileConversions: [FileConversion] = []
    @State private var showingFilePicker = false
    @State private var showingPreview = false
    @State private var previewContent: String = ""
    @State private var previewTitle: String = ""
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    private let conversionService = ConversionService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Status indicator
            HStack {
                Circle()
                    .fill(backendManager.isHealthy ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                Text(backendManager.isHealthy ? "Backend running" : "Backend not reachable")
                    .font(.headline)
            }
            .padding(.top)
            
            Divider()
            
            // File selection button
            Button("Choose files…") {
                selectFiles()
            }
            .disabled(!backendManager.isHealthy)
            .buttonStyle(.borderedProminent)
            
            // File list
            if fileConversions.isEmpty {
                Spacer()
                Text("No files selected")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(fileConversions) { conversion in
                            FileConversionRow(
                                conversion: conversion,
                                onConvert: {
                                    conversionService.convertFile(conversion)
                                },
                                onSave: {
                                    if let markdown = conversion.markdownContent {
                                        let fileName = conversion.fileName.replacingOccurrences(of: ".\(conversion.fileURL.pathExtension)", with: ".md")
                                        conversionService.saveMarkdown(markdown, suggestedFileName: fileName) { success in
                                            if !success {
                                                errorMessage = "Failed to save file"
                                                showingErrorAlert = true
                                            }
                                        }
                                    }
                                },
                                onPreview: {
                                    if let markdown = conversion.markdownContent {
                                        previewContent = markdown
                                        previewTitle = conversion.fileName
                                        showingPreview = true
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding()
        .sheet(isPresented: $showingPreview) {
            MarkdownPreviewView(content: previewContent, title: previewTitle)
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            // Start periodic health checks
            startHealthCheckTimer()
        }
    }
    
    /// Open file picker to select documents.
    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            .pdf,
            UTType(filenameExtension: "docx") ?? .data,
            UTType(filenameExtension: "doc") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            UTType(filenameExtension: "ppt") ?? .data,
            UTType(filenameExtension: "xlsx") ?? .data,
            UTType(filenameExtension: "xls") ?? .data,
            .rtf,
            .plainText
        ]
        
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    let conversion = FileConversion(fileURL: url)
                    fileConversions.append(conversion)
                    
                    // Automatically start conversion
                    conversionService.convertFile(conversion)
                }
            }
        }
    }
    
    /// Start a timer to periodically check backend health.
    private func startHealthCheckTimer() {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            backendManager.checkHealth()
        }
    }
}

/// Row view for a single file conversion.
struct FileConversionRow: View {
    @ObservedObject var conversion: FileConversion
    let onConvert: () -> Void
    let onSave: () -> Void
    let onPreview: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(conversion.fileName)
                    .font(.headline)
                Spacer()
                statusBadge
            }
            
            HStack(spacing: 12) {
                if case .pending = conversion.status {
                    Button("Convert") {
                        onConvert()
                    }
                    .buttonStyle(.bordered)
                }
                
                if case .done = conversion.status {
                    Button("Save Markdown…") {
                        onSave()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Preview") {
                        onPreview()
                    }
                    .buttonStyle(.bordered)
                }
                
                if case .error(let message) = conversion.status {
                    Text("Error: \(message)")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var statusBadge: some View {
        Group {
            switch conversion.status {
            case .pending:
                Text("Pending")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.2))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
            case .uploading:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Uploading…")
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(4)
            case .done:
                Text("Done")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .cornerRadius(4)
            case .error:
                Text("Error")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.2))
                    .foregroundColor(.red)
                    .cornerRadius(4)
            }
        }
    }
}

/// Preview view for Markdown content.
struct MarkdownPreviewView: View {
    let content: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            ScrollView {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

#Preview {
    ContentView()
}
