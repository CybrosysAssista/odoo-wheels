#!/bin/bash
# Runs inside a verify image. Mirrors setupVirtualEnvironment.ts: the venv's bundled pip (not upgraded),
# one wheel per package (the last in directory order), one `pip install --no-index` call.
set -euo pipefail
python=$1

"python$python" -m venv /venv
cd /wheels
files=$(ls *.whl | awk -F- '{ name = tolower($1); gsub(/[-_.]+/, "-", name); last[name] = $0 } END { for (n in last) print "/wheels/" last[n] }')
/venv/bin/pip install -q --no-index --find-links /wheels $files 2>&1 | grep -v -e 'new release of pip' -e 'pip install --upgrade pip' || true
/venv/bin/pip check >/dev/null || /venv/bin/pip check | head -5

/venv/bin/python - <<'EOF'
import importlib, pathlib, sys, sysconfig
root = pathlib.Path(sysconfig.get_paths()['platlib'])
failed, count = [], 0
for so in sorted(root.rglob('*.so')):
    rel = so.relative_to(root)
    if rel.parts[0].endswith('.libs') or any(p in ('tests', 'test', 'testing') for p in rel.parts):
        continue
    module = '.'.join(rel.parts[:-1] + (rel.name.split('.')[0],))
    count += 1
    try:
        importlib.import_module(module)
    except ModuleNotFoundError as e:
        # Optional parts Odoo uses none of: PIL._imagingtk needs tkinter (not in a bare python package), and
        # gevent's cffi loops need cffi, which only loads when GEVENT_LOOP asks for them (default is libev's C loop).
        if not (e.name == 'tkinter' or (e.name == '_cffi_backend' and module.startswith('gevent.'))):
            failed.append(f'{module}: {type(e).__name__}: {e}')
    except Exception as e:
        failed.append(f'{module}: {type(e).__name__}: {e}')
for line in failed:
    print('import failed:', line)
print(f'pip {__import__("pip").__version__}, {count - len(failed)}/{count} compiled modules import')
sys.exit(1 if failed else 0)
EOF
