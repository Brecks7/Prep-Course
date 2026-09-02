#!/usr/bin/env python3
"""Engancha probe-dock.js al final del enable() de una extensión, en la copia
del sandbox. Se hace acá y no a mano porque el enable() de cada extensión es
distinto y el regex tiene que agarrar la llave que cierra, no la primera."""
import re
import sys

ruta, salida = sys.argv[1], sys.argv[2]
s = open(ruta).read()
s = 'import { arm as __probe } from "./probe-dock.js";\n' + s
s, n = re.subn(
    r"(\n    enable\(\) \{.*?)(\n    \})",
    lambda m: f'{m.group(1)}\n        __probe(this, "{salida}", 5);{m.group(2)}',
    s, count=1, flags=re.S)
if n == 0:
    sys.exit("no encontré un enable() donde enganchar el probe")
open(ruta, "w").write(s)
