"""Check original-file integrity and preservation of shared controller logic."""
from pathlib import Path
import hashlib
import json
import re

new = Path(__file__).resolve().parents[1]
old = new.parent / 'Sdram_Control_4Port'
workspace = new.parents[2]
hashes = json.loads((new / 'original_files_sha256.json').read_text(encoding='utf-8'))
for filename, digest in hashes.items():
    path = workspace / filename
    assert path.is_file(), f'Original file missing: {filename}'
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, f'Original file changed: {filename}'

renames = {
    'Sdram_Control_4Port': 'Sdram_Control_2Port',
    'control_interface': 'control_interface_2port',
    'command': 'command_2port',
    'sdr_data_path': 'sdr_data_path_2port',
    'Sdram_WR_FIFO': 'Sdram_WR_FIFO_2Port',
    'Sdram_RD_FIFO': 'Sdram_RD_FIFO_2Port',
    'Sdram_Params': 'Sdram_2Port_Params',
}

def restore_names(text):
    for before, after in renames.items():
        text = re.sub(r'\b' + after + r'\b', before, text)
    return text

for stem in ['control_interface', 'command', 'sdr_data_path', 'Sdram_WR_FIFO', 'Sdram_RD_FIFO']:
    before = (old / (stem + '.v')).read_text(encoding='utf-8-sig')
    after = (new / (renames[stem] + '.v')).read_text(encoding='utf-8-sig')
    assert restore_names(after) == before, f'Shared helper logic changed: {stem}'
assert (new / 'Sdram_2Port_Params.h').read_bytes() == (old / 'Sdram_Params.h').read_bytes()

before = (old / 'Sdram_Control_4Port.v').read_text(encoding='utf-8-sig')
after = (new / 'Sdram_Control_2Port.v').read_text(encoding='utf-8-sig')
assert not re.search(r'\b(?:WR2\w*|RD2\w*|rWR2_ADDR|rRD2_ADDR|mDATAIN[12]|write_fifo2|read_fifo2)\b', after)
assert len(re.findall(r'\bSdram_WR_FIFO_2Port\s+\w+\s*\(', after)) == 1
assert len(re.findall(r'\bSdram_RD_FIFO_2Port\s+\w+\s*\(', after)) == 1

def shared_sequence(text):
    start = text.index('\talways @(posedge CTRL_CLK) begin')
    end = text.index('//\tInternal Address & Length Control', start)
    return text[start:end]

assert shared_sequence(before) == shared_sequence(after), 'Data/control timing sequence changed'

def ports(text):
    header = text[text.index('module '):text.index(');')]
    header = re.sub(r'//[^\n]*', '', header)
    return re.findall(r'\b[A-Z][A-Z0-9_]*\b', header)

assert ports(after) == [p for p in ports(before) if not p.startswith(('WR2', 'RD2'))]
print(f'PASS: {len(hashes)} original files unchanged; helper logic and parameters preserved;')
print('PASS: only WR2/RD2 interfaces removed; one write FIFO and one read FIFO remain;')
print('PASS: SDRAM pin generation, burst timing and read/write transfer state machine unchanged.')
