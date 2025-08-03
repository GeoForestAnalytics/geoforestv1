// functions/index.js (VERSÃO FINAL LIMPA E CORRIGIDA)

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const auth = admin.auth();
const db = admin.firestore();

// =========================================================================
// FUNÇÃO 1: Atualiza os Custom Claims quando um usuário é adicionado/removido
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
              console.error(`Cargo não encontrado para o usuário ${uid}. Pulando.`);
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
// FUNÇÃO 2: Adiciona um novo membro à equipe (chamada pelo app)
// =========================================================================
exports.adicionarMembroEquipe = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
      if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Ação não autenticada.");
      }

      const { email, password, name, cargo } = data;
      if (!email || !password || !name || !cargo || password.length < 6) {
        throw new functions.https.HttpsError("invalid-argument", "Dados inválidos.");
      }

      const managerUid = context.auth.uid;
      const licenseQuery = await db
        .collection("clientes")
        .where(`usuariosPermitidos.${managerUid}.cargo`, "==", "gerente")
        .limit(1)
        .get();

      if (licenseQuery.empty) {
        throw new functions.https.HttpsError("permission-denied", "Você não tem permissão para adicionar membros.");
      }

      const licenseDoc = licenseQuery.docs[0];

      try {
        console.log(`Gerente ${managerUid} tentando criar usuário ${email}`);
        const userRecord = await admin.auth().createUser({
          email: email,
          password: password,
          displayName: name,
        });

        console.log(`Usuário ${userRecord.uid} criado. Atualizando licença ${licenseDoc.id}`);
        const novoMembroData = {
          cargo: cargo,
          email: email,
          nome: name,
          adicionadoEm: admin.firestore.FieldValue.serverTimestamp()
        };
        
        console.log(`---> VAI ATUALIZAR COM A VERSÃO CORRIGIDA (arrayUnion) <---`);

        await licenseDoc.ref.update({
            [`usuariosPermitidos.${userRecord.uid}`]: novoMembroData,
            "uidsPermitidos": admin.firestore.FieldValue.arrayUnion(userRecord.uid),
        });

        console.log(`Licença atualizada com sucesso para o novo membro ${userRecord.uid}`);
        return { success: true, message: `Usuário '${name}' adicionado com sucesso!` };

      } catch (error) {
        console.error("Falha ao criar membro da equipe:", error);
        if (error.code === 'auth/email-already-exists') {
            throw new functions.https.HttpsError("already-exists", "Este email já está em uso.");
        }
        throw new functions.https.HttpsError("internal", "Ocorreu um erro interno.");
      }
    });

// =========================================================================
// FUNÇÃO 3: Deleta um projeto e todos os seus dados (chamada pelo app)
// =========================================================================
exports.deletarProjeto = functions
    .region("southamerica-east1")
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Ação não autenticada.");
        }

        const gerenteUid = context.auth.uid;
        const { projetoId } = data;

        if (!projetoId) {
            throw new functions.https.HttpsError("invalid-argument", "O ID do projeto é obrigatório.");
        }

        console.log(`Gerente ${gerenteUid} solicitou a exclusão do projeto ${projetoId}`);

        const licenseQuery = await db.collection("clientes")
            .where(`usuariosPermitidos.${gerenteUid}.cargo`, "==", "gerente")
            .limit(1).get();

        if (licenseQuery.empty) {
            throw new functions.https.HttpsError("permission-denied", "Você não tem permissão para excluir projetos.");
        }

        const licenseDoc = licenseQuery.docs[0];
        const clienteRef = licenseDoc.ref;
        const batchSize = 400; 
        let batch = db.batch();
        let operationCount = 0;

        async function commitBatchIfNeeded() {
            if (operationCount >= batchSize) {
                console.log(`Executando lote com ${operationCount} operações...`);
                await batch.commit();
                batch = db.batch();
                operationCount = 0;
            }
        }

        try {
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

            await batch.commit(); 
            console.log(`Projeto ${projetoId} e todos os seus dados foram excluídos com sucesso.`);
            return { success: true, message: "Projeto excluído com sucesso." };

        } catch (error) {
            console.error("Falha ao excluir projeto:", error);
            throw new functions.https.HttpsError("internal", "Ocorreu um erro interno ao tentar excluir o projeto.");
        }
    });