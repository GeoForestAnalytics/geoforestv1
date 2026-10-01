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
     espécie, talhão etc.), sem tocar nas imagens originais. Também separa
     CÓPIAS das fotos em duas subpastas, pra facilitar achar o que falta
     classificar:
       <pasta>/classificadas/     (+ classificadas/fotos_bio.csv)
       <pasta>/sem_classificar/   (+ sem_classificar/fotos_bio.csv)

       python3 marcar_fotos.py extrair --pasta /caminho/das/fotos

     Abra o CSV de "sem_classificar" no Excel/Sheets e preencha a coluna
     "especie" nessas linhas (não precisa mover as fotos de pasta).

  2) marcar — lê o CSV (já corrigido por você) e desenha a marca d'água em
     cada foto usando a espécie que está NA PLANILHA, não mais no EXIF/nome
     do arquivo. Se as subpastas de "extrair" existirem, usa elas
     automaticamente (soma as duas); senão, usa a pasta e o CSV informados.

       python3 marcar_fotos.py marcar --pasta /caminho/das/fotos

Instalação:
  pip install -r requirements.txt
"""

import argparse
import csv
import re
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

EXTENSOES_VALIDAS = {".jpg", ".jpeg", ".png"}
NOME_CSV_PADRAO = "fotos_bio.csv"
PASTA_CLASSIFICADAS = "classificadas"
PASTA_SEM_CLASSIFICAR = "sem_classificar"

# Rótulos da empresa, impressos na coluna direita da marca d'água.
EMPRESA_NOME = "Geo Forest Analytics"
EMPRESA_EMAIL = "geoforestanalytics@gmail.com"
EMPRESA_TELEFONE = "+55 15 98140-9153"
CAMINHO_LOGO = Path(__file__).parent / "logo.png"

PADRAO_NOME = re.compile(
    r'^TREE_(?P<fazenda>.+?)_(?P<talhao>.+)_A(?P<amostra>[^_]+)_L(?P<linha>\d+)_P(?P<posicao>\d+)'
    r'_(?P<timestamp>\d{10,})(?:_(?P<especie>.+))?\.\w+$',
    re.IGNORECASE,
)

# "E:589452 N:7398201 Zona 22S" -> (589452, 7398201)
PADRAO_UTM = re.compile(r'E:(?P<e>-?\d+(?:\.\d+)?)\s+N:(?P<n>-?\d+(?:\.\d+)?)')

# "... L:1 P:6 ..." -> (1, 6). Fica só "L:1 P:6" junto no comentário (sem "|" entre L e P),
# por isso não dá pra usar o parsear_comentario genérico (chave:valor separado por "|") aqui.
PADRAO_LP = re.compile(r'L:(?P<l>\d+)\s+P:(?P<p>\d+)')

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


def extrair_linha_posicao_do_comentario(comentario):
    if not comentario:
        return "", ""
    m = PADRAO_LP.search(comentario)
    if not m:
        return "", ""
    return m.group("l"), m.group("p")


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

def escrever_csv(csv_path, linhas):
    with open(csv_path, "w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(f, fieldnames=CAMPOS_CSV, delimiter=";")
        writer.writeheader()
        writer.writerows(linhas)


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
        linha_exif, posicao_exif = extrair_linha_posicao_do_comentario(comentario)
        # EXIF primeiro — o nome do arquivo pode ter sido trocado por um app/serviço de
        # transferência (ex.: baixou tudo renomeado pra números sequenciais).
        linha = linha_exif or campos_nome.get("linha_arquivo") or ""
        posicao = posicao_exif or campos_nome.get("posicao_arquivo") or ""
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

    escrever_csv(csv_path, linhas)

    # Separa cópias em duas subpastas — mais fácil achar o que falta classificar
    # sem precisar filtrar o CSV grande. Os arquivos originais na pasta-base não são
    # tocados/movidos.
    pasta_classificadas = pasta / PASTA_CLASSIFICADAS
    pasta_sem_classificar = pasta / PASTA_SEM_CLASSIFICAR
    pasta_classificadas.mkdir(exist_ok=True)
    pasta_sem_classificar.mkdir(exist_ok=True)

    linhas_classificadas = []
    linhas_sem_classificar = []
    for linha in linhas:
        origem = pasta / linha["arquivo"]
        if linha["especie"] == "Desconhecida":
            destino_pasta, lista_destino = pasta_sem_classificar, linhas_sem_classificar
        else:
            destino_pasta, lista_destino = pasta_classificadas, linhas_classificadas
        try:
            shutil.copy2(origem, destino_pasta / linha["arquivo"])
            lista_destino.append(linha)
        except Exception as e:
            print(f"  aviso: não consegui copiar {linha['arquivo']} para {destino_pasta.name}: {e}")

    escrever_csv(pasta_classificadas / NOME_CSV_PADRAO, linhas_classificadas)
    escrever_csv(pasta_sem_classificar / NOME_CSV_PADRAO, linhas_sem_classificar)

    pendentes = len(linhas_sem_classificar)
    print(f"\n{len(linhas)} foto(s) listada(s) em {csv_path}")
    print(f"{len(linhas_classificadas)} foto(s) com espécie -> {pasta_classificadas}")
    print(f"{pendentes} foto(s) sem espécie -> {pasta_sem_classificar}")
    if pendentes:
        print(f"\nAbra {pasta_sem_classificar / NOME_CSV_PADRAO}, preencha a coluna 'especie' e rode o comando 'marcar' depois.")


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

    pasta_classificadas = pasta / PASTA_CLASSIFICADAS
    pasta_sem_classificar = pasta / PASTA_SEM_CLASSIFICAR
    usa_subpastas = pasta_classificadas.is_dir() and pasta_sem_classificar.is_dir()

    if usa_subpastas:
        print(f"Detectadas subpastas '{PASTA_CLASSIFICADAS}'/'{PASTA_SEM_CLASSIFICAR}' — usando elas (soma das duas).")
        linhas = []
        fontes_fotos = [pasta_classificadas, pasta_sem_classificar]
        for fonte in fontes_fotos:
            csv_fonte = fonte / NOME_CSV_PADRAO
            if csv_fonte.exists():
                linhas.extend(ler_csv(csv_fonte))
            else:
                print(f"  aviso: {csv_fonte} não encontrado, pulando essa subpasta.")
    else:
        if not Path(csv_path).exists():
            print(f"CSV não encontrado: {csv_path}\nRode 'extrair' primeiro.")
            return
        linhas = ler_csv(csv_path)
        fontes_fotos = [pasta]

    if not linhas:
        print("Nenhuma foto encontrada pra marcar.")
        return

    marcadas = 0
    faltando = 0
    falhas = 0
    pendentes_sem_especie = []

    for row in linhas:
        arquivo = (row.get("arquivo") or "").strip()
        if not arquivo:
            continue
        foto = next((f / arquivo for f in fontes_fotos if (f / arquivo).exists()), None)
        if foto is None:
            print(f"  aviso: arquivo do CSV não encontrado: {arquivo}")
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

        try:
            with Image.open(foto) as img:
                # Corrige a orientação real dos pixels a partir da tag EXIF de rotação —
                # sem isso, foto tirada na vertical vem "deitada" e a marca sai na lateral.
                img = ImageOps.exif_transpose(img)
                linhas_empresa = [EMPRESA_NOME, EMPRESA_EMAIL, EMPRESA_TELEFONE]
                img_marcada = desenhar_marca_dagua(img, titulo, [linha1, linha2, linha3], linhas_empresa)
                img_marcada.save(saida / arquivo, quality=90)
        except Exception as e:
            print(f"  ERRO em {arquivo}, pulando: {e}")
            falhas += 1
            continue

        marcadas += 1
        print(f"  ok: {arquivo} -> {especie}")

    print(f"\nConcluído: {marcadas} foto(s) marcada(s), {faltando} arquivo(s) do CSV não encontrados na pasta, {falhas} com erro ao processar.")
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
