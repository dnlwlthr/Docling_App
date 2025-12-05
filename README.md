# Docling App for macOS

![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)
![Python](https://img.shields.io/badge/Python-3.10+-blue.svg)
![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)
![License](https://img.shields.io/badge/License-MIT-green.svg)

A native macOS application that brings the power of [Docling](https://github.com/DS4SD/docling) to your desktop. Convert PDF, DOCX, PPTX, and other document formats into clean, structured Markdown entirely locally on your machine.

**Now optimized for RAG (Retrieval-Augmented Generation) workflows!**

## 🚀 Features

-   **Local Processing**: All conversions happen on your device. No data is ever sent to the cloud, ensuring complete privacy.
-   **Wide Format Support**: Supports PDF, DOCX, PPTX, XLSX, and more.
-   **Batch Processing**: Select and convert multiple files simultaneously.
-   **RAG Optimization**:
    -   **Save as RAG Text**: Export a cleaned, text-optimized version of your documents suitable for LLM context.
    -   **Clean Mode**: Automatically removes HTML comments and collapses whitespace.
    -   **Table Flattening**: Option to convert complex tables into flattened lists for better RAG retrieval.
-   **Advanced Options**:
    -   **OCR Toggle**: Enable/disable OCR for scanned documents (configurable per batch).
    -   **Debug Mode**: Inspect layout blocks and document structure.
-   **Native Experience**: Clean, modern SwiftUI interface with a split-view layout.
-   **Markdown Preview**: Toggle between rendered rich text and raw Markdown source.

## 🛠 Architecture

This application uses a hybrid architecture to combine the best of native macOS UI with powerful Python libraries:

-   **Frontend**: Native macOS app built with **SwiftUI**. Handles the UI, file management, and process lifecycle.
-   **Backend**: A lightweight **FastAPI** server running locally as a sidecar process. It hosts the Docling library and exposes conversion endpoints.
-   **Communication**: The Swift app manages the Python process and communicates via local HTTP requests.

## 📦 Installation

### Prerequisites
-   macOS 13.0 (Ventura) or later
-   Xcode 15+ (for building)
-   Python 3.10+ installed on your system

### Building from Source

1.  **Clone the repository**
    ```bash
    git clone https://github.com/yourusername/Docling_App.git
    cd Docling_App
    ```

2.  **Set up the Python Backend**
    The app requires a standalone Python environment bundled with it.
    ```bash
    cd python-backend
    ./setup_venv.sh
    ```
    *Note: This script creates a virtual environment in `python-backend/venv` and installs dependencies from `requirements.txt`.*

3.  **Open in Xcode**
    Open `Docling_App.xcodeproj` in Xcode.

4.  **Verify Backend Linking**
    Ensure the `python-backend` folder is added to the project as a **Folder Reference** (blue folder icon) and is included in the "Copy Bundle Resources" build phase.

5.  **Build and Run**
    Select the `Docling_App` scheme and press `Cmd+R` to build and run.

## 💻 Usage

1.  **Configure Settings**: Use the sidebar to set your preferences (OCR, RAG Clean Mode, Table Mode) **before** adding files.
2.  **Add Files**: Click "Add Files" to select one or more documents.
3.  **Convert**: Files are processed automatically. You can retry failed conversions individually.
4.  **Preview**: Click "Preview" on a completed file to see the result. Toggle between "Rendered" and "Raw Source" views.
5.  **Export**:
    -   **Save as Markdown**: Standard Docling output.
    -   **Save as RAG Text**: Optimized text output for AI applications.

## 💻 Development

### Backend Development
You can develop and test the backend independently of the Swift app.

1.  Activate the virtual environment:
    ```bash
    source python-backend/venv/bin/activate
    ```

2.  Run the server:
    ```bash
    cd python-backend
    python main.py
    ```
    The server will start on `http://127.0.0.1:8765`. You can access the API documentation at `/docs`.

### Frontend Development
The `BackendManager.swift` class handles the lifecycle of the Python process.
-   **Debug Mode**: When running from Xcode, it looks for the backend in the source directory or bundle resources.
-   **Release Mode**: It expects the backend to be bundled within `Contents/Resources/python-backend`.

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

-   [Docling](https://github.com/DS4SD/docling) for the incredible document conversion capabilities.
-   [FastAPI](https://fastapi.tiangolo.com/) for the robust Python backend framework.
