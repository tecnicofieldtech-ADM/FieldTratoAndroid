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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text("Linha: ${item.linha}  •  Trato: ${item.trato}",
                  style: TextStyle(color: Colors.grey.shade700)),
              const SizedBox(height: 10),

              Row(
                children: [
                  _pill(ok ? "OK" : "PENDENTE", ok ? Colors.green : Colors.orange),
                  const SizedBox(width: 8),
                  if ((item.rfid ?? "").trim().isNotEmpty)
                    _pill("RFID", Colors.blueGrey),
                ],
              ),

              const Spacer(),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _kv("Prev", item.previstoKg),
                  _kv("Real", item.realizadoKg),
                  _kv("Falta", falta),
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
        color: color.withOpacity(.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
    );
  }

  Widget _kv(String k, num v) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
        Text(v.toStringAsFixed(1), style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}
