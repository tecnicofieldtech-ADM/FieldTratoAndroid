import "package:flutter/material.dart";
import "../../data/fornecimento_models.dart";

class CurralCard extends StatelessWidget {
  const CurralCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  final CurralPrev item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final falta = item.faltaKg;
    final ok = item.concluido;

    return Card(
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.nomeLocal,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                "Linha: ${item.linha}  •  Trato: ${item.trato}",
                style: TextStyle(color: Colors.grey.shade700),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  _pill(ok ? "OK" : "PENDENTE",
                      ok ? Colors.green : Colors.orange),
                  const SizedBox(width: 8),
                  if (item.rfid.trim().isNotEmpty)
                    _pill("RFID", Colors.blueGrey),
                ],
              ),

              const Spacer(),

              // ✅ colunas com mesma largura + sem quebra de texto
              Row(
                children: [
                  Expanded(
                    child: _kv(
                      "Previsto",
                      item.previstoKg,
                      alignEnd: false,
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      "Realizado",
                      item.realizadoKg,
                      alignEnd: true,
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      "Falta",
                      falta,
                      alignEnd: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Text(text,
          style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }

  Widget _kv(String k, num v, {required bool alignEnd}) {
    final ta = alignEnd ? TextAlign.right : TextAlign.left;

    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          k,
          textAlign: ta,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
        ),
        Text(
          v.toStringAsFixed(1),
          textAlign: ta,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
