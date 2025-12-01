//
//  BackendManager.swift
//  Docling_App
//
//  Manages the lifecycle of the Python FastAPI backend process.
//
//  BUNDLING SETUP:
//  ---------------
//  1. Create a virtual environment in python-backend:
//     cd python-backend
//     ./setup_venv.sh
//     (or manually: python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt)
//
//  2. In Xcode, add python-backend folder to the project:
//     - Right-click project → Add Files to "Docling_App"...
//     - Select the python-backend folder
//     - Check "Create folder references" (not groups)
//     - Add to target: Docling_App
//     - In Build Phases → Copy Bundle Resources, ensure python-backend is included
//
//  3. The backend will be copied to: Docling_App.app/Contents/Resources/backend/
//     The BackendManager looks for: backend/venv/bin/python
//

import Foundation
import Combine
import Darwin

/// Manages the Python FastAPI backend process lifecycle.
class BackendManager: ObservableObject {
    static let shared = BackendManager()
    
    /// Backend server URL
    private let backendURL = URL(string: "http://127.0.0.1:8765")!
    
    /// Python process instance
    private var pythonProcess: Process?
    
    /// Process output pipes for logging
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    
    /// Health check status
    @Published var isHealthy: Bool = false
    
    /// Whether the backend process is running
    @Published var isRunning: Bool = false
    
    private let healthCheckQueue = DispatchQueue(label: "com.doclingapp.healthcheck")
    
    private init() {
        // Private initializer for singleton
    }
    
    /// Start the backend process if not already running.
    /// This should be called early in the app lifecycle.
    func startIfNeeded() {
        // First, make sure any existing backend is stopped
        if let existingProcess = pythonProcess, existingProcess.isRunning {
            print("Stopping existing backend process...")
            stop()
            // Wait a moment for port to be released
            Thread.sleep(forTimeInterval: 1.0)
        }
        
        guard pythonProcess == nil || pythonProcess?.isRunning != true else {
            print("Backend already running")
            return
        }
        
        // Check if port is in use and try to free it
        killProcessOnPort(8765)
        
        guard let backendPath = getBackendPath() else {
            print("ERROR: Could not find backend folder in app bundle")
            if let resourcesURL = Bundle.main.resourceURL {
                print("  Looking in: \(resourcesURL.path)")
                print("  Expected: \(resourcesURL.appendingPathComponent("python-backend").path)")
                
                // List contents of Resources folder
                if let contents = try? FileManager.default.contentsOfDirectory(atPath: resourcesURL.path) {
                    print("  Contents of Resources folder:")
                    for item in contents {
                        print("    - \(item)")
                    }
                }
            } else {
                print("  Could not get Bundle.main.resourceURL")
            }
            return
        }
        
        print("Found backend folder at: \(backendPath.path)")
        
        guard let pythonExecutable = getPythonExecutable(backendPath: backendPath) else {
            print("ERROR: Could not find Python executable in venv")
            print("Make sure you've run setup_venv.sh in python-backend before building")
            return
        }
        
        let mainPyPath = backendPath.appendingPathComponent("main.py")
        guard FileManager.default.fileExists(atPath: mainPyPath.path) else {
            print("ERROR: main.py not found at \(mainPyPath.path)")
            return
        }
        
        // Create process
        let process = Process()
        process.executableURL = pythonExecutable
        process.arguments = [mainPyPath.path]
        process.currentDirectoryURL = backendPath
        
        // Set up environment variables
        var env = ProcessInfo.processInfo.environment
        // Ensure Python can find its modules
        if let pythonPath = env["PYTHONPATH"] {
            env["PYTHONPATH"] = "\(backendPath.path):\(pythonPath)"
        } else {
            env["PYTHONPATH"] = backendPath.path
        }
        process.environment = env
        
        // Set up output pipes for logging
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        // Read output asynchronously
        setupOutputReading(stdout: stdoutPipe, stderr: stderrPipe)
        
        // Handle process termination
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.isHealthy = false
            }
            print("Backend process terminated with status: \(process.terminationStatus)")
        }
        
        do {
            // Verify Python executable is actually executable
            let pythonPath = pythonExecutable.path
            var isExecutable: ObjCBool = false
            if FileManager.default.fileExists(atPath: pythonPath, isDirectory: &isExecutable) {
                if isExecutable.boolValue {
                    print("WARNING: Python path is a directory, not a file")
                }
            }
            
            // Check file permissions
            let attrs = try? FileManager.default.attributesOfItem(atPath: pythonPath)
            print("Python executable attributes: \(attrs ?? [:])")
            
            try process.run()
            self.pythonProcess = process
            self.stdoutPipe = stdoutPipe
            self.stderrPipe = stderrPipe
            
            DispatchQueue.main.async {
                self.isRunning = true
            }
            
            print("Backend process started: PID \(process.processIdentifier)")
            print("Python executable: \(pythonExecutable.path)")
            print("Working directory: \(backendPath.path)")
            print("Command: \(pythonExecutable.path) \(mainPyPath.path)")
            
            // Check immediately if process started
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if !process.isRunning {
                    print("ERROR: Backend process terminated immediately")
                    print("Termination status: \(process.terminationStatus)")
                    print("Termination reason: \(process.terminationReason)")
                } else {
                    print("Backend process is running (PID: \(process.processIdentifier))")
                }
            }
            
            // Wait longer for server to start (Python + uvicorn need time)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                // Check if process is still running
                if process.isRunning {
                    print("Backend process is still running after 5s, checking health...")
                    self.checkHealth()
                } else {
                    print("ERROR: Backend process terminated before health check")
                    print("Termination status: \(process.terminationStatus)")
                    print("Termination reason: \(process.terminationReason)")
                }
            }
            
        } catch {
            print("ERROR: Failed to start backend process: \(error)")
            print("Error details: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                print("Error domain: \(nsError.domain)")
                print("Error code: \(nsError.code)")
                print("Error userInfo: \(nsError.userInfo)")
            }
        }
    }
    
    /// Stop the backend process.
    /// Should be called when the app is terminating.
    func stop() {
        guard let process = pythonProcess, process.isRunning else {
            return
        }
        
        print("Stopping backend process...")
        process.terminate()
        
        // Wait up to 5 seconds for graceful termination
        let timeout: TimeInterval = 5.0
        let startTime = Date()
        
        while process.isRunning && Date().timeIntervalSince(startTime) < timeout {
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Force kill if still running
        if process.isRunning {
            print("Force killing backend process")
            kill(process.processIdentifier, SIGKILL)
        }
        
        pythonProcess = nil
        stdoutPipe = nil
        stderrPipe = nil
        
        DispatchQueue.main.async {
            self.isRunning = false
            self.isHealthy = false
        }
    }
    
    /// Check backend health by calling the /health endpoint.
    /// Updates isHealthy property on completion.
    func checkHealth(completion: ((Bool) -> Void)? = nil) {
        healthCheckQueue.async {
            let healthURL = self.backendURL.appendingPathComponent("health")
            
            var request = URLRequest(url: healthURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0  // Increased to tolerate backend being busy
            
            let semaphore = DispatchSemaphore(value: 0)
            var healthStatus = false
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200,
                   let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["status"] as? String == "ok" {
                    healthStatus = true
                }
                
                semaphore.signal()
            }
            
            task.resume()
            semaphore.wait()
            
            DispatchQueue.main.async {
                // Only log if status changes to avoid spamming console
                if self.isHealthy != healthStatus {
                    print("Backend health changed: \(healthStatus ? "Healthy" : "Unhealthy")")
                }
                self.isHealthy = healthStatus
                completion?(healthStatus)
            }
        }
    }
    
    /// Get the base URL for backend API calls.
    func getBaseURL() -> URL {
        return backendURL
    }
    
    // MARK: - Private Helpers
    
    /// Find the backend folder in the app bundle.
    private func getBackendPath() -> URL? {
        guard let resourcesURL = Bundle.main.resourceURL else {
            return nil
        }
        
        // The folder is copied as "python-backend" from the project
        let backendURL = resourcesURL.appendingPathComponent("python-backend")
        
        guard FileManager.default.fileExists(atPath: backendURL.path) else {
            return nil
        }
        
        return backendURL
    }
    
    /// Find the Python executable in the venv.
    private func getPythonExecutable(backendPath: URL) -> URL? {
        let pythonPath = backendPath
            .appendingPathComponent("venv")
            .appendingPathComponent("bin")
            .appendingPathComponent("python")
        
        guard FileManager.default.fileExists(atPath: pythonPath.path) else {
            return nil
        }
        
        return pythonPath
    }
    
    /// Set up reading from stdout and stderr pipes for logging.
    private func setupOutputReading(stdout: Pipe, stderr: Pipe) {
        // Set pipes to non-blocking mode
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    print("[Backend stdout] \(output)", terminator: "")
                } else {
                    print("[Backend stdout] <binary data: \(data.count) bytes>")
                }
            }
        }
        
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                if let output = String(data: data, encoding: .utf8) {
                    print("[Backend stderr] \(output)", terminator: "")
                } else {
                    print("[Backend stderr] <binary data: \(data.count) bytes>")
                }
            }
        }
    }
    
    /// Kill any process using the specified port.
    private func killProcessOnPort(_ port: Int) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-ti", "TCP:\(port)"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let pids = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
                    for pidStr in pids {
                        if let pid = Int(pidStr), pid > 0, pid != getpid() {
                            print("Found process \(pid) using port \(port), killing it...")
                            kill(pid_t(pid), SIGTERM)
                            // Wait a moment for the process to terminate
                            Thread.sleep(forTimeInterval: 0.5)
                            // Force kill if still running
                            var checkTask = Process()
                            checkTask.executableURL = URL(fileURLWithPath: "/bin/ps")
                            checkTask.arguments = ["-p", "\(pid)"]
                            checkTask.standardOutput = Pipe()
                            checkTask.standardError = Pipe()
                            try? checkTask.run()
                            checkTask.waitUntilExit()
                            if checkTask.terminationStatus == 0 {
                                // Process still exists, force kill
                                kill(pid_t(pid), SIGKILL)
                            }
                        }
                    }
                }
            }
        } catch {
            print("Warning: Could not check/kill processes on port \(port): \(error)")
        }
    }
}

