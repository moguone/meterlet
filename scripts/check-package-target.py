#!/usr/bin/env python3
"""Do not replace an application that is currently being tested or used."""
import pathlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
executable = str(app / 'Contents/MacOS/Meterlet')
commands = subprocess.check_output(['ps', '-axo', 'comm='], text=True).splitlines()
if executable in (command.strip() for command in commands):
    sys.exit(f'{app} is running. Quit it first, or choose a different OUTPUT_DIR.')
