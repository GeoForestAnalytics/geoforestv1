// functions/index.js (VERSÃO FINAL REVISADA)

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const auth = admin.auth();
const db = admin.firestore();

exports.updateUserLicenseClaim = functions.firestore
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

exports.adicionarMembroEquipe = functions
    .region("southamerica-east1") // Confirme se esta é sua região
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

        await licenseDoc.ref.update({
          [`usuariosPermitidos.${userRecord.uid}`]: novoMembroData,
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