import subprocess
import os
import sys

def main():
    # Get the directory where THIS launcher is located
    if getattr(sys, 'frozen', False):
        current_dir = os.path.dirname(sys.executable)
    else:
        current_dir = os.path.dirname(os.path.abspath(__file__))

    server_path = os.path.join(current_dir, "server.exe")
    flutter_path = os.path.join(current_dir, "file_transfer_app.exe")

    if not os.path.exists(server_path) or not os.path.exists(flutter_path):
        import ctypes
        ctypes.windll.user32.MessageBoxW(0, f"Could not find server.exe or file_transfer_app.exe in {current_dir}", "Startup Error", 0)
        return

    # Start the backend server hidden in the background
    CREATE_NO_WINDOW = 0x08000000
    server_process = subprocess.Popen([server_path], creationflags=CREATE_NO_WINDOW)

    try:
        # Run the Flutter UI and wait for the user to close it
        subprocess.run([flutter_path])
    finally:
        # Guarantee the background server is killed when the UI is closed
        server_process.terminate()

if __name__ == '__main__':
    main()
