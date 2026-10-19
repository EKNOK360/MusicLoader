# Lee o escribe SOLO la letra de un M4A (atomo ©lyr) o MP3 (ID3 USLT), sin re-codificar: el audio y la portada no se tocan.
# Uso: python letra-tag.py leer archivo          -> imprime la letra (UTF-8)
#      python letra-tag.py escribir archivo x.lrc -> pone la letra de x.lrc
import sys

#      python letra-tag.py titulo-leer archivo / titulo-escribir archivo x.txt  -> lo mismo con el titulo
modo, ruta = sys.argv[1], sys.argv[2]
nueva = open(sys.argv[3], encoding='utf-8').read() if modo.endswith('escribir') else None

if modo.startswith('titulo'):
    from mutagen.mp3 import EasyMP3
    from mutagen.easymp4 import EasyMP4
    m = EasyMP3(ruta) if ruta.lower().endswith('.mp3') else EasyMP4(ruta)
    if modo == 'titulo-leer':
        sys.stdout.buffer.write(''.join(m.get('title', [''])).encode('utf-8'))
    else:
        m['title'] = [nueva.strip()]
        m.save()
    sys.exit(0)

if ruta.lower().endswith('.mp3'):
    from mutagen.id3 import ID3, USLT, ID3NoHeaderError
    try:
        t = ID3(ruta)
    except ID3NoHeaderError:
        t = ID3()
    if modo == 'leer':
        u = t.getall('USLT')
        # si hay varias, la sincronizada primero
        u.sort(key=lambda x: '[0' not in x.text)
        sys.stdout.buffer.write((u[0].text if u else '').encode('utf-8'))
    else:
        t.delall('USLT')
        # reproductores viejos: ID3v2.3 con la letra en Latin-1 (el "ANSI" clasico); si no cabe (japones...), UTF-16
        try:
            nueva.encode('latin-1'); cod = 0
        except UnicodeEncodeError:
            cod = 1
        t.add(USLT(encoding=cod, lang='spa', desc='', text=nueva))
        t.save(ruta, v2_version=3)
else:
    from mutagen.mp4 import MP4
    m = MP4(ruta)
    if modo == 'leer':
        sys.stdout.buffer.write('\n'.join(m.tags.get('\xa9lyr', [''])).encode('utf-8'))
    else:
        m.tags['\xa9lyr'] = [nueva]
        m.save()
