// functions/index.js (VERSÃO COMPLETA E CORRIGIDA)

const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { v4: uuidv4 } = require("uuid");

admin.initializeApp();
const auth = admin.auth();
const db = admin.firestore();

// =========================================================================
// FUNÇÃO 1: updateUserLicenseClaim (Sem alterações)
// =========================================================================
exports.updateUserLicenseClaim = functions
    .region("southamerica-east1")
    .firestore
    .document("clientes/{licenseId}")
    .onWrite(async (change, context) => {
      // ... seu código original aqui, está correto ...
      const licenseId = context.params.licenseId;
      const dataAfter = change.after.exists ? change.after.data() : null;
      const dataBefore = change.before.exists ? change.before.data() : null;
      const usersAfter = dataAfter ? dataAfter.usuariosPermitidos || {} : {};
      const usersBefore = dataBefore ? dataBefore.usuariosPermitidos || {} : {};
      const allUids = new Set([...Object.keys(usersBefore), ...Object.keys(usersAfter)]);
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
          const promise = auth.setCustomUserClaims(uid, { licenseId: licenseId, cargo: cargo });
          promises.push(promise);
          console.log(`Aplicando claims { licenseId: ${licenseId}, cargo: ${cargo} } para ${uid}`);
        } else if (userWasMemberBefore && !userIsMemberAfter) {
          const promise = auth.setCustomUserClaims(uid, { licenseId: null, cargo: null });
          promises.push(promise);
          console.log(`Removendo claims para ${uid}`);
        }
      }
      await Promise.all(promises);
      return null;
    });

// =========================================================================
// FUNÇÃO 2: adicionarMembroEquipe (VERSÃO CORRIGIDA)
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
        // Passo 1: Cria o usuário no Firebase Authentication
        const userRecord = await admin.auth().createUser({
          email: email,
          password: password,
          displayName: name,
        });

        // <<< INÍCIO DA CORREÇÃO >>>

        // Passo 2: Prepara um "batch" para executar as duas escritas no Firestore
        const batch = db.batch();

        // Passo 3: Adiciona a atualização do documento 'clientes' ao batch
        const clienteDocRef = db.collection("clientes").doc(managerLicenseId);
        batch.update(clienteDocRef, {
            [`usuariosPermitidos.${userRecord.uid}`]: {
                cargo: cargo,
                email: email,
                nome: name,
                adicionadoEm: admin.firestore.FieldValue.serverTimestamp()
            },
            "uidsPermitidos": admin.firestore.FieldValue.arrayUnion(userRecord.uid),
        });

        // Passo 4: Adiciona a criação do documento 'users' ao batch
        const userDocRef = db.collection("users").doc(userRecord.uid);
        batch.set(userDocRef, {
            email: email,
            licenseId: managerLicenseId, // Aponta para a licença do gerente
        });

        // Passo 5: Executa as duas operações juntas
        await batch.commit();
        
        // <<< FIM DA CORREÇÃO >>>

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
// FUNÇÃO 3: deletarProjeto (Sem alterações)
// =========================================================================
exports.deletarProjeto = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      // ... seu código original aqui, está correto ...
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
// FUNÇÃO 4: delegarProjeto (Sem alterações)
// =========================================================================
exports.delegarProjeto = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      // ... seu código original aqui, está correto ...
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
        chave: chaveId, status: "pendente", licenseIdConvidada: null, empresaConvidada: "Aguardando Vínculo",
        dataCriacao: admin.firestore.FieldValue.serverTimestamp(), projetosPermitidos: [projetoId], nomesProjetos: [nomeProjeto],
      });
      console.log(`Chave ${chaveId} gerada para o projeto ${projetoId} pela licença ${managerLicenseId}`);
      return { chave: chaveId };
    });

// =========================================================================
// FUNÇÃO 5: vincularProjetoDelegado (Sem alterações)
// =========================================================================
exports.vincularProjetoDelegado = functions
    .region("southamerica-east1")
    .runWith({ enforceAppCheck: true })
    .https.onCall(async (data, context) => {
      // Verifica se o usuário está autenticado
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Você precisa estar autenticado para vincular um projeto.");
      }

      // Lógica robusta para obter a licenseId
      let contractorLicenseId = context.auth.token.licenseId;
      if (!contractorLicenseId) {
        console.log(`licenseId não encontrado no token. Buscando em /users...`);
        const userDoc = await db.collection('users').doc(context.auth.uid).get();
        if (userDoc.exists) {
            contractorLicenseId = userDoc.data().licenseId;
        }
      }
      if (!contractorLicenseId) {
          throw new functions.https.HttpsError("unauthenticated", "Não foi possível identificar sua licença.");
      }
      
      const { chave } = data;
      if (!chave) {
        throw new functions.https.HttpsError("invalid-argument", "Uma chave de delegação válida é necessária.");
      }

      // A busca pela chave continua a mesma
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
        throw new functions.https.HttpsError("already-exists", "Esta chave já foi utilizada ou foi revogada.");
      }
      
      // <<< INÍCIO DA CORREÇÃO >>>

      // 1. Busca o documento da licença do contratado para obter o nome
      let contractorName = "Nome não encontrado"; // Valor padrão
      try {
        const contractorLicenseDoc = await db.collection('clientes').doc(contractorLicenseId).get();
        if (contractorLicenseDoc.exists) {
            const contractorData = contractorLicenseDoc.data();
            // Acessa o nome dentro do mapa 'usuariosPermitidos'
            const contractorUserInfo = contractorData.usuariosPermitidos[context.auth.uid];
            if (contractorUserInfo && contractorUserInfo.nome) {
                contractorName = contractorUserInfo.nome;
            } else {
                // Fallback para o email se o nome não for encontrado
                contractorName = context.auth.token.email || "Email não disponível";
            }
        }
      } catch (error) {
        console.error("Erro ao buscar nome do contratado:", error);
        // Usa o email como fallback em caso de erro na busca
        contractorName = context.auth.token.email || "Email não disponível";
      }

      // <<< FIM DA CORREÇÃO >>>

      await doc.ref.update({
        status: "ativa",
        licenseIdConvidada: contractorLicenseId,
        empresaConvidada: contractorName, // Usa o nome obtido de forma segura
        dataVinculo: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`Chave ${chave} vinculada com sucesso à licença ${contractorLicenseId}.`);
      return { success: true, message: "Projeto vinculado com sucesso! Sincronize seus dados para começar." };
    });