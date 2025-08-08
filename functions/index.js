// functions/index.js (VERSÃO FINAL, COMPLETA E REFINADA)

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { v4: uuidv4 } = require("uuid");

admin.initializeApp();
const auth = admin.auth();
const db = admin.firestore();

// =========================================================================
// FUNÇÃO 1: Atualiza os Custom Claims quando um documento de cliente muda
// Disparada automaticamente pelo Firestore. Garante que as permissões estejam sempre sincronizadas.
// =========================================================================
exports.updateUserLicenseClaim = functions
    .region("southamerica-east1")
    .firestore
    .document("clientes/{licenseId}")
    .onWrite(async (change, context) => {
      const licenseId = context.params.licenseId;
      const dataAfter = change.after.exists ? change.after.data() : null;
      const dataBefore = change.before.exists ? change.before.data() : null;

      const usersAfter = dataAfter ? dataAfter.usuariosPermitidos || {} : {};
      const usersBefore = dataBefore ? dataBefore.usuariosPermitidos || {} : {};

      const allUids = new Set([
        ...Object.keys(usersBefore),
        ...Object.keys(usersAfter),
      ]);

      const promises = [];

      for (const uid of allUids) {
        const userIsMemberAfter = usersAfter[uid] != null;
        const userWasMemberBefore = usersBefore[uid] != null;
        
        if (userIsMemberAfter) {
          const cargo = usersAfter[uid].cargo;
          if (!cargo) {
              console.error(`Cargo não encontrado para o usuário ${uid} na licença ${licenseId}. Pulando.`);
              continue;
          }
          const promise = auth.setCustomUserClaims(uid, { 
              licenseId: licenseId, 
              cargo: cargo 
          });
          promises.push(promise);
          console.log(`Aplicando claims { licenseId: ${licenseId}, cargo: ${cargo} } para ${uid}`);

        } else if (userWasMemberBefore && !userIsMemberAfter) {
          const promise = auth.setCustomUserClaims(uid, { 
              licenseId: null, 
              cargo: null 
          });
          promises.push(promise);
          console.log(`Removendo claims para ${uid}`);
        }
      }

      await Promise.all(promises);
      return null;
    });

// =========================================================================
// FUNÇÃO 2: Adiciona um novo membro à equipe (Chamada pelo app)
// =========================================================================
exports.adicionarMembroEquipe = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      // Verificação de permissão robusta usando Custom Claims do token.
      if (!context.auth || !context.auth.token.licenseId || context.auth.token.cargo !== 'gerente') {
        throw new functions.https.HttpsError("permission-denied", "Apenas gerentes autenticados podem adicionar membros.");
      }
      
      const { email, password, name, cargo } = data;
      if (!email || !password || !name || !cargo || password.length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "Dados inválidos. Forneça email, senha (mín. 6 caracteres), nome e cargo.");
      }

      const managerLicenseId = context.auth.token.licenseId;

      try {
        const userRecord = await admin.auth().createUser({
          email: email,
          password: password,
          displayName: name,
        });

        const novoMembroData = {
          cargo: cargo,
          email: email,
          nome: name,
          adicionadoEm: admin.firestore.FieldValue.serverTimestamp()
        };
        
        // Atualiza o mapa de usuários e o array de UIDs para otimizar buscas.
        await db.collection("clientes").doc(managerLicenseId).update({
            [`usuariosPermitidos.${userRecord.uid}`]: novoMembroData,
            "uidsPermitidos": admin.firestore.FieldValue.arrayUnion(userRecord.uid),
        });

        return { success: true, message: `Usuário '${name}' adicionado com sucesso!` };

      } catch (error) {
        console.error("Erro ao criar membro da equipe:", error);
        if (error.code === 'auth/email-already-exists') {
            throw new functions.https.HttpsError("already-exists", "Este email já está em uso por outro usuário.");
        }
        throw new functions.https.HttpsError("internal", "Ocorreu um erro interno ao criar o novo membro.");
      }
    });

// =========================================================================
// FUNÇÃO 3: Deleta um projeto e todos os seus dados (Chamada pelo app)
// =========================================================================
exports.deletarProjeto = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      // Verificação de permissão robusta.
      if (!context.auth || !context.auth.token.licenseId || context.auth.token.cargo !== 'gerente') {
        throw new functions.https.HttpsError("permission-denied", "Apenas gerentes autenticados podem excluir projetos.");
      }

      const { projetoId } = data;
      if (!projetoId) {
        throw new functions.https.HttpsError("invalid-argument", "O ID do projeto é obrigatório para a exclusão.");
      }
      
      const licenseId = context.auth.token.licenseId;
      const clienteRef = db.collection("clientes").doc(licenseId);
      const batchSize = 400; // Limite seguro para operações em lote no Firestore.
      let batch = db.batch();
      let operationCount = 0;

      // Função auxiliar para commitar o lote quando ele atingir o tamanho máximo.
      async function commitBatchIfNeeded() {
        if (operationCount >= batchSize) {
          await batch.commit();
          batch = db.batch();
          operationCount = 0;
        }
      }

      try {
        // A lógica de exclusão em cascata está correta, percorrendo as coleções relacionadas.
        const atividadesSnap = await clienteRef.collection('atividades').where('projetoId', '==', projetoId).get();
        const atividadeIds = atividadesSnap.docs.map((doc) => doc.data()['id']);

        if (atividadeIds.length > 0) {
          const fazendasSnap = await clienteRef.collection('fazendas').where('atividadeId', 'in', atividadeIds).get();
          const fazendaIdsStr = fazendasSnap.docs.map((doc) => doc.data()['id']);

          if (fazendaIdsStr.length > 0) {
            const talhoesSnap = await clienteRef.collection('talhoes').where('fazendaId', 'in', fazendaIdsStr).get();
            const talhaoIds = talhoesSnap.docs.map((doc) => doc.data()['id']);

            if (talhaoIds.length > 0) {
              const parcelasSnap = await clienteRef.collection('dados_coleta').where('talhaoId', 'in', talhaoIds).get();
              for (const doc of parcelasSnap.docs) { batch.delete(doc.ref); operationCount++; await commitBatchIfNeeded(); }
              
              const cubagensSnap = await clienteRef.collection('dados_cubagem').where('talhaoId', 'in', talhaoIds).get();
              for (const doc of cubagensSnap.docs) { batch.delete(doc.ref); operationCount++; await commitBatchIfNeeded(); }
            }
            for (const doc of talhoesSnap.docs) { batch.delete(doc.ref); operationCount++; await commitBatchIfNeeded(); }
          }
          for (const doc of fazendasSnap.docs) { batch.delete(doc.ref); operationCount++; await commitBatchIfNeeded(); }
        }
        for (const doc of atividadesSnap.docs) { batch.delete(doc.ref); operationCount++; await commitBatchIfNeeded(); }

        batch.delete(clienteRef.collection('projetos').doc(projetoId.toString()));
        operationCount++;

        // Garante que o último lote de operações seja commitado.
        if (operationCount > 0) {
          await batch.commit();
        }
        
        return { success: true, message: "Projeto e todos os seus dados foram excluídos com sucesso." };

      } catch (error) {
        console.error("Falha crítica ao excluir projeto e seus sub-dados:", error);
        throw new functions.https.HttpsError("internal", "Ocorreu um erro interno ao tentar excluir o projeto. Verifique os logs do servidor.");
      }
    });

// =========================================================================
// FUNÇÃO 4: Gerar a chave de delegação (Ação do Gerente)
// =========================================================================
exports.delegarProjeto = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      // Verificação de permissão robusta.
      if (!context.auth || !context.auth.token.licenseId || context.auth.token.cargo !== 'gerente') {
        throw new functions.https.HttpsError("permission-denied", "Apenas gerentes podem delegar projetos.");
      }

      const { projetoId, nomeProjeto } = data;
      if (!projetoId || !nomeProjeto) {
        throw new functions.https.HttpsError("invalid-argument", "Os dados do projeto (ID e Nome) são obrigatórios.");
      }
      
      const managerLicenseId = context.auth.token.licenseId;
      const chaveId = uuidv4(); // Gera uma chave única e segura.
      const chaveRef = db.collection("clientes").doc(managerLicenseId).collection("chavesDeDelegacao").doc(chaveId);

      await chaveRef.set({
        status: "pendente",
        licenseIdConvidada: null,
        empresaConvidada: "Aguardando Vínculo",
        dataCriacao: admin.firestore.FieldValue.serverTimestamp(),
        projetosPermitidos: [projetoId],
        nomesProjetos: [nomeProjeto], // Guardar o nome facilita a exibição na UI do terceiro.
      });

      console.log(`Chave ${chaveId} gerada para o projeto ${projetoId} pela licença ${managerLicenseId}`);
      return { chave: chaveId };
    });

// =========================================================================
// FUNÇÃO 5: Vincular o projeto usando a chave (Ação do Terceiro)
// =========================================================================
exports.vincularProjetoDelegado = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Você precisa estar autenticado para vincular um projeto.");
      }

      // O UID do usuário que está vinculando se torna o ID da licença convidada.
      const contractorLicenseId = context.auth.uid; 
      const { chave } = data;

      if (!chave) {
        throw new functions.https.HttpsError("invalid-argument", "Uma chave de delegação válida é necessária.");
      }

      // Procura em todas as subcoleções 'chavesDeDelegacao' por um documento com o ID da chave.
      const query = db.collectionGroup("chavesDeDelegacao").where(admin.firestore.FieldPath.documentId(), "==", chave);
      const snapshot = await query.get();

      if (snapshot.empty) {
        throw new functions.https.HttpsError("not-found", "Chave de delegação inválida ou não encontrada.");
      }

      const doc = snapshot.docs[0];
      const docData = doc.data();

      if (docData.status !== "pendente") {
        throw new functions.https.HttpsError("already-exists", "Esta chave já foi utilizada ou foi revogada pelo administrador.");
      }

      await doc.ref.update({
        status: "ativa",
        licenseIdConvidada: contractorLicenseId,
        empresaConvidada: context.auth.token.name || context.auth.token.email, // Usa o nome ou email do usuário como identificação.
        dataVinculo: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`Chave ${chave} vinculada com sucesso à licença ${contractorLicenseId}.`);
      return { success: true, message: "Projeto vinculado com sucesso! Sincronize seus dados para começar." };
    });