const functions = require("firebase-functions");
const admin = require("firebase-admin");
// Removi o uuidv4 pois vamos usar um gerador de código curto manual

admin.initializeApp();
const auth = admin.auth();
const db = admin.firestore();

// =========================================================================
// FUNÇÃO 1: updateUserLicenseClaim (Mantém as permissões em dia)
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
      
      const allUids = new Set([...Object.keys(usersBefore), ...Object.keys(usersAfter)]);
      const promises = [];
      
      for (const uid of allUids) {
        const userIsMemberAfter = usersAfter[uid] != null;
        const userWasMemberBefore = usersBefore[uid] != null;
        
        if (userIsMemberAfter) {
          const cargo = usersAfter[uid].cargo;
          if (!cargo) continue;
          
          // Define os claims: licenseId (empresa) e cargo
          const promise = auth.setCustomUserClaims(uid, { licenseId: licenseId, cargo: cargo });
          promises.push(promise);
          console.log(`Claims atualizados para ${uid}: Empresa ${licenseId}, Cargo ${cargo}`);
        } else if (userWasMemberBefore && !userIsMemberAfter) {
          // Remove os claims se o usuário foi removido da equipe
          const promise = auth.setCustomUserClaims(uid, { licenseId: null, cargo: null });
          promises.push(promise);
          console.log(`Claims revogados para ${uid}`);
        }
      }
      await Promise.all(promises);
      return null;
    });

// =========================================================================
// FUNÇÃO 2: adicionarMembroEquipe (Cria usuário e vincula à licença)
// =========================================================================
exports.adicionarMembroEquipe = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      // Segurança: Apenas gerentes podem adicionar
      if (!context.auth || !context.auth.token.licenseId || context.auth.token.cargo !== 'gerente') {
        throw new functions.https.HttpsError("permission-denied", "Apenas gerentes autenticados podem adicionar membros.");
      }
      
      const { email, password, name, cargo } = data;
      if (!email || !password || !name || !cargo || password.length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "Dados inválidos. Senha deve ter mín. 6 caracteres.");
      }

      const managerLicenseId = context.auth.token.licenseId;

      try {
        // 1. Cria no Auth
        const userRecord = await admin.auth().createUser({
          email: email,
          password: password,
          displayName: name,
        });

        const batch = db.batch();

        // 2. Atualiza documento do CLIENTE (Empresa)
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

        // 3. Cria documento do USUÁRIO (Link reverso para Login)
        const userDocRef = db.collection("users").doc(userRecord.uid);
        batch.set(userDocRef, {
            email: email,
            licenseId: managerLicenseId, 
        });

        await batch.commit();
        
        return { success: true, message: `Usuário '${name}' adicionado com sucesso!` };

      } catch (error) {
        console.error("Erro ao criar membro:", error);
        if (error.code === 'auth/email-already-exists') {
            throw new functions.https.HttpsError("already-exists", "Este email já está em uso.");
        }
        throw new functions.https.HttpsError("internal", "Erro ao criar membro da equipe.");
      }
    });

// =========================================================================
// FUNÇÃO 3: deletarProjeto (Soft Delete)
// =========================================================================
exports.deletarProjeto = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      if (!context.auth || !context.auth.token.licenseId || context.auth.token.cargo !== 'gerente') {
        throw new functions.https.HttpsError("permission-denied", "Permissão negada.");
      }
      
      const { projetoId } = data;
      const licenseId = context.auth.token.licenseId;
      
      try {
        const projetoRef = db.collection("clientes").doc(licenseId).collection('projetos').doc(String(projetoId));
        await projetoRef.update({ 
            status: 'deletado',
            lastModified: admin.firestore.FieldValue.serverTimestamp() 
        });
        return { success: true };
      } catch (error) {
        throw new functions.https.HttpsError("internal", "Erro ao deletar projeto.");
      }
    });

// =========================================================================
// FUNÇÃO 4: delegarProjeto (Gera chave curta)
// =========================================================================
exports.delegarProjeto = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      if (!context.auth || !context.auth.token.licenseId || context.auth.token.cargo !== 'gerente') {
        throw new functions.https.HttpsError("permission-denied", "Apenas gerentes podem delegar projetos.");
      }
      
      const { projetoId, nomeProjeto } = data;
      const managerLicenseId = context.auth.token.licenseId;

      // --- ALTERAÇÃO AQUI: Gera código curto (ex: A1B2C3) ---
      const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
      let chaveId = '';
      for (let i = 0; i < 6; i++) {
        chaveId += chars.charAt(Math.floor(Math.random() * chars.length));
      }
      // -----------------------------------------------------

      // Usa a chave gerada como ID do documento para garantir unicidade na busca direta se quisesse,
      // mas aqui mantemos no corpo para permitir a Query Collection Group.
      // O ID do documento pode ser a própria chave para facilitar.
      const chaveRef = db.collection("clientes").doc(managerLicenseId).collection("chavesDeDelegacao").doc(chaveId);
      
      await chaveRef.set({
        chave: chaveId, 
        status: "pendente", 
        licenseIdConvidada: null, 
        empresaConvidada: "Aguardando Vínculo",
        dataCriacao: admin.firestore.FieldValue.serverTimestamp(), 
        projetosPermitidos: [projetoId], 
        nomesProjetos: [nomeProjeto],
      });

      return { chave: chaveId };
    });

// =========================================================================
// FUNÇÃO 5: vincularProjetoDelegado (Consome a chave)
// =========================================================================
exports.vincularProjetoDelegado = functions
    .region("southamerica-east1")
    .runWith({ enforceAppCheck: false }) // Opcional: Proteção extra
    .https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Login necessário.");
      }

      // 1. Tenta pegar a licença do token (mais rápido) ou do banco (fallback)
      let contractorLicenseId = context.auth.token.licenseId;
      if (!contractorLicenseId) {
        const userDoc = await db.collection('users').doc(context.auth.uid).get();
        if (userDoc.exists) {
            contractorLicenseId = userDoc.data().licenseId;
        }
      }
      if (!contractorLicenseId) {
          throw new functions.https.HttpsError("unauthenticated", "Licença não identificada.");
      }
      
      // Sanitização da entrada
      const rawChave = data.chave || "";
      const chave = rawChave.trim().toUpperCase();

      if (chave.length === 0) {
        throw new functions.https.HttpsError("invalid-argument", "Chave inválida.");
      }

      // 2. Busca a chave globalmente
      // NOTA: Requer índice 'chave' (Ascending) e 'status' (Ascending) em 'chavesDeDelegacao'
      const query = db.collectionGroup("chavesDeDelegacao")
          .where("chave", "==", chave)
          .where("status", "==", "pendente")
          .limit(1);
          
      const snapshot = await query.get();

      if (snapshot.empty) {
        throw new functions.https.HttpsError("not-found", "Chave inválida, já usada ou expirada.");
      }

      const doc = snapshot.docs[0];
      const managerLicenseId = doc.ref.parent.parent.id;

      if (managerLicenseId === contractorLicenseId) {
        throw new functions.https.HttpsError("invalid-argument", "Não é possível vincular projeto da própria empresa.");
      }
      
      // 3. Obtém o nome da empresa/usuário que está vinculando
      let contractorName = context.auth.token.email || "Usuário Externo";
      try {
        const contractorDoc = await db.collection('clientes').doc(contractorLicenseId).get();
        if (contractorDoc.exists) {
            const users = contractorDoc.data().usuariosPermitidos || {};
            if (users[context.auth.uid] && users[context.auth.uid].nome) {
                contractorName = users[context.auth.uid].nome;
            }
        }
      } catch (e) {
          console.error("Erro ao buscar nome:", e);
      }

      // 4. Efetiva o vínculo
      await doc.ref.update({
        status: "ativa",
        licenseIdConvidada: contractorLicenseId,
        empresaConvidada: contractorName,
        dataVinculo: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { success: true, message: "Projeto vinculado com sucesso!" };
    });