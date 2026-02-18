"""
Celowo podatna aplikacja do testów bezpieczeństwa
⚠️ NIE UŻYWAJ W PRODUKCJI!
"""
import os
import subprocess
import pickle
import yaml
from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = '/tmp/uploads'

@app.route('/')
def index():
    return jsonify({"message": "Vulnerable App - DO NOT USE IN PRODUCTION"})

@app.route('/exec', methods=['POST'])
def exec_command():
    """Vulnerability: Command Injection"""
    cmd = request.json.get('command', '')
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return jsonify({"output": result.stdout, "error": result.stderr})

@app.route('/eval', methods=['POST'])
def eval_code():
    """Vulnerability: Code Injection"""
    code = request.json.get('code', '')
    result = eval(code)
    return jsonify({"result": str(result)})

@app.route('/pickle', methods=['POST'])
def unpickle():
    """Vulnerability: Insecure Deserialization"""
    data = request.get_data()
    obj = pickle.loads(data)
    return jsonify({"unpickled": str(obj)})

@app.route('/yaml', methods=['POST'])
def parse_yaml():
    """Vulnerability: YAML Deserialization"""
    yaml_data = request.get_data(as_text=True)
    obj = yaml.load(yaml_data, Loader=yaml.Loader)
    return jsonify({"parsed": str(obj)})

@app.route('/upload', methods=['POST'])
def upload_file():
    """Vulnerability: Path Traversal"""
    if 'file' not in request.files:
        return jsonify({"error": "No file"}), 400
    file = request.files['file']
    filename = file.filename  # Brak użycia secure_filename
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    file.save(filepath)
    return jsonify({"saved": filepath})

@app.route('/env', methods=['GET'])
def show_env():
    """Vulnerability: Information Disclosure"""
    return jsonify(dict(os.environ))

@app.route('/sql', methods=['POST'])
def sql_query():
    """Vulnerability: SQL Injection (mock)"""
    query = request.json.get('query', '')
    # Symulacja SQL injection
    return jsonify({"query": query, "vulnerable": True})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
