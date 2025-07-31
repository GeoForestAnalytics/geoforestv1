"use strict";
// /functions/src/index.ts
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createcheckoutsession = exports.onusercreate = void 0;
const https_1 = require("firebase-functions/v2/https");
const auth_1 = require("firebase-functions/v2/auth");
const params_1 = require("firebase-functions/params");
const firebase_functions_1 = require("firebase-functions");
const admin = __importStar(require("firebase-admin"));
const stripe_1 = __importDefault(require("stripe"));
admin.initializeApp();
const db = admin.firestore();
const stripeSecret = (0, params_1.defineSecret)("STRIPE_SECRET_KEY");
exports.onusercreate = (0, auth_1.onUserCreated)({ region: "southamerica-east1", secrets: [stripeSecret] }, async (event) => {
    const user = event.data;
    firebase_functions_1.logger.info(`Novo usuário criado: ${user.email}, UID: ${user.uid}`);
    try {
        const stripeInstance = new stripe_1.default(stripeSecret.value(), { apiVersion: "2024-04-10" });
        const customer = await stripeInstance.customers.create({
            email: user.email, name: user.displayName, metadata: { firebaseUID: user.uid },
        });
        firebase_functions_1.logger.info(`Cliente Stripe criado para ${user.email} com ID ${customer.id}`);
        const trialEndDate = new Date();
        trialEndDate.setDate(trialEndDate.getDate() + 7);
        const customerDocRef = db.collection("clientes").doc(user.uid);
        await customerDocRef.set({
            email: user.email, stripeCustomerId: customer.id, statusAssinatura: "trial",
            features: { exportacao: false, analise: false },
            limites: { smartphone: 1, desktop: 0 },
            trial: {
                ativo: true, dataInicio: admin.firestore.FieldValue.serverTimestamp(),
                dataFim: admin.firestore.Timestamp.fromDate(trialEndDate),
            },
        });
        firebase_functions_1.logger.info(`Documento de licença e trial criado para ${user.uid}`);
    }
    catch (error) {
        firebase_functions_1.logger.error(`Erro ao configurar o novo usuário ${user.uid}:`, error);
    }
});
exports.createcheckoutsession = (0, https_1.onCall)({ region: "southamerica-east1", secrets: [stripeSecret] }, async (request) => {
    var _a;
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Você precisa estar logado.");
    }
    const stripeInstance = new stripe_1.default(stripeSecret.value(), {
        apiVersion: "2024-04-10",
    });
    const uid = request.auth.uid;
    const priceId = request.data.priceId;
    try {
        const userDoc = await db.collection("clientes").doc(uid).get();
        if (!userDoc.exists) {
            throw new https_1.HttpsError("not-found", "Os dados da sua conta não foram encontrados.");
        }
        const customerId = (_a = userDoc.data()) === null || _a === void 0 ? void 0 : _a.stripeCustomerId;
        if (!customerId) {
            throw new https_1.HttpsError("internal", "Sua conta de pagamento não está configurada.");
        }
        const session = await stripeInstance.checkout.sessions.create({
            payment_method_types: ["card"],
            mode: "subscription",
            customer: customerId,
            line_items: [{ price: priceId, quantity: 1 }],
            success_url: "https://geoforest.com.br/sucesso?session_id={CHECKOUT_SESSION_ID}",
            cancel_url: "https://geoforest.com.br/cancelamento",
            allow_promotion_codes: true,
        });
        if (!session.url) {
            throw new https_1.HttpsError("internal", "Não foi possível obter a URL de pagamento.");
        }
        return { url: session.url };
    }
    catch (error) {
        firebase_functions_1.logger.error(`Erro ao criar a sessão de checkout para ${uid}:`, error);
        if (error instanceof https_1.HttpsError) {
            throw error;
        }
        throw new https_1.HttpsError("internal", "Não foi possível iniciar o pagamento.");
    }
});
//# sourceMappingURL=index.js.js.map