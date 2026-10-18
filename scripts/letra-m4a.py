# Lee o escribe SOLO la letra (atomo ©lyr) de un M4A, sin re-codificar: el audio y la portada no se tocan.
# Uso: python letra-m4a.py leer archivo.m4a          -> imprime la letra (UTF-8)
#      python letra-m4a.py escribir archivo.m4a x.lrc -> pone la letra de x.lrc
import sys
from mutagen.mp4 import MP4

modo, ruta = sys.argv[1], sys.argv[2]
m = MP4(ruta)
if modo == 'leer':
    sys.stdout.buffer.write('\n'.join(m.tags.get('\xa9lyr', [''])).encode('utf-8'))
elif modo == 'escribir':
    m.tags['\xa9lyr'] = [open(sys.argv[3], encoding='utf-8').read()]
    m.save()
