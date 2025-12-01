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
enum ConversionStatus {
    case pending
    case uploading
    case done
    case error(String)
}

/// Represents a file being converted.
class FileConversion: ObservableObject, Identifiable {
    let id = UUID()
    let fileURL: URL
    let fileName: String
    
    @Published var status: ConversionStatus = .pending
    @Published var markdownContent: String?
    
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
    /// Updates the FileConversion object's status and markdownContent.
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
                        // Try to get error details from response body
                        if let data = data, !data.isEmpty {
                            // Try JSON first (FastAPI error format: {"detail": "error message"})
                            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                if let detail = errorJson["detail"] as? String {
                                    errorMsg = detail
                                } else {
                                    // Print full JSON for debugging
                                    print("Error response JSON (no 'detail' field): \(errorJson)")
                                    if let jsonString = String(data: data, encoding: .utf8) {
                                        print("Raw JSON: \(jsonString)")
                                    }
                                }
                            } else if let errorText = String(data: data, encoding: .utf8), !errorText.isEmpty {
                                // Not JSON, use as plain text (limit length)
                                let maxLength = 500
                                if errorText.count > maxLength {
                                    errorMsg = String(errorText.prefix(maxLength)) + "..."
                                } else {
                                    errorMsg = errorText
                                }
                            }
                            print("Conversion failed (HTTP \(httpResponse.statusCode)): \(errorMsg)")
                        } else {
                            print("Conversion failed: HTTP \(httpResponse.statusCode) (no response body)")
                        }
                        fileConversion.status = .error(errorMsg)
                        return
                    }
                    
                    guard let data = data,
                          let markdown = String(data: data, encoding: .utf8) else {
                        fileConversion.status = .error("Failed to decode Markdown response")
                        return
                    }
                    
                    fileConversion.markdownContent = markdown
                    fileConversion.status = .done
                }
            }
            
            task.resume()
            
        } catch {
            DispatchQueue.main.async {
                fileConversion.status = .error("Failed to read file: \(error.localizedDescription)")
            }
        }
    }
    
    /// Save markdown content to a file using a save panel.
    func saveMarkdown(_ markdown: String, suggestedFileName: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.plainText]
            savePanel.nameFieldStringValue = suggestedFileName
            savePanel.title = "Save Markdown File"
            
            savePanel.begin { response in
                if response == .OK, let url = savePanel.url {
                    do {
                        try markdown.write(to: url, atomically: true, encoding: .utf8)
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

