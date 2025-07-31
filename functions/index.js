const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const auth = admin.auth();
const db = admin.firestore();

/**
 * Esta função é acionada sempre que um documento de cliente é criado ou atualizado.
 * Ela percorre o mapa 'usuariosPermitidos' e aplica um Custom Claim 'licenseId'
 * em cada usuário listado, garantindo que suas permissões sejam atualizadas.
 */
exports.updateUserLicenseClaim = functions.firestore
    .document("clientes/{licenseId}")
    .onWrite(async (change, context) => {
      const licenseId = context.params.licenseId;
      const dataAfter = change.after.exists ? change.after.data() : null;
      const dataBefore = change.before.exists ? change.before.data() : null;

      // Pega a lista de usuários permitidos antes e depois da mudança
      const usersAfter = dataAfter ? dataAfter.usuariosPermitidos || {} : {};
      const usersBefore = dataBefore ? dataBefore.usuariosPermitidos || {} : {};

      // Combina todos os UIDs que podem ter sido afetados
      const allUids = new Set([
        ...Object.keys(usersBefore),
        ...Object.keys(usersAfter),
      ]);

      const promises = [];

      for (const uid of allUids) {
        const userIsMemberAfter = usersAfter[uid] != null;
        const userWasMemberBefore = usersBefore[uid] != null;
        
        // Se o usuário foi adicionado ou já existia, garante que ele tenha o claim correto
        if (userIsMemberAfter) {
          const promise = auth.setCustomUserClaims(uid, { licenseId: licenseId });
          promises.push(promise);
          console.log(`Aplicando claim { licenseId: ${licenseId} } para o usuário ${uid}`);
        } 
        // Se o usuário foi removido da lista, remove o claim dele
        else if (userWasMemberBefore && !userIsMemberAfter) {
          const promise = auth.setCustomUserClaims(uid, { licenseId: null });
          promises.push(promise);
          console.log(`Removendo claim de licença para o usuário ${uid}`);
        }
      }

      await Promise.all(promises);
      return null;
    });