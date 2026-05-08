#!/usr/bin/env -S uv run --with Levenshtein python
import json, sys, os, subprocess, shlex
from pathlib import Path
import platform
from Levenshtein import ratio

CONFIG=".config"
if platform.system() == "Darwin":
    CONFIG="Library/Application Support"

memfile=Path(f"~/{CONFIG}/sidechat").expanduser() / "memories.json"

def rpc(data):
    print(json.dumps({"jsonrpc": "2.0", "result": data}), flush=True)

for res in sys.stdin: 
    input_data = json.loads(res)
    if input_data['method'] == 'initialize':
        rpc({
            "protocolVersion":"2024-11-05",
            "capabilities": {
                "tools":{"listChanged":True},"resources":{"listChanged":True},"completions":{}
            },
            "serverInfo":{"name":"demo", "version":"1.0.0"}
        })

    if input_data['method'] == 'tools/call':
        params = input_data.get('params')
        tool_name = params['name']
        args = params.get('arguments', {})
        break


if tool_name == "list_files":
    DIR = Path(args.get('path') or '.').expanduser()
    rpc([f.name for f in DIR.glob("*")])

elif tool_name == "create_file":
    file_path = Path(args.get('path') or '.').expanduser()
    if file_path.exists():
        rpc({
            "ok": False,
            "reason": f"path {file_path} already exists"
            })
        sys.exit(0)

    fd = os.open(file_path, os.O_CREAT | os.O_WRONLY)
    rpc({"ok": True, "message": f"File created: {file_path}"})

elif tool_name == "edit_file":
    file_path = Path(args.get('path') or '.').expanduser() 
    line_start = args.get('line_start')
    line_end = args.get('line_end')
    old_content = args.get('old_content')
    new_content = args.get('new_content')
    
    try:
        with open(file_path, 'r') as f:
            lines = f.readlines()
        
        # Validate line range and fetch content
        if line_start < 1 or line_end > len(lines) or line_start > line_end:
            rpc({
                "ok": False,
                "reason": f"Invalid line range: line_start={line_start}, line_end={line_end}, total_lines={len(lines)}"
            })
            sys.exit(0)
        
        # Get the actual content being edited
        lines_in_range = ''.join(lines[line_start - 1:line_end])

        similarity = ratio(lines_in_range, old_content)
        
        # Verify content matches (sanity check)
        if similarity < 0.8:
            rpc({
                "ok": False,
                "reason": "Content mismatch. Reread the file",
                "line_start": line_start,
                "line_end": line_end,
                "similarity": similarity,
                "expected": old_content[:100],  # partial view for debugging
                "actual": lines_in_range[:100]
            })
            sys.exit(0)
        
        # Perform the edit
        lines[line_start - 1:line_end] = [new_content + '\n'] if line_start == line_end else [new_content + '\n'] + lines[line_end:]
        
        with open(file_path, 'w') as f:
            f.writelines(lines)
        
        rpc({
            "ok": True,
            "path": str(file_path),
            "line_start": line_start,
            "line_end": line_end,
            "similarity": similarity,
            "old_length": line_end - line_start + 1,
            "new_length": 1 if line_start == line_end else len(lines[line_end:]) + 1
        })

    except Exception as e:
        rpc({
            "ok": False,
            "error": str(e),
            "path": str(file_path)
        })

elif tool_name == "run_cmd":
    torun = args.get("cmd")
    forbidden_words = {"rm", "sudo", "dd", "unlink", "shutdown"}
    cmdlist = shlex.split(torun)

    for token in cmdlist:
        if any(token == word or token.startswith(word + " ") for word in forbidden_words):
            rpc({
                "ok": False,
                "reason": f"Destructive commands prohibited. You will be fired for removing files or trying to get sudo privileges"
            })
            sys.exit(0)

    try:
        res = subprocess.run(
            torun,
            capture_output=True,
            text=True,
            shell=True)

        rpc({
            "ok": True,
            "stdout": res.stdout,
            "stderr": res.stderr,
        })

    except Exception as e:
        rpc({"ok": False, "error": str(e)})


elif tool_name == "read_file":
    file_path = Path(args.get('path') or '.').expanduser()
    line_start = args.get('line_start')
    line_end = args.get('line_end')
    
    try:
        with open(file_path, 'r') as f:
            lines = f.readlines()
        
        # Handle line range
        total_lines = len(lines)
        if line_start is not None or line_end is not None:
            # Default values if not provided
            start = line_start if line_start is not None else 1
            end = line_end if line_end is not None else total_lines
            
            # Validate line range
            if start < 1 or end > total_lines or start > end:
                rpc({
                    "ok": False,
                    "reason": f"Invalid line range: line_start={start}, line_end={end}, total_lines={total_lines}"
                })
                sys.exit(0)
            
            # Slice lines to requested range
            lines = lines[start - 1:end]
            line_offset = start - 1
        else:
            line_offset = 0
        
        formatted_lines = []
        for i, line in enumerate(lines, 1 + line_offset):
            formatted_lines.append(f"<line number={i}>{line}</line>")
        
        rpc("".join(formatted_lines))
    except Exception as e:
        rpc({
            "ok": False,
            "error": str(e),
            "path": str(file_path)
        })

elif tool_name == "read_pydoc":
    rpc(subprocess.run(
        ["pydoc", args['object']],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False      
    ).stdout)

elif tool_name == "read_man_section":
    rpc(subprocess.run(
        ["mansnip", "--llm", args['manpage'], args['section']],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False      
    ).stdout)

elif "memory" in tool_name:
    fd = os.open(memfile, os.O_RDONLY | os.O_CREAT, mode=0o644)
    with os.fdopen(fd, 'r') as f:
        try:
            mems = json.load(f)
        except:
            mems = []

    if tool_name == "show_memory":
        rpc(mems)

    # this is save memory
    else:
        mems.append(args.get('memory'))
        with open(memfile, 'w') as f:
            json.dump(mems,f, indent=2)

        rpc({"ok": True})

