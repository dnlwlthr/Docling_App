# Setup Instructions for Docling Markdown App

## ✅ Step 1: Python Backend Setup (COMPLETED)
The virtual environment has been created and dependencies installed.

## 📋 Step 2: Add Backend to Xcode Project

You need to add the `python-backend` folder to your Xcode project so it gets bundled with the app.

### Instructions:

1. **Open Xcode** and open `Docling_App.xcodeproj`

2. **Add the backend folder**:
   - Right-click on the project root (or the `Docling_App` folder) in the Project Navigator
   - Select **"Add Files to 'Docling_App'..."**
   - Navigate to and select the `python-backend` folder
   - **IMPORTANT**: In the dialog that appears:
     - ✅ Check **"Copy items if needed"** (if not already checked)
     - ✅ Select **"Create folder references"** (blue folder icon) - NOT "Create groups" (yellow folder)
     - ✅ Make sure **"Add to targets: Docling_App"** is checked
   - Click **"Add"**

3. **Verify it's in Copy Bundle Resources**:
   - Select the project in the Project Navigator
   - Select the **"Docling_App"** target
   - Go to **"Build Phases"** tab
   - Expand **"Copy Bundle Resources"**
   - Verify that `python-backend` is listed there (it should appear automatically)
   - If it's not there, click the **"+"** button and add it manually

4. **Verify the folder reference**:
   - In the Project Navigator, you should see `python-backend` with a **blue folder icon** (not yellow)
   - This indicates it's a folder reference, which is correct

## 🚀 Step 3: Build and Run

1. **Select a scheme**: Choose "Docling_App" from the scheme dropdown (top left)

2. **Select a destination**: Choose "My Mac" or your Mac from the destination dropdown

3. **Build and Run**: Press **⌘R** or click the Play button

4. **What to expect**:
   - The app will launch
   - It will automatically start the Python backend
   - After 2-3 seconds, the status indicator should turn **green** ("Backend running")
   - If it stays red, check the Xcode console for error messages

## 🧪 Step 4: Test the App

1. **Click "Choose files…"** button
2. **Select one or more documents** (PDF, DOCX, etc.)
3. **Watch the conversion**:
   - Files will show "Uploading…" status
   - Then change to "Done" when complete
4. **Save or Preview**:
   - Click "Save Markdown…" to save the converted file
   - Click "Preview" to view the Markdown in a popup window

## 🔍 Troubleshooting

### Backend Not Starting

**Check Xcode Console** for messages like:
- `"ERROR: Could not find backend folder in app bundle"`
- `"ERROR: Could not find Python executable in venv"`

**Solutions**:
- Make sure `python-backend` is added as a **folder reference** (blue icon), not a group (yellow icon)
- Verify `python-backend/venv` exists and has the Python executable
- Check that `python-backend` is in "Copy Bundle Resources"

### Backend Not Reachable (Red Status)

**Check**:
- Look for `[Backend stdout]` or `[Backend stderr]` messages in Xcode console
- Verify port 8765 is not in use: `lsof -i :8765`
- Try restarting the app

### Conversion Fails

**Check**:
- File format is supported (PDF, DOCX, PPTX, XLSX, RTF, TXT)
- File is not password-protected
- File is not corrupted
- Check backend logs in Xcode console

## 📁 Expected App Bundle Structure

After building, the app bundle should contain:
```
Docling_App.app/
└── Contents/
    └── Resources/
        └── backend/
            ├── venv/
            │   └── bin/
            │       └── python
            ├── main.py
            ├── requirements.txt
            └── ...
```

You can verify this by:
1. Right-clicking the app in Finder → "Show Package Contents"
2. Navigating to `Contents/Resources/backend/`
3. Verifying the `venv` folder exists

