import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geoforestv1/data/repositories/pilha_repository.dart';
import 'package:geoforestv1/models/pilha_madeira_model.dart';
import 'package:geoforestv1/pages/pilhas/coleta_pilha_page.dart';
import 'package:geoforestv1/widgets/grafico_perfil_pilha_widget.dart';

class DetalhePilhaPage extends StatefulWidget {
  final PilhaMadeira pilha;

  const DetalhePilhaPage({super.key, required this.pilha});

  @override
  State<DetalhePilhaPage> createState() => _DetalhePilhaPageState();
}

class _DetalhePilhaPageState extends State<DetalhePilhaPage> {
  final _repo = PilhaRepository();
  CentroidePilha? _centroide;
  late PilhaMadeira _pilha;

  @override
  void initState() {
    super.initState();
    _pilha = widget.pilha;
    _carregarCentroide();
  }

  Future<void> _carregarCentroide() async {
    if (_pilha.centroideId == null) return;
    final c = await _repo.getCentroideById(_pilha.centroideId!);
    if (mounted) setState(() => _centroide = c);
  }

  Future<void> _abrirEdicao() async {
    if (_centroide == null) return;
    final result = await Navigator.of(context).push<PilhaMadeira>(
      MaterialPageRoute(
        builder: (_) => ColetaPilhaPage(
          centroide: _centroide!,
          pilhaParaEditar: _pilha,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() => _pilha = result);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pilha ${result.numeroPilhaFormatado} atualizada!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vol = _pilha.calcularVolumeBruto();
    final volSolido = _pilha.calcularVolumesolido();
    final toraLabel = _pilha.comprimentoToraReal != null
        ? '${_pilha.comprimentoToraReal!.toStringAsFixed(2)} m (ajustado em campo)'
        : '${_pilha.comprimentoTora.toStringAsFixed(2)} m (OS)';

    return Scaffold(
      appBar: AppBar(
        title: Text('Pilha ${_pilha.numeroPilhaFormatado} — ${_pilha.nomeTalhao ?? ''}'),
        actions: [
          if (_centroide != null)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Editar pilha',
              onPressed: _abrirEdicao,
            )
          else
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Resumo ────────────────────────────────────────────────────
            _card(
              child: Column(
                children: [
                  _statRow(context, 'Fazenda', _pilha.nomeFazenda ?? '—'),
                  _statRow(context, 'Talhão', _pilha.nomeTalhao ?? '—'),
                  _statRow(context, 'Sortimento', _pilha.sortimento),
                  _statRow(context, 'Comprimento pilha', '${_pilha.comprimentoPilha.toStringAsFixed(2)} m'),
                  _statRow(context, 'Tora', toraLabel),
                  if (_pilha.dapMin != null || _pilha.dapMax != null)
                    _statRow(context, 'DAP', '${_pilha.dapMin?.toStringAsFixed(0) ?? '?'}–${_pilha.dapMax?.toStringAsFixed(0) ?? '?'} cm'),
                  _statRow(context, 'Altura média', '${_pilha.calcularAlturaMedia().toStringAsFixed(2)} m'),
                  _statRow(context, 'Seções medidas', '${_pilha.secoes.length}'),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Volume Estéreo',
                          style: TextStyle(color: Colors.brown.shade600, fontSize: 13)),
                      Text(
                        '${vol.toStringAsFixed(2)} st',
                        style: TextStyle(fontSize: 14, color: Colors.brown.shade600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Volume Sólido  (fe ${_pilha.fatorEmpilhamento.toStringAsFixed(2)})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        '${volSolido.toStringAsFixed(2)} m³',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.brown.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Gráfico perfil ────────────────────────────────────────────
            _sectionTitle('Perfil de altura'),
            _card(
              child: GraficoPerfilPilhaWidget(
                secoes: _pilha.secoes,
                comprimentoPilha: _pilha.comprimentoPilha,
              ),
            ),

            const SizedBox(height: 16),

            // ── Seções individuais ────────────────────────────────────────
            _sectionTitle('Medições por seção'),
            _card(
              child: Table(
                columnWidths: const {
                  0: FixedColumnWidth(40),
                  1: FlexColumnWidth(),
                  2: FlexColumnWidth(),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.brown.shade50),
                    children: const [
                      _TableHeader('Nº'),
                      _TableHeader('Distância'),
                      _TableHeader('Altura'),
                    ],
                  ),
                  ..._pilha.secoes.map((s) => TableRow(children: [
                    _TableCell('${s.posicao}'),
                    _TableCell('${s.distanciaMetros.toStringAsFixed(2)} m'),
                    _TableCell('${s.altura.toStringAsFixed(2)} m'),
                  ])),
                ],
              ),
            ),

            // ── Observações ───────────────────────────────────────────────
            if (_pilha.observacoes != null && _pilha.observacoes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionTitle('Observações'),
              _card(child: Text(_pilha.observacoes!, style: const TextStyle(fontSize: 14))),
            ],

            // ── Fotos ─────────────────────────────────────────────────────
            if (_pilha.fotos.isNotEmpty) ...[
              const SizedBox(height: 16),
              _sectionTitle('Fotos (${_pilha.fotos.length})'),
              SizedBox(
                height: 200,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pilha.fotos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) => GestureDetector(
                    onTap: () => _verFotoExpandida(ctx, _pilha.fotos, i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_pilha.fotos[i]),
                        width: 200,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 200,
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.broken_image, size: 48, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            // ── Metadados ─────────────────────────────────────────────────
            const SizedBox(height: 16),
            _sectionTitle('Metadados'),
            _card(
              child: Column(
                children: [
                  if (_pilha.dataColeta != null)
                    _statRow(context, 'Data coleta', _formatarData(_pilha.dataColeta!)),
                  if (_pilha.nomeLider != null && _pilha.nomeLider!.isNotEmpty)
                    _statRow(context, 'Coletado por', _pilha.nomeLider!),
                  if (_pilha.latitude != null)
                    _statRow(context, 'GPS',
                        '${_pilha.latitude!.toStringAsFixed(6)}, ${_pilha.longitude!.toStringAsFixed(6)}'),
                  _statRow(context, 'Exportada', _pilha.exportada ? 'Sim' : 'Não'),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _verFotoExpandida(BuildContext ctx, List<String> fotos, int inicial) {
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => _FotoExpandidaPage(fotos: fotos, inicial: inicial),
    ));
  }

  String _formatarData(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );

  Widget _card({required Widget child}) => Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      );

  Widget _statRow(BuildContext ctx, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            ),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

// ── Visualizador de fotos em tela cheia ──────────────────────────────────────

class _FotoExpandidaPage extends StatefulWidget {
  final List<String> fotos;
  final int inicial;
  const _FotoExpandidaPage({required this.fotos, required this.inicial});

  @override
  State<_FotoExpandidaPage> createState() => _FotoExpandidaPageState();
}

class _FotoExpandidaPageState extends State<_FotoExpandidaPage> {
  late final PageController _ctrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.inicial;
    _ctrl = PageController(initialPage: widget.inicial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.fotos.length}'),
      ),
      body: PageView.builder(
        controller: _ctrl,
        itemCount: widget.fotos.length,
        onPageChanged: (i) => setState(() => _current = i),
        itemBuilder: (_, i) => InteractiveViewer(
          child: Center(
            child: Image.file(
              File(widget.fotos[i]),
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Widgets auxiliares da tabela ─────────────────────────────────────────────

class _TableHeader extends StatelessWidget {
  final String text;
  const _TableHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      );
}

class _TableCell extends StatelessWidget {
  final String text;
  const _TableCell(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
        child: Text(text, style: const TextStyle(fontSize: 12)),
      );
}
