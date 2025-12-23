Contexto de Projeto: GeoForest Analytics
1. O que é: Um sistema Vertical SaaS para Engenharia Florestal. Atualmente possui um App Mobile (Flutter) para coleta de inventário (DAP/Altura), cubagem rigorosa e diário de campo financeiro.
2. Stack Técnica:
Frontend: Flutter (Android/iOS).
Backend: Firebase (Firestore, Auth, Cloud Functions).
IA: Gemini 2.0 Flash integrado via firebase_vertexai (Vertex AI for Firebase).
Processamento Estatístico: Iniciando transição para Python (Cloud Functions) para cálculos complexos.
3. Estado Atual do Código:
Sync: Implementado sistema de sincronização incremental (Offline First) entre SQLite e Firestore.
Auditoria IA: Implementada função validarErrosAutomatico no AiValidationService. A IA já entende que árvores normais podem ter altura zero (amostragem) e foca em inconsistências reais e erros de digitação.
Pulo Direto: O App já consegue clicar em um erro gerado pela IA na tela de resultados e levar o usuário direto para a árvore específica na InventarioPage, abrindo o popup de edição e destacando a linha em vermelho.
Dependências: Limpamos conflitos do pubspec.yaml, removendo o firebase_ai e padronizando para firebase_vertexai com suporte ao Gemini 2.0.
4. Próximos Passos (Roadmap):
Hub Web: Criar painel administrativo em Next.js para gestão financeira e dashboards.
Análise Taper: Implementar regressão polinomial de 5º grau via Python para descrever perfil do fuste.
Negócio: Transição de "app coletor" para "ERP Florestal completo" (Vertical ERP).
Instrução para a IA: Use este contexto para continuar o desenvolvimento, respeitando as regras de negócio florestal (bifurcadas, múltiplas, altura de dano, etc).