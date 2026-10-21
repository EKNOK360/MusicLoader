# Copia TODAS las etiquetas de un FLAC a otro (incluida la letra de varias lineas y los generos multiples)
# y le pone la portada indicada (o conserva la del original si no se indica).
# Uso: python copiar-etiquetas.py origen.flac destino.flac [portada.jpg]
import sys
from mutagen.flac import FLAC, Picture

src, dst = FLAC(sys.argv[1]), FLAC(sys.argv[2])
dst.delete(); dst.clear_pictures()
for k in src.keys():
    dst[k.upper()] = src[k]   # en MAYUSCULA como las originales (algunos reproductores no leen minusculas)
if len(sys.argv) > 3:
    p = Picture(); p.type = 3; p.mime = 'image/jpeg'; p.data = open(sys.argv[3], 'rb').read()
    dst.add_picture(p)
else:
    for p in src.pictures:
        dst.add_picture(p)
dst.save()
