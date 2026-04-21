// @file        apps/session-broker/src/services/kubernetes-oidc/index.ts
// @module      identity/kubernetes
// @description Kubernetes OIDC service exports

export { KubernetesOIDCService, createKubernetesOIDCRouter } from './kubernetes-oidc';
export type {
  KubernetesOIDCConfig,
  KubernetesServiceAccountClaim,
  KubernetesOIDCToken,
} from './kubernetes-oidc';
