# Pasa una letra LRC en japones o coreano a letras latinas (romaji / romanizacion revisada). NO traduce.
# Los tiempos [mm:ss.xx] se conservan; las lineas que ya estan en letras latinas no se tocan.
# Uso: python romanizar.py entrada.lrc salida.lrc        Prueba: python romanizar.py --prueba
import re, sys
import pykakasi
from korean_romanizer.romanizer import Romanizer

kks = pykakasi.kakasi()
JA = re.compile(r'[぀-ヿ㐀-鿿ｦ-ﾟ]')
KO = re.compile(r'[가-힯ᄀ-ᇿ㄰-㆏]+')
HIRA = re.compile(r'[぀-ゟ]+')
KANJI = re.compile(r'[㐀-鿿]')
PART = {'は', 'が', 'を', 'に', 'で', 'と', 'の', 'も', 'へ', 'や', 'か', 'ね', 'よ', 'な', 'さ', 'ぞ', 'わ', 'から', 'まで', 'より', 'だけ', 'って'}
TAG = re.compile(r'^((?:\[[^\]]*\])*)(.*)$')

def texto(s):
    if KO.search(s):
        s = KO.sub(lambda m: Romanizer(m.group(0)).romanize(), s)
    if JA.search(s):
        out = []; prev = ''
        for p in kks.convert(s):
            h = p['hepburn'].strip(); o = p['orig']
            if not h: prev = o; continue
            # terminacion de verbo/adjetivo (okurigana) va pegada al kanji: 駆ける -> kakeru; las particulas van separadas
            if out and HIRA.fullmatch(o) and len(o) <= 2 and KANJI.search(prev) and o not in PART:
                out[-1] += h
            else:
                out.append(h)
            prev = o
        s = ' '.join(out)
        s = re.sub(r'\s+([,.!?、。」』）)])', r'\1', s).replace('、', ',').replace('。', '.')
    return s

def lrc(t):
    return '\n'.join(TAG.match(l).group(1) + texto(TAG.match(l).group(2)) for l in t.split('\n'))

if sys.argv[1:] == ['--prueba']:
    r = lrc('[00:01.00]夜に駆ける\n[00:02.00]Hello world\n[00:03.00]사랑해')
    assert r.startswith('[00:01.00]yoru ni kakeru'), r
    assert '[00:02.00]Hello world' in r and '[00:03.00]saranghae' in r, r
    print('prueba OK')
else:
    ent = open(sys.argv[1], encoding='utf-8').read()
    open(sys.argv[2], 'w', encoding='utf-8').write(lrc(ent))
