const excelImport = require("../services/excelImport");
const excelTemplate = require("../services/excelTemplate");
const excelExport = require("../services/excelExport");
const { TEMPLATE_FILENAME } = require("../services/excelLayout");

function registerPlanilhaRoutes(app, { assertAdmin, resolveAdminClient }) {
  app.get("/planilha/template", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    const buf = await excelTemplate.buildTemplateBuffer();
    reply
      .header(
        "Content-Type",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      )
      .header(
        "Content-Disposition",
        `attachment; filename="${TEMPLATE_FILENAME}"`,
      )
      .send(buf);
  });

  app.post("/planilha/importar", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    let cc = "";
    try {
      cc = (await resolveAdminClient(req, { required: false })) || "";
    } catch (_) {
      cc = "";
    }

    const file = await req.file();
    if (!file) {
      return reply.code(400).send({
        success: false,
        erros: [
          {
            aba: "",
            linha: 0,
            campo: "",
            mensagem: "Envie um arquivo .xlsx no campo 'file'.",
          },
        ],
      });
    }

    const chunks = [];
    for await (const chunk of file.file) chunks.push(chunk);
    const buffer = Buffer.concat(chunks);
    const filename = file.filename || "upload.xlsx";

    try {
      const result = await excelImport.importBuffer(buffer, {
        filename,
        clienteCodigo: cc,
      });
      if (!result.success) {
        return reply.code(400).send(result);
      }
      return reply.send(result);
    } catch (e) {
      req.log.error(e);
      return reply.code(500).send({
        success: false,
        erros: [
          {
            aba: "",
            linha: 0,
            campo: "",
            mensagem: e.message || "Falha ao importar planilha.",
          },
        ],
      });
    }
  });

  app.get("/planilha/importacoes", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    let cc = "";
    try {
      cc = (await resolveAdminClient(req, { required: false })) || "";
    } catch (_) {
      cc = "";
    }
    return reply.send(await excelImport.listImportacoes(cc));
  });

  app.get("/planilha/importacoes/:id", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    let cc = "";
    try {
      cc = (await resolveAdminClient(req, { required: true })) || "";
    } catch (e) {
      return reply.code(400).send({ success: false, error: e.message });
    }
    const row = await excelImport.getImportacao(req.params.id);
    if (
      !row ||
      String(row.cliente_codigo || "").toUpperCase() !== String(cc).toUpperCase()
    ) {
      return reply.code(404).send({ success: false, error: "Importação não encontrada." });
    }
    return reply.send(row);
  });

  app.get("/planilha/exportar/:id", async (req, reply) => {
    if (!assertAdmin(req, reply)) return;
    let cc = "";
    try {
      cc = (await resolveAdminClient(req, { required: true })) || "";
    } catch (e) {
      return reply.code(400).send({ success: false, error: e.message });
    }
    const result = await excelExport.exportImportacao(req.params.id, {
      clienteCodigo: cc,
    });
    if (!result || result.missingClient) {
      return reply.code(result && result.missingClient ? 400 : 404).send({
        success: false,
        error: result && result.missingClient
          ? "Informe client_code (header X-Client-Code ou query/body)."
          : "Importação não encontrada.",
      });
    }
    reply
      .header(
        "Content-Type",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      )
      .header(
        "Content-Disposition",
        `attachment; filename="${result.filename}"`,
      )
      .send(result.buffer);
  });
}

module.exports = { registerPlanilhaRoutes };
