//
//  FileConversion.swift
//  Docling_App
//
//  Model and service for handling document conversion.
//

import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

/// Represents the status of a file conversion.
enum ConversionStatus: Equatable {
    case pending
    case uploading
    case done
    case error(String)
}

/// Options for the conversion process.
struct ConversionOptions {
    var ocrEnabled: Bool = true
    var ragClean: Bool = false
    var tableMode: String = "markdown" // "markdown" or "list"
    var debugMode: Bool = false
}

/// Represents a file being converted.
class FileConversion: ObservableObject, Identifiable {
    let id = UUID()
    let fileURL: URL
    let fileName: String
    
    @Published var status: ConversionStatus = .pending
    @Published var markdownContent: String?
    @Published var ragTextContent: String?
    @Published var debugInfo: [Any]? // Placeholder for debug info
    
    var options: ConversionOptions = ConversionOptions()
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
    }
}

/// Service for converting files using the backend API.
class ConversionService {
    static let shared = ConversionService()
    
    private let backendManager = BackendManager.shared
    
    private init() {}
    
    /// Convert a file by uploading it to the backend.
    /// Updates the FileConversion object's status and content.
    func convertFile(_ fileConversion: FileConversion) {
        let baseURL = backendManager.getBaseURL().appendingPathComponent("convert")
        
        DispatchQueue.main.async {
            fileConversion.status = .uploading
        }
        
        // Create multipart form data request
        let boundary = UUID().uuidString
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300.0  // 5 minutes for large document processing
        
        // Build multipart body
        var body = Data()
        
        // Helper to append form fields
        func appendFormField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        
        // Add options
        appendFormField(name: "ocr_enabled", value: String(fileConversion.options.ocrEnabled))
        appendFormField(name: "rag_clean", value: String(fileConversion.options.ragClean))
        appendFormField(name: "table_mode", value: fileConversion.options.tableMode)
        appendFormField(name: "debug_mode", value: String(fileConversion.options.debugMode))
        
        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileConversion.fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        
        do {
            let fileData = try Data(contentsOf: fileConversion.fileURL)
            body.append(fileData)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            request.httpBody = body
            
            // Perform request
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    if let error = error {
                        fileConversion.status = .error("Network error: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        fileConversion.status = .error("Invalid response")
                        return
                    }
                    
                    guard httpResponse.statusCode == 200 else {
                        var errorMsg = "Server error: HTTP \(httpResponse.statusCode)"
                        if let data = data, let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let detail = errorJson["detail"] as? String {
                            errorMsg = detail
                        }
                        fileConversion.status = .error(errorMsg)
                        return
                    }
                    
                    guard let data = data else {
                        fileConversion.status = .error("No data received")
                        return
                    }
                    
                    // Parse JSON response
                    do {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            if let markdown = json["markdown"] as? String {
                                fileConversion.markdownContent = markdown
                            }
                            if let ragText = json["rag_text"] as? String {
                                fileConversion.ragTextContent = ragText
                            }
                            // Debug info parsing can be added here
                            
                            fileConversion.status = .done
                        } else {
                            fileConversion.status = .error("Invalid JSON response")
                        }
                    } catch {
                        fileConversion.status = .error("Failed to parse response: \(error.localizedDescription)")
                    }
                }
            }
            
            task.resume()
            
        } catch {
            DispatchQueue.main.async {
                fileConversion.status = .error("Failed to read file: \(error.localizedDescription)")
            }
        }
    }
    
    /// Save text content to a file using a save panel.
    func saveContent(_ content: String, suggestedFileName: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.plainText]
            savePanel.nameFieldStringValue = suggestedFileName
            savePanel.title = "Save File"
            
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    do {
                        try content.write(to: url, atomically: true, encoding: .utf8)
                        completion(true)
                    } catch {
                        print("Failed to save file: \(error)")
                        completion(false)
                    }
                } else {
                    completion(false)
                }
            }
        }
    }
}
