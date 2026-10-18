# Pasa una letra LRC en japones o coreano a letras latinas (romaji Hepburn / romanizacion revisada). NO traduce.
# Japones con cutlet (diccionario MeCab/UniDic: separa bien las palabras y lee los kanji segun el contexto).
# Los tiempos [mm:ss.xx] se conservan; las lineas que ya estan en letras latinas no se tocan.
# Uso: python romanizar.py entrada.lrc salida.lrc        Prueba: python romanizar.py --prueba
import re, sys
import cutlet
from korean_romanizer.romanizer import Romanizer

kat = cutlet.Cutlet()                # Hepburn
kat.use_foreign_spelling = False     # katakana como se pronuncia, no "corregido" al ingles
JA = re.compile(r'[぀-ヿ㐀-鿿ｦ-ﾟ]')
KO = re.compile(r'[가-힯ᄀ-ᇿ㄰-㆏]+')
TAG = re.compile(r'^((?:\[[^\]]*\])*)(.*)$')

def texto(s):
    if KO.search(s):
        s = KO.sub(lambda m: Romanizer(m.group(0)).romanize(), s)
    if JA.search(s):
        s = kat.romaji(s.replace('　', ' '))
    return s

def lrc(t):
    return '\n'.join(TAG.match(l).group(1) + texto(TAG.match(l).group(2)) for l in t.split('\n'))

if sys.argv[1:] == ['--prueba']:
    r = lrc('[00:01.00]夜に駆ける\n[00:02.00]Hello world\n[00:03.00]사랑해\n[00:04.00]正しさとは 愚かさとは')
    assert r.startswith('[00:01.00]Yoru ni kakeru'), r
    assert '[00:02.00]Hello world' in r and '[00:03.00]saranghae' in r, r
    assert '[00:04.00]Tadashisa to wa orokasa to wa' in r, r
    print('prueba OK')
else:
    ent = open(sys.argv[1], encoding='utf-8').read()
    open(sys.argv[2], 'w', encoding='utf-8').write(lrc(ent))
