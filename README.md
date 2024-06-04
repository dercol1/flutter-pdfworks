# Flutter PDF Editor App

This project is a Flutter application for editing PDF files. It includes features for loading, viewing, and editing PDFs, performing OCR (Optical Character Recognition), and compressing PDF files. The app also displays detailed logs of operations performed, which can be saved for later analysis.

## Features

- Load PDF
- View PDF
- Perform OCR on PDF
- Compress PDF
- View and save operation logs
- Support for non-blocking dialog windows for license information and logs

## Requirements

- Flutter SDK
- Dart
- An Android/iOS device or emulator

## Installation

1. Clone this repository:

    ```sh
    git clone https://github.com/dercol1/flutter-pdfworks.git
    cd flutter-pdfworks
    ```

2. Install dependencies:

    ```sh
    flutter pub get
    ```

3. Run the app:

    ```sh
    flutter run
    ```

## Usage

1. **Load a PDF**:
   - Use the "Load PDF" button to select a PDF file from your device.

2. **View the PDF**:
   - You can view the loaded PDF directly in the app.

3. **Perform OCR**:
   - Press the "Perform OCR" button (article icon) to perform optical character recognition on the loaded PDF.

4. **Compress PDF**:
   - After performing OCR, the PDF will be automatically compressed.

5. **View and save logs**:
   - Press the "?" button next to the debug switch to view license information and access the log.
   - The log is selectable and updates in real-time. You can save it by pressing the "Save Log" button.

## Code Structure

- `main.dart`: Contains the main application code for the Flutter app.

## Dependencies

Use dependacies from pubspec.yaml file
