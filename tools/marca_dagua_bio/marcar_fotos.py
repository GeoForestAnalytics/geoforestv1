#!/usr/bin/env python3
"""
Ferramenta de pós-processamento das fotos do modo BIO (GeoForest Analytics).

Roda no computador (não no celular) de propósito: desenhar texto em cima da
foto exige decodificar/redesenhar o bitmap inteiro, e uma tentativa anterior
de fazer isso no app mobile travava o processamento e derrubava o app.
No computador não existe esse risco.

Funciona em DUAS etapas, pra dar espaço pra corrigir a espécie das fotos que
ficaram "Desconhecida" antes de gravar a marca d'água definitiva:

  1) extrair — lê cada foto da pasta (nome do arquivo + EXIF UserComment
     gravados pelo app) e gera um CSV com uma linha por foto (id, árvore,
     espécie, talhão etc.), sem tocar nas imagens.

       python3 marcar_fotos.py extrair --pasta /caminho/das/fotos

     Abra o CSV gerado (fotos_bio.csv) no Excel/Sheets e preencha a coluna
     "especie" nas linhas que vieram como "Desconhecida".

  2) marcar — lê esse mesmo CSV (já corrigido por você) e desenha a marca
     d'água em cada foto usando a espécie que está NA PLANILHA, não mais no
     EXIF/nome do arquivo. O CSV vira a fonte da verdade.

       python3 marcar_fotos.py marcar --pasta /caminho/das/fotos

Instalação:
  pip install -r requirements.txt
"""

import argparse
import csv
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

EXTENSOES_VALIDAS = {".jpg", ".jpeg", ".png"}

PADRAO_NOME = re.compile(
    r'^TREE_(?P<fazenda>.+?)_(?P<talhao>.+)_A(?P<amostra>[^_]+)_L(?P<linha>\d+)_P(?P<posicao>\d+)'
    r'_(?P<timestamp>\d{10,})(?:_(?P<especie>.+))?\.\w+$',
    re.IGNORECASE,
)

# "E:589452 N:7398201 Zona 22S" -> (589452, 7398201)
PADRAO_UTM = re.compile(r'E:(?P<e>-?\d+(?:\.\d+)?)\s+N:(?P<n>-?\d+(?:\.\d+)?)')

CAMPOS_CSV = [
    "id", "arquivo",
    # Nomeadas igual às colunas da planilha principal (export do app/web), pra dar pra
    # cruzar com PROCV/PROCX sem precisar de coluna auxiliar/fórmula.
    "ID_Coleta_Parcela", "Linha", "Posicao_na_Linha",
    "arvore", "especie", "fazenda", "talhao", "projeto",
    "Easting", "Northing", "utm",
    "identificado_por_ia", "comentario_exif_bruto",
]


def extrair_easting_northing(utm_texto):
    if not utm_texto:
        return "", ""
    m = PADRAO_UTM.search(utm_texto)
    if not m:
        return "", ""
    return m.group("e"), m.group("n")


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
            # UserComment costuma ficar na sub-IFD "Exif" (tag 0x8769 -> 0x9286).
            try:
                exif_ifd = exif.get_ifd(0x8769)
                if 0x9286 in exif_ifd:
                    texto = decodificar_user_comment(exif_ifd[0x9286])
                    if texto:
                        return texto
            except Exception:
                pass
            # Alguns gravadores colocam direto na IFD principal.
            if 0x9286 in exif:
                return decodificar_user_comment(exif[0x9286])
    except Exception as e:
        print(f"  aviso: não consegui ler EXIF de {caminho.name}: {e}")
    return None


def parsear_comentario(texto):
    """'Projeto: X | Talhao: Y | L:1 P:2 | Especie: Z | Identificado por IA: Sim' -> dict"""
    campos = {}
    if not texto:
        return campos
    for parte in texto.split("|"):
        if ":" in parte:
            chave, valor = parte.split(":", 1)
            campos[chave.strip().lower()] = valor.strip()
    return campos


def extrair_do_nome_arquivo(nome):
    m = PADRAO_NOME.match(nome)
    if not m:
        return {}
    d = m.groupdict()
    return {
        "especie_arquivo": (d.get("especie") or "").replace("_", " ").strip(),
        "fazenda_arquivo": d.get("fazenda"),
        "talhao_arquivo": d.get("talhao"),
        "amostra_arquivo": d.get("amostra"),
        "linha_arquivo": d.get("linha"),
        "posicao_arquivo": d.get("posicao"),
    }


def listar_fotos(pasta):
    return sorted(
        f for f in Path(pasta).iterdir()
        if f.is_file() and f.suffix.lower() in EXTENSOES_VALIDAS
    )


# ───────────────────────────────── Etapa 1: extrair CSV ─────────────────────────────────

def extrair(pasta, csv_path):
    pasta = Path(pasta)
    fotos = listar_fotos(pasta)

    if not fotos:
        print(f"Nenhuma foto encontrada em {pasta}")
        return

    linhas = []
    for i, foto in enumerate(fotos, start=1):
        comentario = ler_user_comment(foto)
        campos_exif = parsear_comentario(comentario)
        campos_nome = extrair_do_nome_arquivo(foto.name)

        especie = campos_exif.get("especie") or campos_nome.get("especie_arquivo") or "Desconhecida"
        fazenda = campos_exif.get("fazenda") or campos_nome.get("fazenda_arquivo") or ""
        talhao = campos_exif.get("talhao") or campos_nome.get("talhao_arquivo") or ""
        projeto = campos_exif.get("projeto") or ""
        utm = campos_exif.get("utm") or ""
        identificado_ia = campos_exif.get("identificado por ia") or "Desconhecido"

        amostra = campos_exif.get("amostra") or campos_nome.get("amostra_arquivo") or ""
        linha = campos_nome.get("linha_arquivo") or ""
        posicao = campos_nome.get("posicao_arquivo") or ""
        # Amostra entra na chave da árvore: L1P2 se repete entre amostras diferentes do mesmo talhão.
        arvore = f"A{amostra}_L{linha}P{posicao}" if linha and posicao else ""

        easting, northing = extrair_easting_northing(utm)

        linhas.append({
            "id": i,
            "arquivo": foto.name,
            "ID_Coleta_Parcela": amostra,
            "Linha": linha,
            "Posicao_na_Linha": posicao,
            "arvore": arvore,
            "especie": especie,
            "fazenda": fazenda,
            "talhao": talhao,
            "projeto": projeto,
            "Easting": easting,
            "Northing": northing,
            "utm": utm,
            "identificado_por_ia": identificado_ia,
            "comentario_exif_bruto": comentario or "",
        })
        print(f"  {i:>3}: {foto.name} -> {especie}")

    with open(csv_path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=CAMPOS_CSV, delimiter=";")
        writer.writeheader()
        writer.writerows(linhas)

    pendentes = sum(1 for l in linhas if l["especie"] == "Desconhecida")
    print(f"\n{len(linhas)} foto(s) listada(s) em {csv_path}")
    if pendentes:
        print(f"{pendentes} com espécie 'Desconhecida' — abra o CSV, preencha a coluna 'especie' nessas linhas e rode o comando 'marcar' depois.")


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


def desenhar_marca_dagua(img, titulo, linhas_subtitulo):
    img = img.convert("RGB")
    largura, altura = img.size

    fonte_titulo = carregar_fonte(max(18, largura // 32), negrito=True)
    fonte_subtitulo = carregar_fonte(max(13, largura // 48))

    draw = ImageDraw.Draw(img, "RGBA")
    padding = max(10, largura // 80)

    linhas = [(titulo, fonte_titulo)] if titulo else []
    for texto_sub in linhas_subtitulo:
        if texto_sub:
            linhas.append((texto_sub, fonte_subtitulo))

    if not linhas:
        return img

    altura_barra = padding * 2
    for texto, fonte in linhas:
        bbox = draw.textbbox((0, 0), texto, font=fonte)
        altura_barra += (bbox[3] - bbox[1]) + 4

    draw.rectangle(
        [(0, altura - altura_barra), (largura, altura)],
        fill=(0, 0, 0, 160),
    )

    y = altura - altura_barra + padding
    for texto, fonte in linhas:
        draw.text((padding, y), texto, font=fonte, fill=(255, 255, 255, 255))
        bbox = draw.textbbox((0, 0), texto, font=fonte)
        y += (bbox[3] - bbox[1]) + 4

    return img


def ler_csv(csv_path):
    with open(csv_path, newline="", encoding="utf-8-sig") as f:
        # aceita ; (padrão do script) ou , (caso o Excel resalve com outro separador)
        amostra = f.read(2048)
        f.seek(0)
        delimitador = ";" if amostra.count(";") >= amostra.count(",") else ","
        return list(csv.DictReader(f, delimiter=delimitador))


def marcar(pasta, csv_path, saida):
    pasta = Path(pasta)
    saida = Path(saida)
    saida.mkdir(parents=True, exist_ok=True)

    if not Path(csv_path).exists():
        print(f"CSV não encontrado: {csv_path}\nRode 'extrair' primeiro.")
        return

    linhas = ler_csv(csv_path)
    if not linhas:
        print(f"CSV vazio: {csv_path}")
        return

    marcadas = 0
    faltando = 0
    pendentes_sem_especie = []

    for row in linhas:
        arquivo = (row.get("arquivo") or "").strip()
        if not arquivo:
            continue
        foto = pasta / arquivo
        if not foto.exists():
            print(f"  aviso: arquivo do CSV não encontrado na pasta: {arquivo}")
            faltando += 1
            continue

        especie = (row.get("especie") or "").strip() or "Desconhecida"
        if especie == "Desconhecida":
            pendentes_sem_especie.append(arquivo)

        fazenda = (row.get("fazenda") or "").strip()
        talhao = (row.get("talhao") or "").strip()
        projeto = (row.get("projeto") or "").strip()
        amostra = (row.get("ID_Coleta_Parcela") or "").strip()
        linha_pos = (row.get("Linha") or "").strip()
        posicao_pos = (row.get("Posicao_na_Linha") or "").strip()
        utm = (row.get("utm") or "").strip()

        titulo = especie
        linha1 = " | ".join(p for p in [f"Projeto: {projeto}" if projeto else None, f"Fazenda: {fazenda}" if fazenda else None] if p)
        posicao_str = f"Amostra: {amostra} | L:{linha_pos} P:{posicao_pos}" if linha_pos and posicao_pos else (f"Amostra: {amostra}" if amostra else None)
        linha2 = " | ".join(p for p in [f"Talhão: {talhao}" if talhao else None, posicao_str] if p)
        linha3 = f"Coordenada: {utm}" if utm else None

        with Image.open(foto) as img:
            img_marcada = desenhar_marca_dagua(img, titulo, [linha1, linha2, linha3])
            img_marcada.save(saida / arquivo, quality=90)

        marcadas += 1
        print(f"  ok: {arquivo} -> {especie}")

    print(f"\nConcluído: {marcadas} foto(s) marcada(s), {faltando} arquivo(s) do CSV não encontrados na pasta.")
    print(f"Fotos marcadas em: {saida}")
    if pendentes_sem_especie:
        print(f"\nAtenção: {len(pendentes_sem_especie)} foto(s) ainda marcada(s) como 'Desconhecida' (espécie não preenchida no CSV):")
        for a in pendentes_sem_especie:
            print(f"  - {a}")


def main():
    parser = argparse.ArgumentParser(description="Marca d'água + CSV das fotos do modo BIO (GeoForest Analytics).")
    sub = parser.add_subparsers(dest="comando", required=True)

    p_extrair = sub.add_parser("extrair", help="Lê as fotos da pasta e gera o CSV (sem desenhar nada)")
    p_extrair.add_argument("--pasta", required=True, help="Pasta com as fotos exportadas do celular")
    p_extrair.add_argument("--csv", default=None, help="Caminho do CSV de saída (padrão: <pasta>/fotos_bio.csv)")

    p_marcar = sub.add_parser("marcar", help="Lê o CSV (já corrigido) e desenha a marca d'água nas fotos")
    p_marcar.add_argument("--pasta", required=True, help="Pasta com as fotos originais")
    p_marcar.add_argument("--csv", default=None, help="CSV gerado pelo 'extrair' (padrão: <pasta>/fotos_bio.csv)")
    p_marcar.add_argument("--saida", default=None, help="Pasta de saída das fotos marcadas (padrão: <pasta>/marcadas)")

    args = parser.parse_args()
    pasta = Path(args.pasta)
    csv_path = Path(args.csv) if args.csv else pasta / "fotos_bio.csv"

    if args.comando == "extrair":
        extrair(pasta, csv_path)
    elif args.comando == "marcar":
        saida = Path(args.saida) if args.saida else pasta / "marcadas"
        marcar(pasta, csv_path, saida)


if __name__ == "__main__":
    main()
