// functions/index.js (VERSÃO FINAL, UNIFICADA E EM JAVASCRIPT)

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { v4: uuidv4 } = require("uuid"); // Para gerar chaves seguras

admin.initializeApp();
const auth = admin.auth();
const db = admin.firestore();

// =========================================================================
// FUNÇÃO 1: Atualiza os Custom Claims quando um documento de cliente muda
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
// FUNÇÃO 2: Adiciona um novo membro à equipe
// =========================================================================
exports.adicionarMembroEquipe = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
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
// FUNÇÃO 3: Deleta um projeto (Soft Delete)
// =========================================================================
exports.deletarProjeto = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      if (!context.auth || !context.auth.token.licenseId || context.auth.token.cargo !== 'gerente') {
        throw new functions.https.HttpsError("permission-denied", "Apenas gerentes autenticados podem excluir projetos.");
      }

      const { projetoId } = data;
      if (!projetoId) {
        throw new functions.https.HttpsError("invalid-argument", "O ID do projeto é obrigatório para a exclusão.");
      }
      
      const licenseId = context.auth.token.licenseId;
      const projetoRef = db.collection("clientes").doc(licenseId).collection('projetos').doc(projetoId.toString());

      try {
        await projetoRef.update({ status: 'deletado' });
        console.log(`Projeto ${projetoId} da licença ${licenseId} marcado como 'deletado'.`);
        return { success: true, message: "Projeto movido para a lixeira com sucesso." };
      } catch (error) {
        console.error(`Falha ao marcar projeto ${projetoId} como deletado:`, error);
        throw new functions.https.HttpsError("internal", "Ocorreu um erro interno ao tentar arquivar o projeto.");
      }
    });

// =========================================================================
// FUNÇÃO 4: Gerar a chave de delegação
// =========================================================================
exports.delegarProjeto = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      if (!context.auth || !context.auth.token.licenseId || context.auth.token.cargo !== 'gerente') {
        throw new functions.https.HttpsError("permission-denied", "Apenas gerentes podem delegar projetos.");
      }

      const { projetoId, nomeProjeto } = data;
      if (!projetoId || !nomeProjeto) {
        throw new functions.https.HttpsError("invalid-argument", "Os dados do projeto (ID e Nome) são obrigatórios.");
      }
      
      const managerLicenseId = context.auth.token.licenseId;
      const chaveId = uuidv4();
      const chaveRef = db.collection("clientes").doc(managerLicenseId).collection("chavesDeDelegacao").doc(chaveId);

      await chaveRef.set({
        chave: chaveId, // Armazena a chave no documento para facilitar buscas
        status: "pendente",
        licenseIdConvidada: null,
        empresaConvidada: "Aguardando Vínculo",
        dataCriacao: admin.firestore.FieldValue.serverTimestamp(),
        projetosPermitidos: [projetoId],
        nomesProjetos: [nomeProjeto],
      });

      console.log(`Chave ${chaveId} gerada para o projeto ${projetoId} pela licença ${managerLicenseId}`);
      return { chave: chaveId };
    });

// =========================================================================
// FUNÇÃO 5: Vincular o projeto usando a chave
// =========================================================================
exports.vincularProjetoDelegado = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      if (!context.auth || !context.auth.token.licenseId) {
        throw new functions.https.HttpsError("unauthenticated", "Você precisa estar autenticado e possuir uma licença para vincular um projeto.");
      }

      const contractorLicenseId = context.auth.token.licenseId; 
      const { chave } = data;
      if (!chave) {
        throw new functions.https.HttpsError("invalid-argument", "Uma chave de delegação válida é necessária.");
      }

      const query = db.collectionGroup("chavesDeDelegacao").where("chave", "==", chave).limit(1);
      const snapshot = await query.get();

      if (snapshot.empty) {
        throw new functions.https.HttpsError("not-found", "Chave de delegação inválida ou não encontrada.");
      }

      const doc = snapshot.docs[0];
      const docData = doc.data();
      const managerLicenseId = doc.ref.parent.parent.id;

      if (managerLicenseId === contractorLicenseId) {
        throw new functions.https.HttpsError("invalid-argument", "Você não pode vincular um projeto de sua própria empresa.");
      }

      if (docData.status !== "pendente") {
        throw new functions.https.HttpsError("already-exists", "Esta chave já foi utilizada ou foi revogada pelo administrador.");
      }

      await doc.ref.update({
        status: "ativa",
        licenseIdConvidada: contractorLicenseId,
        empresaConvidada: context.auth.token.name || context.auth.token.email,
        dataVinculo: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`Chave ${chave} vinculada com sucesso à licença ${contractorLicenseId}.`);
      return { success: true, message: "Projeto vinculado com sucesso! Sincronize seus dados para começar." };
    });