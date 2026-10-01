#!/usr/bin/env python3
"""
Ferramenta de pós-processamento das fotos de AMOSTRA/PARCELA (GeoForest Analytics).

Irmã do tools/marca_dagua_bio/marcar_fotos.py, mas pra fotos da parcela em si
(tiradas antes de começar a coleta, com o cabeçalho da amostra: projeto,
atividade, fazenda, talhão, coordenada etc.) em vez de fotos de árvore
individual. Mesma ideia: roda no computador, não no celular, porque desenhar
texto em cima do bitmap inteiro é pesado pra rodar no app.

Diferente do modo BIO, aqui não existe "espécie pendente de classificar" —
é só ler o que o app já gravou (nome do arquivo + EXIF) e marcar direto,
numa etapa só:

    python3 marcar_fotos_amostra.py marcar --pasta /caminho/das/fotos

Se quiser só conferir os dados antes de marcar, rode 'extrair' primeiro pra
gerar um CSV de conferência (não mexe nas fotos):

    python3 marcar_fotos_amostra.py extrair --pasta /caminho/das/fotos

Instalação:
  pip install -r requirements.txt
"""

import argparse
import csv
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

EXTENSOES_VALIDAS = {".jpg", ".jpeg", ".png"}
NOME_CSV_PADRAO = "fotos_amostra.csv"

# Rótulos da empresa, impressos na coluna direita da marca d'água.
EMPRESA_NOME = "Geo Forest Analytics"
EMPRESA_EMAIL = "geoforestanalytics@gmail.com"
EMPRESA_TELEFONE = "+55 15 98140-9153"
CAMINHO_LOGO = Path(__file__).parent / "logo.png"

# Nome gravado pelo app: PARC_<talhao>_P<parcela>_<timestamp_ms>.jpg
# (ver lib/pages/amostra/coleta_dados_page.dart, método _pickImage)
PADRAO_NOME = re.compile(
    r'^PARC_(?P<talhao>.+)_P(?P<parcela>[^_]+)_(?P<timestamp>\d{10,})\.\w+$',
    re.IGNORECASE,
)

# O campo UTM do app vem com um "|" embutido dentro do próprio valor
# ("UTM: E: 123 N: 456 | Zona 22S | Lider: ..."), então não dá pra separar o
# comentário inteiro só no "|" — precisa capturar esse trecho à parte, indo
# até o próximo rótulo conhecido (Lider:).
PADRAO_UTM_COMPLETO = re.compile(r'UTM:\s*(.+?)\s*\|\s*Lider:', re.IGNORECASE)
PADRAO_EASTING_NORTHING = re.compile(r'E:\s*(-?\d+(?:\.\d+)?)\s+N:\s*(-?\d+(?:\.\d+)?)')

CAMPOS_CSV = [
    "id", "arquivo",
    "projeto", "atividade", "fazenda", "talhao", "parcela",
    "Easting", "Northing", "utm",
    "lider", "data_coleta", "comentario_exif_bruto",
]


# ───────────────────────────── Leitura EXIF / nome de arquivo ─────────────────────────────

def decodificar_user_comment(bruto):
    """EXIF UserComment pode vir com um prefixo de 8 bytes indicando o charset
    (padrão EXIF) ou, dependendo da lib que gravou, como texto puro. Tenta os
    formatos mais comuns antes de desistir."""
    if bruto is None:
        return None
    if isinstance(bruto, str):
        texto = bruto.strip("\x00").strip()
        return texto or None
    if isinstance(bruto, bytes):
        prefixos = {
            b"ASCII\x00\x00\x00": "ascii",
            b"UNICODE\x00": "utf-16-be",
            b"\x00\x00\x00\x00\x00\x00\x00\x00": "utf-8",
        }
        for prefixo, codificacao in prefixos.items():
            if bruto.startswith(prefixo):
                try:
                    texto = bruto[len(prefixo):].decode(codificacao, errors="replace")
                    texto = texto.strip("\x00").strip()
                    if texto:
                        return texto
                except Exception:
                    pass
        for codificacao in ("utf-8", "utf-16-le", "latin-1"):
            try:
                texto = bruto.decode(codificacao, errors="replace").strip("\x00").strip()
                if texto:
                    return texto
            except Exception:
                continue
    return None


def ler_user_comment(caminho):
    try:
        with Image.open(caminho) as img:
            exif = img.getexif()
            if not exif:
                return None
            try:
                exif_ifd = exif.get_ifd(0x8769)
                if 0x9286 in exif_ifd:
                    texto = decodificar_user_comment(exif_ifd[0x9286])
                    if texto:
                        return texto
            except Exception:
                pass
            if 0x9286 in exif:
                return decodificar_user_comment(exif[0x9286])
    except Exception as e:
        print(f"  aviso: não consegui ler EXIF de {caminho.name}: {e}")
    return None


def parsear_comentario(texto):
    """'Projeto: X | Atividade: Y | Fazenda: Z | Talhao: W | Parcela: V |
    UTM: E: 1 N: 2 | Zona 22S | Lider: L | Data: dd/MM/yyyy HH:mm:ss' -> dict.

    O campo UTM é tratado à parte (ver PADRAO_UTM_COMPLETO) porque tem um "|"
    dentro do próprio valor — dividir ingenuamente por "|" quebraria ele.
    """
    campos = {}
    if not texto:
        return campos

    m_utm = PADRAO_UTM_COMPLETO.search(texto)
    if m_utm:
        campos["utm"] = m_utm.group(1).strip()
        texto = texto[:m_utm.start()] + texto[m_utm.end() - len("Lider:"):]

    for parte in texto.split("|"):
        if ":" in parte:
            chave, valor = parte.split(":", 1)
            chave = chave.strip().lower()
            if chave == "utm" and "utm" in campos:
                continue  # já capturado acima, com o valor completo
            campos[chave] = valor.strip()
    return campos


def extrair_easting_northing(utm_texto):
    if not utm_texto:
        return "", ""
    m = PADRAO_EASTING_NORTHING.search(utm_texto)
    if not m:
        return "", ""
    return m.group(1), m.group(2)


def extrair_do_nome_arquivo(nome):
    m = PADRAO_NOME.match(nome)
    if not m:
        return {}
    d = m.groupdict()
    return {
        "talhao_arquivo": d.get("talhao"),
        "parcela_arquivo": d.get("parcela"),
    }


def listar_fotos(pasta):
    return sorted(
        f for f in Path(pasta).iterdir()
        if f.is_file() and f.suffix.lower() in EXTENSOES_VALIDAS
    )


# ───────────────────────────────── Etapa 1: extrair CSV (opcional, só conferência) ─────────

def escrever_csv(csv_path, linhas):
    with open(csv_path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=CAMPOS_CSV, delimiter=";")
        writer.writeheader()
        writer.writerows(linhas)


def montar_linha_csv(i, foto):
    comentario = ler_user_comment(foto)
    campos_exif = parsear_comentario(comentario)
    campos_nome = extrair_do_nome_arquivo(foto.name)

    projeto = campos_exif.get("projeto") or ""
    atividade = campos_exif.get("atividade") or ""
    fazenda = campos_exif.get("fazenda") or ""
    talhao = campos_exif.get("talhao") or campos_nome.get("talhao_arquivo") or ""
    parcela = campos_exif.get("parcela") or campos_nome.get("parcela_arquivo") or ""
    utm = campos_exif.get("utm") or ""
    lider = campos_exif.get("lider") or ""
    data = campos_exif.get("data") or ""

    easting, northing = extrair_easting_northing(utm)

    return {
        "id": i,
        "arquivo": foto.name,
        "projeto": projeto,
        "atividade": atividade,
        "fazenda": fazenda,
        "talhao": talhao,
        "parcela": parcela,
        "Easting": easting,
        "Northing": northing,
        "utm": utm,
        "lider": lider,
        "data_coleta": data,
        "comentario_exif_bruto": comentario or "",
    }


def extrair(pasta, csv_path):
    pasta = Path(pasta)
    fotos = listar_fotos(pasta)

    if not fotos:
        print(f"Nenhuma foto encontrada em {pasta}")
        return

    linhas = []
    for i, foto in enumerate(fotos, start=1):
        linha = montar_linha_csv(i, foto)
        linhas.append(linha)
        print(f"  {i:>3}: {foto.name} -> {linha['projeto']} | {linha['atividade']} | Parcela {linha['parcela']}")

    escrever_csv(csv_path, linhas)
    print(f"\n{len(linhas)} foto(s) listada(s) em {csv_path}")


# ───────────────────────────────── Etapa 2: marcar fotos ─────────────────────────────────

def carregar_fonte(tamanho, negrito=False):
    candidatos = [
        "DejaVuSans-Bold.ttf" if negrito else "DejaVuSans.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if negrito else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if negrito else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "C:\\Windows\\Fonts\\arialbd.ttf" if negrito else "C:\\Windows\\Fonts\\arial.ttf",
    ]
    for caminho in candidatos:
        try:
            return ImageFont.truetype(caminho, tamanho)
        except Exception:
            continue
    return ImageFont.load_default()


_CACHE_LOGO = {}


def carregar_logo(altura_alvo):
    """Carrega logo.png (ícone da árvore, já recortado) e redimensiona mantendo
    a proporção. Cacheia por altura pra não reabrir/redimensionar a cada foto."""
    if altura_alvo in _CACHE_LOGO:
        return _CACHE_LOGO[altura_alvo]
    if not CAMINHO_LOGO.exists():
        _CACHE_LOGO[altura_alvo] = None
        return None
    try:
        logo = Image.open(CAMINHO_LOGO).convert("RGBA")
        largura_alvo = int(logo.width * (altura_alvo / logo.height))
        logo = logo.resize((max(1, largura_alvo), altura_alvo), Image.LANCZOS)
    except Exception:
        logo = None
    _CACHE_LOGO[altura_alvo] = logo
    return logo


def desenhar_marca_dagua(img, titulo, linhas_subtitulo, linhas_direita=None):
    img = img.convert("RGB")
    largura, altura = img.size

    fonte_titulo = carregar_fonte(max(18, largura // 32), negrito=True)
    fonte_subtitulo = carregar_fonte(max(13, largura // 48))

    draw = ImageDraw.Draw(img, "RGBA")
    padding = max(10, largura // 80)

    linhas_esq = [(titulo, fonte_titulo)] if titulo else []
    for texto_sub in linhas_subtitulo:
        if texto_sub:
            linhas_esq.append((texto_sub, fonte_subtitulo))

    textos_dir = [texto for texto in (linhas_direita or []) if texto]

    if not linhas_esq and not textos_dir:
        return img

    def altura_bloco(linhas):
        h = 0
        for texto, fonte in linhas:
            bbox = draw.textbbox((0, 0), texto, font=fonte)
            h += (bbox[3] - bbox[1]) + 4
        return h

    def largura_max(linhas):
        return max(
            (draw.textbbox((0, 0), texto, font=fonte)[2] for texto, fonte in linhas),
            default=0,
        )

    largura_max_esq = largura_max(linhas_esq)
    # Espaço que sobra pra coluna da direita (logo + texto) depois do bloco
    # esquerdo. Se o texto da esquerda for muito comprido, encolhe a fonte da
    # direita (até um piso legível) em vez de deixar o texto cortar na borda.
    largura_disponivel_dir = largura - padding - (padding * 3 + largura_max_esq)

    tamanho_fonte_empresa = max(15, largura // 40)
    linhas_dir = []
    logo = None
    logo_largura = 0
    gap_logo = int(padding * 0.8) if textos_dir else 0
    if textos_dir:
        while True:
            fonte_empresa = carregar_fonte(tamanho_fonte_empresa)
            linhas_dir = [(texto, fonte_empresa) for texto in textos_dir]
            altura_texto_dir = altura_bloco(linhas_dir) - 4
            logo = carregar_logo(max(16, altura_texto_dir))
            logo_largura = logo.width if logo else 0
            largura_bloco_dir = logo_largura + gap_logo + largura_max(linhas_dir)
            if largura_bloco_dir <= largura_disponivel_dir or tamanho_fonte_empresa <= 10:
                break
            tamanho_fonte_empresa -= 1

    altura_barra = padding * 2 + max(altura_bloco(linhas_esq), altura_bloco(linhas_dir))

    draw.rectangle(
        [(0, altura - altura_barra), (largura, altura)],
        fill=(0, 0, 0, 160),
    )

    y = altura - altura_barra + padding
    for texto, fonte in linhas_esq:
        draw.text((padding, y), texto, font=fonte, fill=(255, 255, 255, 255))
        bbox = draw.textbbox((0, 0), texto, font=fonte)
        y += (bbox[3] - bbox[1]) + 4

    if linhas_dir:
        # Coluna da direita (logo + empresa/email/telefone) — texto alinhado
        # à esquerda dentro da própria coluna, mas a coluna fica no lado
        # direito da barra pra não brigar com os dados da amostra. A fonte já
        # foi ajustada acima pra caber sem cortar na borda da foto.
        largura_bloco_dir = logo_largura + gap_logo + largura_max(linhas_dir)
        x_dir = max(largura - padding - largura_bloco_dir, padding * 3 + largura_max_esq)
        x_texto = x_dir + logo_largura + gap_logo

        y = altura - altura_barra + padding
        if logo:
            img.paste(logo, (x_dir, y), logo)
        for texto, fonte in linhas_dir:
            draw.text((x_texto, y), texto, font=fonte, fill=(255, 255, 255, 230))
            bbox = draw.textbbox((0, 0), texto, font=fonte)
            y += (bbox[3] - bbox[1]) + 4

    return img


def marcar(pasta, saida):
    pasta = Path(pasta)
    saida = Path(saida)
    saida.mkdir(parents=True, exist_ok=True)

    fotos = listar_fotos(pasta)
    if not fotos:
        print("Nenhuma foto encontrada pra marcar.")
        return

    marcadas = 0
    falhas = 0

    for i, foto in enumerate(fotos, start=1):
        dados = montar_linha_csv(i, foto)

        titulo = f"Amostra {dados['parcela']}" if dados["parcela"] else "Amostra"
        linha1 = " | ".join(p for p in [
            f"Projeto: {dados['projeto']}" if dados["projeto"] else None,
            f"Atividade: {dados['atividade']}" if dados["atividade"] else None,
        ] if p)
        linha2 = " | ".join(p for p in [
            f"Fazenda: {dados['fazenda']}" if dados["fazenda"] else None,
            f"Talhão: {dados['talhao']}" if dados["talhao"] else None,
        ] if p)
        linha3 = " | ".join(p for p in [
            f"Data: {dados['data_coleta']}" if dados["data_coleta"] else None,
            f"Coordenada: {dados['utm']}" if dados["utm"] else None,
        ] if p)

        try:
            with Image.open(foto) as img:
                # Corrige a orientação real dos pixels a partir da tag EXIF de rotação —
                # sem isso, foto tirada na vertical vem "deitada" e a marca sai na lateral.
                img = ImageOps.exif_transpose(img)
                linhas_empresa = [EMPRESA_NOME, EMPRESA_EMAIL, EMPRESA_TELEFONE]
                img_marcada = desenhar_marca_dagua(img, titulo, [linha1, linha2, linha3], linhas_empresa)
                img_marcada.save(saida / foto.name, quality=90)
        except Exception as e:
            print(f"  ERRO em {foto.name}, pulando: {e}")
            falhas += 1
            continue

        marcadas += 1
        print(f"  ok: {foto.name} -> {titulo}")

    print(f"\nConcluído: {marcadas} foto(s) marcada(s), {falhas} com erro ao processar.")
    print(f"Fotos marcadas em: {saida}")


def main():
    parser = argparse.ArgumentParser(description="Marca d'água + CSV das fotos de amostra/parcela (GeoForest Analytics).")
    sub = parser.add_subparsers(dest="comando", required=True)

    p_extrair = sub.add_parser("extrair", help="Lê as fotos da pasta e gera um CSV de conferência (sem desenhar nada)")
    p_extrair.add_argument("--pasta", required=True, help="Pasta com as fotos exportadas do celular")
    p_extrair.add_argument("--csv", default=None, help="Caminho do CSV de saída (padrão: <pasta>/fotos_amostra.csv)")

    p_marcar = sub.add_parser("marcar", help="Lê nome do arquivo + EXIF de cada foto e desenha a marca d'água")
    p_marcar.add_argument("--pasta", required=True, help="Pasta com as fotos originais")
    p_marcar.add_argument("--saida", default=None, help="Pasta de saída das fotos marcadas (padrão: <pasta>/marcadas)")

    args = parser.parse_args()
    pasta = Path(args.pasta)

    if args.comando == "extrair":
        csv_path = Path(args.csv) if args.csv else pasta / NOME_CSV_PADRAO
        extrair(pasta, csv_path)
    elif args.comando == "marcar":
        saida = Path(args.saida) if args.saida else pasta / "marcadas"
        marcar(pasta, saida)


if __name__ == "__main__":
    main()
