import os
import sys

# Fix for PyInstaller noconsole crash
log_file = open('server.log', 'w', encoding='utf-8')
sys.stdout = log_file
sys.stderr = log_file

from flask import Flask, request, jsonify, send_file
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

UPLOAD_FOLDER = os.path.abspath("uploads")
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# ---------------- UPLOAD SYSTEM ----------------
@app.route('/upload-chunk', methods=['POST'])
def upload_chunk():
    file_id = request.form.get('file_id')
    chunk_index = int(request.form.get('chunk_index'))
    total_chunks = int(request.form.get('total_chunks'))
    original_name = request.form.get('original_name')
    total_size = int(request.form.get('total_size'))
    chunk_file = request.files.get('file')

    chunk_path = os.path.join(UPLOAD_FOLDER, f"{file_id}_part_{chunk_index}")
    chunk_file.save(chunk_path)

    if chunk_index == total_chunks - 1:
        temp_final_path = os.path.join(UPLOAD_FOLDER, f"{file_id}.temp")
        with open(temp_final_path, 'wb') as outfile:
            for i in range(total_chunks):
                part = os.path.join(UPLOAD_FOLDER, f"{file_id}_part_{i}")
                with open(part, 'rb') as infile:
                    outfile.write(infile.read())
                os.remove(part)

        actual_size = os.path.getsize(temp_final_path)
        if actual_size == total_size:
            final_path = os.path.join(UPLOAD_FOLDER, original_name)
            os.replace(temp_final_path, final_path)
            return jsonify({"status": "success", "message": "Verified"}), 200
        else:
            os.remove(temp_final_path)
            return jsonify({"status": "error", "message": "Integrity failed"}), 400

    return jsonify({"status": "success"}), 200


# ---------------- DOWNLOAD SYSTEM ----------------
@app.route('/list-files', methods=['GET'])
def list_files():
    files = []
    for f in os.listdir(UPLOAD_FOLDER):
        if not f.endswith('.temp') and not '_part_' in f:
            path = os.path.join(UPLOAD_FOLDER, f)
            files.append({'name': f, 'size': os.path.getsize(path)})
    return jsonify(files)

from flask import send_from_directory
import urllib.parse

@app.route('/download/<path:filename>', methods=['GET'])
def download_file(filename):
    print(f"RAW FILENAME: {filename}")
    filename = urllib.parse.unquote(filename)
    print(f"UNQUOTED FILENAME: {filename}")
    full_path = os.path.join(UPLOAD_FOLDER, filename)
    print(f"FULL PATH: {full_path}")
    print(f"EXISTS: {os.path.exists(full_path)}")
    if not os.path.exists(full_path):
        return "File not found", 404
    return send_from_directory(UPLOAD_FOLDER, filename, conditional=True)

@app.route('/delete/<path:filename>', methods=['DELETE'])
def delete_file(filename):
    file_path = os.path.join(UPLOAD_FOLDER, filename)
    if os.path.exists(file_path):
        try:
            os.remove(file_path)
            return jsonify({"status": "success"}), 200
        except Exception as e:
            return jsonify({"status": "error", "message": str(e)}), 500
    else:
        return jsonify({"status": "error", "message": "File not found"}), 404

@app.route('/delete-all', methods=['DELETE'])
def delete_all_files():
    try:
        for filename in os.listdir(UPLOAD_FOLDER):
            file_path = os.path.join(UPLOAD_FOLDER, filename)
            if os.path.isfile(file_path):
                os.remove(file_path)
        return jsonify({"status": "success", "message": "All files deleted"}), 200
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

import argparse
import threading
import time
import subprocess

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--parent-pid', type=int, help='PID of the parent process')
    args, unknown = parser.parse_known_args()

    if args.parent_pid:
        import psutil
        import threading
        import time
        def watchdog():
            while True:
                exists = psutil.pid_exists(args.parent_pid)
                if not exists:
                    print(f"Exiting because parent PID {args.parent_pid} does not exist", flush=True)
                    os._exit(0)
                time.sleep(2)
        threading.Thread(target=watchdog, daemon=True).start()

    app.run(debug=False, port=5000)