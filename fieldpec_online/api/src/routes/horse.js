const master = require("../services/master");
const ops = require("../services/ops");
const tenant = require("../services/tenant");

async function withClient(req, reply, fn) {
  try {
    const code = await tenant.requireClientCode(req);
    req.clienteCodigo = code;
    return await fn(code);
  } catch (e) {
    const msg = e.message || String(e);
    const status =
      msg.includes("obrigatório") || msg.includes("inválido") ? 400 : 403;
    return reply.code(status).send({
      success: false,
      error: msg,
      hint: "Envie header X-Client-Code com o código do cliente cadastrado.",
    });
  }
}

function registerHorseRoutes(app) {
  app.get("/GetTeste", async (_req, reply) => {
    return reply.code(200).send({ "OK ": "Sevidor Online" });
  });

  /** Valida se o código está cadastrado/ativo (app / conector). */
  app.get("/cliente/validar", async (req, reply) => {
    try {
      const fromQuery =
        (req.query && (req.query.codigo || req.query.code || req.query.client_code)) ||
        "";
      const code =
        tenant.extractClientCode(req) || tenant.normalizeClientCode(fromQuery);
      const row = await tenant.requireRegisteredCliente(code);
      return reply.send({
        ok: true,
        success: true,
        codigo: row.codigo,
        nome: row.nome,
        ativo: row.ativo !== false,
      });
    } catch (e) {
      const msg = e.message || String(e);
      const status =
        msg.includes("obrigatório") || msg.includes("inválido") || msg.includes("Informe")
          ? 400
          : 403;
      return reply.code(status).send({
        ok: false,
        success: false,
        error: msg,
      });
    }
  });

  app.get("/fazenda/get", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(await master.listFazendas(cc)),
    );
  });

  app.get("/vagao/get", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(await master.listVagoes(cc)),
    );
  });
  app.get("/vagao/get/", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(await master.listVagoes(cc)),
    );
  });

  app.get("/usuarios/get", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(await master.listUsuarios(cc, null)),
    );
  });
  app.get("/usuarios/get/:idfazenda", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(await master.listUsuarios(cc, req.params.idfazenda)),
    );
  });

  app.get("/baias/get", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(await master.listBaias(cc, null)),
    );
  });
  app.get("/baias/get/:idfazenda", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(await master.listBaias(cc, req.params.idfazenda)),
    );
  });

  app.get("/dietas/get", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(await master.listDietas(cc, null)),
    );
  });
  app.get("/dietas/get/:idfazenda", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(await master.listDietas(cc, req.params.idfazenda)),
    );
  });

  app.get("/dietas_detalhes/get", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(await master.listDietasDetalhes(cc, null)),
    );
  });
  app.get("/dietas_detalhes/get/:idfazenda", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(await master.listDietasDetalhes(cc, req.params.idfazenda)),
    );
  });

  app.get("/previsao_trato/get", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(await master.listPrevisao(cc, null, null)),
    );
  });
  app.get("/previsao_trato/get/:idfazenda/:dataPrev", async (req, reply) => {
    return withClient(req, reply, async (cc) =>
      reply.send(
        await master.listPrevisao(cc, req.params.idfazenda, req.params.dataPrev),
      ),
    );
  });

  app.post("/Post/Fabricacao", async (req, reply) => {
    return withClient(req, reply, async (cc) => {
      try {
        const result = await ops.saveFabricacao(cc, req.body || {});
        return reply.code(201).send(result);
      } catch (e) {
        req.log.error(e);
        return reply.code(500).send({
          success: false,
          message: "Erro ao salvar fabricação.",
          error: e.message,
        });
      }
    });
  });

  app.post("/Post/Fornecimento", async (req, reply) => {
    return withClient(req, reply, async (cc) => {
      try {
        const body = req.body;
        if (Array.isArray(body)) {
          for (const row of body) await ops.saveFornecimento(cc, row);
        } else if (body && Array.isArray(body.itens)) {
          for (const row of body.itens) await ops.saveFornecimento(cc, row);
        } else {
          await ops.saveFornecimento(cc, body || {});
        }
        return reply.code(200).send({ success: true, cliente_codigo: cc });
      } catch (e) {
        req.log.error(e);
        return reply.code(500).send({ success: false, error: e.message });
      }
    });
  });

  app.post("/Post/GravaTag", async (req, reply) => {
    return withClient(req, reply, async (cc) => {
      try {
        await ops.saveGravaTag(cc, req.body || {});
        return reply.code(200).send({ success: true });
      } catch (e) {
        return reply.code(500).send({ success: false, error: e.message });
      }
    });
  });

  app.post("/Post/FabricacaoAudit", async (req, reply) => {
    return withClient(req, reply, async (cc) => {
      await ops.saveAudit(cc, "fabricacao", req.body || {});
      return reply.code(200).send({ success: true });
    });
  });

  app.post("/Post/FornecimentoAudit", async (req, reply) => {
    return withClient(req, reply, async (cc) => {
      await ops.saveAudit(cc, "fornecimento", req.body || {});
      return reply.code(200).send({ success: true });
    });
  });

  app.post("/Post/GpsTrack", async (req, reply) => {
    return withClient(req, reply, async (cc) => {
      await ops.saveGps(cc, req.body || {});
      return reply.code(200).send({ success: true });
    });
  });

  app.post("/Post/Fabricacao_Insumo", async (req, reply) => {
    return reply.code(200).send({ success: true, ignored: true });
  });
}

module.exports = { registerHorseRoutes };
