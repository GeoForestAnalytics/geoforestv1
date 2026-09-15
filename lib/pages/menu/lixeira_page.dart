// lib/pages/menu/lixeira_page.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geoforestv1/providers/license_provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

class LixeiraPage extends StatelessWidget {
  const LixeiraPage({super.key});

  @override
  Widget build(BuildContext context) {
    final licenseId = context.read<LicenseProvider>().licenseData?.id;
    if (licenseId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Lixeira de Projetos')),
        body: const Center(child: Text('Licença não encontrada.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lixeira de Projetos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Projetos excluídos ficam armazenados para recuperação.',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Contate o suporte para restaurar um projeto excluído.')),
            ),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('clientes')
            .doc(licenseId)
            .collection('lixeira')
            .orderBy('deletadoEm', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.delete_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('Nenhum projeto excluído ainda.',
                      style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final data = docs[i].data() as Map<String, dynamic>;
              final nome = data['projetoNome'] as String? ?? '—';
              final projetoId = data['projetoId']?.toString() ?? '—';
              final deletadoPorNome = data['deletadoPorNome'] as String? ?? '—';
              final deletadoPorEmail = data['deletadoPorEmail'] as String? ?? '—';
              final ts = data['deletadoEm'];
              final DateTime? deletadoEm = ts is Timestamp ? ts.toDate() : null;
              final fmt = DateFormat('dd/MM/yyyy HH:mm');

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.red.shade50,
                    child: const Icon(Icons.folder_delete_outlined, color: Colors.red),
                  ),
                  title: Text(nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ID: $projetoId'),
                      Text('Excluído por: $deletadoPorNome'),
                      if (deletadoEm != null) Text('Em: ${fmt.format(deletadoEm)}'),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.receipt_long_outlined, color: Colors.indigo),
                    tooltip: 'Gerar comprovante PDF',
                    onPressed: () => _gerarComprovante(
                      context: context,
                      nome: nome,
                      projetoId: projetoId,
                      deletadoPorNome: deletadoPorNome,
                      deletadoPorEmail: deletadoPorEmail,
                      deletadoEm: deletadoEm,
                      licenseId: licenseId,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _gerarComprovante({
    required BuildContext context,
    required String nome,
    required String projetoId,
    required String deletadoPorNome,
    required String deletadoPorEmail,
    required DateTime? deletadoEm,
    required String licenseId,
  }) async {
    final fmt = DateFormat('dd/MM/yyyy HH:mm:ss');
    final doc = pw.Document();

    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (pw.Context ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('GeoForest Analytics',
                  style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#023853'))),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#FDECEA'),
                  borderRadius: pw.BorderRadius.circular(6),
                  border: pw.Border.all(color: PdfColor.fromHex('#E53935')),
                ),
                child: pw.Text('PROJETO EXCLUÍDO',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#E53935'))),
              ),
            ],
          ),
          pw.SizedBox(height: 8),
          pw.Divider(color: PdfColor.fromHex('#023853'), thickness: 2),
          pw.SizedBox(height: 20),
          pw.Text('Comprovante de Exclusão de Projeto',
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 24),
          _pdfRow('Nome do Projeto', nome),
          _pdfRow('ID do Projeto', projetoId),
          _pdfRow('ID da Licença', licenseId),
          _pdfRow('Excluído por', '$deletadoPorNome ($deletadoPorEmail)'),
          _pdfRow('Data e Hora', deletadoEm != null ? fmt.format(deletadoEm) : '—'),
          pw.SizedBox(height: 32),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#FFF8E1'),
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColor.fromHex('#FFC107')),
            ),
            child: pw.Text(
              'Para recuperar este projeto, entre em contato com o suporte '
              'informando o ID do Projeto e a ID da Licença acima.',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          pw.Spacer(),
          pw.Divider(),
          pw.Text('Documento gerado em ${fmt.format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ],
      ),
    ));

    await Printing.layoutPdf(onLayout: (fmt) async => doc.save());
  }

  pw.Widget _pdfRow(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 160,
              child: pw.Text(label,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11,
                      color: PdfColor.fromHex('#555555'))),
            ),
            pw.Expanded(
              child: pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
            ),
          ],
        ),
      );
}
