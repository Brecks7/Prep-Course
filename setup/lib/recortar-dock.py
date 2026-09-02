#!/usr/bin/env python3
"""Recorta una captura del sandbox a la zona del dock.

`medir-dock` sabe encontrar el dock cuando el fondo es parejo, pero la captura
del shell headless trae fondo de escritorio y barra superior, y ahí el detector
se queda con toda la pantalla. Las coordenadas exactas ya las imprimió el probe,
así que se usan esas: `[probe] container WxH @X,Y`.

    recortar-dock.py <captura.png> <log-con-lineas-probe>
"""
import re
import sys

from PIL import Image

png, log = sys.argv[1], sys.argv[2]
m = None
for linea in open(log, errors="replace"):
    hallado = re.search(r"\[probe\] container (\d+)x(\d+) @(-?\d+),(-?\d+)", linea)
    if hallado:
        m = hallado
if not m:
    sys.exit("no encontré la geometría del dock en el log")

w, h, x, y = (int(g) for g in m.groups())
margen = 14
im = Image.open(png)
im.crop((max(0, x - margen), max(0, y - margen),
         min(im.width, x + w + margen), min(im.height, y + h + margen))).save(png)
print(f"recortado a {w}x{h} en ({x},{y}) con {margen}px de margen")
