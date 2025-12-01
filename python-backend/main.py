"""
Docling FastAPI Backend

This FastAPI server provides endpoints to convert documents to Markdown using Docling.

SETUP INSTRUCTIONS:
------------------
1. Create a virtual environment:
   cd python-backend
   python3 -m venv venv

2. Activate the virtual environment:
   source venv/bin/activate  # On macOS/Linux
   # or
   venv\Scripts\activate  # On Windows

3. Install dependencies:
   pip install -r requirements.txt

4. Run the server manually for development/testing:
   uvicorn main:app --host 127.0.0.1 --port 8765

5. For production (bundled in macOS app):
   The Swift app will run: <venv>/bin/python main.py
   Make sure the venv is created inside python-backend/venv before bundling.

BUNDLING INTO macOS APP:
------------------------
- The python-backend folder should be added to the Xcode project as a "Copy Bundle Resources"
- This will copy it to: Docling_App.app/Contents/Resources/backend/
- The Swift BackendManager will look for: backend/venv/bin/python
- Ensure venv is created and dependencies installed before building the app bundle
"""

import os
import tempfile
from pathlib import Path
from typing import Optional

import sys
from urllib.parse import quote
# Force unbuffered output immediately
sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

print("Starting Docling Backend...", flush=True)

# Fix mimetypes issue in sandboxed environment
import mimetypes
mimetypes.knownfiles = []
try:
    mimetypes.init()
except Exception:
    pass

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import StreamingResponse
import uvicorn
from contextlib import asynccontextmanager

# Initialize DocumentConverter lazily (will be loaded on first use)
converter = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Lifespan context manager for startup and shutdown."""
    # Startup - don't initialize Docling here, do it lazily
    global converter
    yield

app = FastAPI(title="Docling Markdown Converter", lifespan=lifespan)


def get_converter():
    """Get or initialize the DocumentConverter (lazy loading)."""
    global converter
    if converter is None:
        print("Loading Docling (this may take 10-30 seconds)...", flush=True)
        try:
            # Import Docling here (lazy import)
            from docling.document_converter import DocumentConverter as DC
            from docling.datamodel.base_models import InputFormat
            from docling.datamodel.pipeline_options import PdfPipelineOptions
            from docling.document_converter import PdfFormatOption
            
            pipeline_options = PdfPipelineOptions()
            pipeline_options.do_ocr = True
            pipeline_options.do_table_structure = True
            
            # Initialize converter with support for multiple formats
            # Docling will auto-detect format and use appropriate backend
            converter = DC(
                format_options={
                    InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options)
                }
            )
            print("DocumentConverter initialized successfully", flush=True)
        except Exception as e:
            print(f"ERROR: Failed to initialize DocumentConverter: {e}", flush=True)
            import traceback
            traceback.print_exc()
            raise
    return converter


@app.get("/health")
async def health_check():
    """Health check endpoint for backend status verification."""
    return {"status": "ok"}


@app.post("/convert")
async def convert_document(file: UploadFile = File(...)):
    """
    Convert an uploaded document to Markdown using Docling.
    
    Accepts a single file upload and returns the Markdown content.
    Supports PDF, DOCX, and other formats supported by Docling.
    """
    temp_file_path: Optional[Path] = None
    
    try:
        # Validate file
        if not file.filename:
            raise HTTPException(status_code=400, detail="No filename provided")
        
        print(f"Received file upload: {file.filename} (content-type: {file.content_type})", flush=True)
        
        # Create temporary file to save uploaded content
        temp_dir = tempfile.gettempdir()
        temp_file_path = Path(temp_dir) / f"docling_upload_{os.getpid()}_{Path(file.filename).name}"
        
        # Write uploaded content to temp file
        content = await file.read()
        print(f"Read {len(content)} bytes from upload", flush=True)
        
        with open(temp_file_path, 'wb') as temp_file:
            temp_file.write(content)
            temp_file.flush()
        
        print(f"Saved uploaded file to: {temp_file_path} ({len(content)} bytes)", flush=True)
        
        # Verify file was written correctly
        if not temp_file_path.exists():
            raise HTTPException(status_code=500, detail="Failed to save uploaded file")
        
        file_size = temp_file_path.stat().st_size
        print(f"Verified file exists, size: {file_size} bytes", flush=True)
        
        # Convert document using Docling in a thread pool to avoid blocking
        try:
            print(f"Starting conversion of {file.filename}...", flush=True)
            
            # Run the blocking conversion in a thread pool
            import asyncio
            from concurrent.futures import ThreadPoolExecutor
            
            def run_conversion(file_path: str, filename: str) -> str:
                """Run the actual conversion (blocking operation)."""
                doc_converter = get_converter()
                print("DocumentConverter retrieved, calling convert()...", flush=True)
                
                # Check file extension to determine format
                file_ext = Path(filename).suffix.lower()
                print(f"File extension: {file_ext}", flush=True)
                
                result = doc_converter.convert(file_path)
                print("Conversion completed, rendering as Markdown...", flush=True)
                
                # Render as Markdown using document.export_to_markdown()
                markdown_content = result.document.export_to_markdown()
                print(f"Markdown generated ({len(markdown_content)} characters)", flush=True)
                
                return markdown_content
            
            # Execute conversion in thread pool
            loop = asyncio.get_event_loop()
            with ThreadPoolExecutor(max_workers=1) as executor:
                markdown_content = await loop.run_in_executor(
                    executor,
                    run_conversion,
                    str(temp_file_path),
                    file.filename
                )
            
        except Exception as e:
            import traceback
            error_msg = str(e)
            error_trace = traceback.format_exc()
            print(f"ERROR: {error_msg}", flush=True)
            print(f"Traceback:\n{error_trace}", flush=True)
            # Return a concise error message (FastAPI will format it as JSON)
            raise HTTPException(status_code=500, detail=error_msg)
        
        # Generate output filename
        original_name = Path(file.filename).stem
        output_filename = f"{original_name}.md"
        
        # Clean up temporary file now that conversion is complete
        if temp_file_path and temp_file_path.exists():
            try:
                temp_file_path.unlink()
                print(f"Cleaned up temp file: {temp_file_path}", flush=True)
            except Exception as e:
                print(f"Warning: Failed to delete temp file {temp_file_path}: {e}", flush=True)
        
        # Return Markdown as downloadable file
        def generate():
            yield markdown_content.encode('utf-8')
        
        return StreamingResponse(
            generate(),
            media_type="text/markdown",
            headers={
                "Content-Disposition": f'attachment; filename*=UTF-8\'\'{quote(output_filename)}'
            }
        )
        
    except HTTPException:
        # Clean up temp file before re-raising HTTP exceptions
        if temp_file_path and temp_file_path.exists():
            try:
                temp_file_path.unlink()
            except Exception:
                pass
        raise
    except HTTPException:
        # Re-raise HTTP exceptions (they already have proper formatting)
        raise
    except Exception as e:
        # Handle any other unexpected errors
        import traceback
        error_msg = str(e)
        error_trace = traceback.format_exc()
        print(f"ERROR: {error_msg}", flush=True)
        print(f"Traceback:\n{error_trace}", flush=True)
        
        # Clean up temp file if it exists
        if temp_file_path and temp_file_path.exists():
            try:
                temp_file_path.unlink()
            except Exception:
                pass
        
        raise HTTPException(status_code=500, detail=error_msg)


if __name__ == "__main__":
    # Run the server when executed directly (used by Swift app)
    # The Swift app runs: python main.py
    import socket
    
    print("Entering main block", flush=True)
    
    def is_port_in_use(port: int) -> bool:
        """Check if a port is already in use."""
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(('127.0.0.1', port))
                return False
            except OSError:
                return True
    
    port = 8765
    print("Starting FastAPI server...", flush=True)
    print(f"Host: 127.0.0.1", flush=True)
    print(f"Port: {port}", flush=True)
    
    # Check if port is in use
    if is_port_in_use(port):
        print(f"WARNING: Port {port} is already in use. Attempting to use it anyway...", flush=True)
        print("(This might fail if another process is using the port)", flush=True)
    else:
        print(f"Port {port} is available", flush=True)
    
    print("Initializing uvicorn...", flush=True)
    try:
        uvicorn.run(
            app,
            host="127.0.0.1",
            port=port,
            log_level="info"
        )
    except Exception as e:
        print(f"ERROR: Failed to start server: {e}", flush=True, file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

