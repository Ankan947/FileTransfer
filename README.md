# Resumable Large-File Transfer App

A resilient, native Android application designed to handle massive file uploads and downloads without crashing or losing progress. Built for the **GDG on Campus SRM Recruitments (Task 2)**, this app utilizes precise byte-chunking and a local SQLite (Room) database to allow users to pause, resume, and recover active network transfers even if the app is force-closed or the internet connection drops completely.

## 🚀 Key Features
* **Pause & Resume:** Manually pause and resume large file transfers at any time.
* **Crash Recovery:** Transfers automatically pause if the app is force-closed and can be resumed from the exact byte offset.
* **Network Resilience:** Automatically retries on dropped connections and gracefully fails over to a paused state if the network is lost.
* **Reboot Support:** Automatically restarts pending background transfers when the device reboots.

## 🏗 Architecture & Tech Stack
The application strictly adheres to modern Android architecture principles with a firm separation of concerns:

* **UI Layer (Jetpack Compose):** A reactive, declarative UI that observes a database-backed Kotlin `StateFlow`. It remains completely unaware of network operations, communicating user intent strictly via Android Intents.
* **Service Layer (Foreground Service):** Acts as the execution engine. By operating as a Foreground Service, it ensures active transfers survive UI teardowns and OS background memory limits. It displays a live-progress Notification with actionable controls.
* **Data Layer (Room DB):** Acts as the strict single source of truth. Every chunk transferred updates the local database, ensuring the UI and background service are always perfectly synchronized.
* **Networking (OkHttp):** Handles the I/O streams, custom interceptors, and HTTP headers required for partial file delivery.

## 📡 Transfer Protocol & Chunking
To support massive files without OOM (Out Of Memory) exceptions, the application avoids loading entire files into RAM:
* **Downloads:** OkHttp utilizes the HTTP `Range: bytes={downloadedBytes}-` header to request only the missing portions of a file. Incoming byte streams are piped directly to disk.
* **Uploads:** Files are read from disk in 2MB chunks using Kotlin's `RandomAccessFile` and dispatched via HTTP POST requests using the `Content-Range: bytes START-END/TOTAL` header.

## 🛡️ Edge Cases & Recovery Logic

### 1. Handling Network Drops
The OkHttp client is configured with a custom `RetryInterceptor`. If the connection drops or the server returns transient 503 errors, the interceptor executes exponential backoff retries. If retries are exhausted, the transfer gracefully falls back to a `FAILED` state, allowing the user to manually resume from the saved byte offset.

### 2. Handling Application Termination
If the user force-closes the app, ongoing transfers are abruptly interrupted. Upon the next app initialization, a custom `TransferApplication` class queries the Room DB for any orphaned transfers stuck in the `TRANSFERRING` state and safely reverts them to `PAUSED`.

### 3. Handling Device Reboots
A `BootReceiver` listens for the `ACTION_BOOT_COMPLETED` broadcast. Upon device reboot, it queries the database, identifies interrupted transfers, and automatically spins up the `TransferService` to resume operations in the background.

### 4. Handling Lost Server Acknowledgments (Idempotency)
To handle scenarios where a chunk is successfully received by the server but the HTTP 200 OK response drops over the network, the client transmits an explicit `chunk_index` and byte range with every payload. The server validates this offset before writing, preventing the client's retry logic from duplicating data.

### 5. Data Integrity Verification
A transfer is never assumed complete just because the byte loop finishes. Before transitioning to the `COMPLETED` state, the application cross-verifies that the final assembled file size on disk perfectly matches the `total_bytes` expected by the database.

---

## 🛠️ Installation & Setup

### 1. Run the Python Mock Server
The Android app requires the included local Python server to process the chunked file streams.
```bash
# Navigate to the server directory
cd mock-server

# Install requirements
pip install -r requirements.txt

# Run the server (or use the provided start_server.ps1 script)
uvicorn main:app --host 0.0.0.0 --port 8000
