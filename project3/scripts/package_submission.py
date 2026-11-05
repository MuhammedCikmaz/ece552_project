#!/usr/bin/env python3
"""Package only required deliverables, with no folder hierarchy or testbench."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
files = sorted((root/'rtl').glob('*.v'))
files += [root/'schematic.pdf']
files += [root/f'{kind}_type_schematic.pdf' for kind in 'risbuj']
files += [root/'project3.txt']
for path in files:
    if not path.is_file():
        raise SystemExit(f'Missing required file: {path}')
archive = root/'submission.zip'
with ZipFile(archive, 'w', ZIP_DEFLATED) as output:
    for path in files:
        output.write(path, arcname=path.name)
print(f'Packaged {len(files)} files into {archive}')
if 'TODO' in (root/'project3.txt').read_text():
    print('Group names are still missing: fill project3.txt and regenerate the archive before uploading.')
