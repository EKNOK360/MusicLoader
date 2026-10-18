# Pasa una letra LRC en japones o coreano a letras latinas (romaji Hepburn / romanizacion revisada). NO traduce.
# Japones con cutlet (diccionario MeCab/UniDic: separa bien las palabras y lee los kanji segun el contexto).
# Los tiempos [mm:ss.xx] se conservan; las lineas que ya estan en letras latinas no se tocan.
# Uso: python romanizar.py entrada.lrc salida.lrc        Prueba: python romanizar.py --prueba
import re, sys
import cutlet
from korean_romanizer.romanizer import Romanizer

import os
kat = cutlet.Cutlet()                # Hepburn
kat.use_foreign_spelling = True      # palabras de otro idioma en katakana van en su idioma: シャンデリア -> chandelier
# lecturas especiales que el diccionario no conoce (titulos con lectura propia). Se pueden agregar mas en
# %USERPROFILE%\reportes-musica\romaji-manual.txt, una por linea:  original|romaji
MANUAL = {'紅蓮華': 'Gurenge', '唱': 'Show'}
_m = os.path.join(os.environ.get('USERPROFILE', ''), 'reportes-musica', 'romaji-manual.txt')
if os.path.exists(_m):
    for _l in open(_m, encoding='utf-8'):
        if '|' in _l:
            _o, _r = _l.rstrip('\n').split('|', 1); MANUAL[_o.strip()] = _r.strip()
MAN = re.compile('|'.join(sorted(map(re.escape, MANUAL), key=len, reverse=True))) if MANUAL else None

def japones(s):  # las lecturas manuales se respetan; lo demas pasa por cutlet
    if not MAN:
        return kat.romaji(s)
    out, i = [], 0
    for m in MAN.finditer(s):
        if s[i:m.start()].strip(): out.append(kat.romaji(s[i:m.start()]))
        out.append(MANUAL[m.group(0)]); i = m.end()
    if s[i:].strip(): out.append(kat.romaji(s[i:]))
    return ' '.join(out)
JA = re.compile(r'[぀-ヿ㐀-鿿ｦ-ﾟ]')
KO = re.compile(r'[가-힯ᄀ-ᇿ㄰-㆏]+')
TAG = re.compile(r'^((?:\[[^\]]*\])*)(.*)$')

def texto(s):
    if KO.search(s):
        s = KO.sub(lambda m: Romanizer(m.group(0)).romanize(), s)
    if JA.search(s):
        s = japones(s.replace('　', ' '))
    return s

def lrc(t):
    return '\n'.join(TAG.match(l).group(1) + texto(TAG.match(l).group(2)) for l in t.split('\n'))

if sys.argv[1:] == ['--prueba']:
    r = lrc('[00:01.00]夜に駆ける\n[00:02.00]Hello world\n[00:03.00]사랑해\n[00:04.00]正しさとは 愚かさとは')
    assert r.startswith('[00:01.00]Yoru ni kakeru'), r
    assert '[00:02.00]Hello world' in r and '[00:03.00]saranghae' in r, r
    assert '[00:04.00]Tadashisa to wa orokasa to wa' in r, r
    assert lrc('[00:05.00]ギラギラ光るシャンデリア') == '[00:05.00]Giragira hikaru chandelier', lrc('[00:05.00]ギラギラ光るシャンデリア')
    assert lrc('紅蓮華') == 'Gurenge' and lrc('唱') == 'Show', (lrc('紅蓮華'), lrc('唱'))
    print('prueba OK')
else:
    ent = open(sys.argv[1], encoding='utf-8').read()
    open(sys.argv[2], 'w', encoding='utf-8').write(lrc(ent))
