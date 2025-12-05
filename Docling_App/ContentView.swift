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
    @State private var globalOptions = ConversionOptions()
    
    @State private var showingPreview = false
    @State private var previewContent: String = ""
    @State private var previewTitle: String = ""
    @State private var previewIsRag: Bool = false
    
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    private let conversionService = ConversionService.shared
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar for settings
            SidebarView(options: $globalOptions, backendHealthy: backendManager.isHealthy)
                .frame(width: 250)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Main Content
            VStack(spacing: 0) {
                // Header / Status
                HStack {
                    Circle()
                        .fill(backendManager.isHealthy ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(backendManager.isHealthy ? "Backend Ready" : "Backend Unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Add Files") {
                        selectFiles()
                    }
                    .disabled(!backendManager.isHealthy)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                
                Divider()
                
                // File List
                if fileConversions.isEmpty {
                    VStack {
                        Spacer()
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                            .padding(.bottom)
                        Text("No files selected")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Text("Configure options in the sidebar and add files to start.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.textBackgroundColor))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(fileConversions) { conversion in
                                FileConversionRow(
                                    conversion: conversion,
                                    onConvert: {
                                        // Update options from current global state before retrying
                                        conversion.options = globalOptions
                                        conversionService.convertFile(conversion)
                                    },
                                    onSaveMarkdown: {
                                        if let content = conversion.markdownContent {
                                            let fileName = conversion.fileName.replacingOccurrences(of: ".\(conversion.fileURL.pathExtension)", with: ".md")
                                            conversionService.saveContent(content, suggestedFileName: fileName) { _ in }
                                        }
                                    },
                                    onSaveRag: {
                                        if let content = conversion.ragTextContent {
                                            let fileName = conversion.fileName.replacingOccurrences(of: ".\(conversion.fileURL.pathExtension)", with: "_rag.txt")
                                            conversionService.saveContent(content, suggestedFileName: fileName) { _ in }
                                        }
                                    },
                                    onPreview: {
                                        if let content = conversion.markdownContent {
                                            previewContent = content
                                            previewTitle = conversion.fileName
                                            previewIsRag = false
                                            showingPreview = true
                                        }
                                    }
                                )
                                Divider()
                            }
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor))
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .sheet(isPresented: $showingPreview) {
            MarkdownPreviewView(content: previewContent, title: previewTitle)
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            startHealthCheckTimer()
        }
    }
    
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
                    // Apply current global options
                    conversion.options = globalOptions
                    fileConversions.append(conversion)
                    
                    // Automatically start conversion
                    conversionService.convertFile(conversion)
                }
            }
        }
    }
    
    private func startHealthCheckTimer() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            backendManager.checkHealth()
        }
    }
}

struct SidebarView: View {
    @Binding var options: ConversionOptions
    var backendHealthy: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.headline)
                .padding(.bottom, 5)
            
            // Priority A: RAG Features
            Group {
                Text("RAG Options")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Toggle("RAG Clean Mode", isOn: $options.ragClean)
                    .help("Removes HTML comments and collapses whitespace")
            }
            
            Divider()
            
            // Priority B: Advanced Options
            Group {
                Text("Processing")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Toggle("Enable OCR", isOn: $options.ocrEnabled)
                    .help("Use OCR for scanned PDFs (Slower)")
                
                if options.ocrEnabled {
                    Text("OCR is active. Processing will take longer.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                
                VStack(alignment: .leading) {
                    Text("Table Mode")
                    Picker("Table Mode", selection: $options.tableMode) {
                        Text("Markdown Tables").tag("markdown")
                        Text("Flattened List").tag("list")
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }
            
            Divider()
            
            Group {
                Toggle("Debug Mode", isOn: $options.debugMode)
                    .help("Extract layout blocks for debugging")
            }
            
            Spacer()
            
            if !backendHealthy {
                Text("Backend is offline")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
    }
}

struct FileConversionRow: View {
    @ObservedObject var conversion: FileConversion
    let onConvert: () -> Void
    let onSaveMarkdown: () -> Void
    let onSaveRag: () -> Void
    let onPreview: () -> Void
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Icon
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundColor(.blue)
            
            // File Info
            VStack(alignment: .leading) {
                Text(conversion.fileName)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                statusView
            }
            
            Spacer()
            
            // Actions
            if case .done = conversion.status {
                HStack(spacing: 8) {
                    Button("Preview") { onPreview() }
                    
                    Menu("Save...") {
                        Button("Save as Markdown") { onSaveMarkdown() }
                        Button("Save as RAG Text") { onSaveRag() }
                    }
                    .menuStyle(.borderedButton)
                }
            } else if case .pending = conversion.status {
                Button("Convert") { onConvert() }
            } else if case .error = conversion.status {
                Button("Retry") { onConvert() }
            }
        }
        .padding()
        .background(conversion.status == .uploading ? Color.blue.opacity(0.05) : Color.clear)
    }
    
    @ViewBuilder
    private var statusView: some View {
        switch conversion.status {
        case .pending:
            Text("Pending")
                .font(.caption)
                .foregroundColor(.secondary)
        case .uploading:
            HStack(spacing: 4) {
                ProgressView().scaleEffect(0.5)
                Text("Processing...")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        case .done:
            Text("Ready")
                .font(.caption)
                .foregroundColor(.green)
        case .error(let msg):
            Text(msg)
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(1)
        }
    }
}

struct MarkdownPreviewView: View {
    let content: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var showRawSource = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                Picker("View Mode", selection: $showRawSource) {
                    Text("Rendered").tag(false)
                    Text("Raw Source").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            if showRawSource {
                TextEditor(text: .constant(content))
                    .font(.system(.body, design: .monospaced))
                    .padding()
            } else {
                ScrollView {
                    // SwiftUI's Text view supports basic Markdown rendering
                    Text(LocalizedStringKey(content))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
