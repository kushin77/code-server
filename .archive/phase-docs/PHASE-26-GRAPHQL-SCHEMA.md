# Phase 26: Developer Ecosystem - GraphQL Schema Specification

**Status**: Production Design - Ready for July 22 Implementation  
**Timeline**: July 22 - August 12, 2026  
**Effort**: 15+ hours (schema + resolver implementation)  
**Complements**: REST API for flexible querying  

---

## GraphQL API Overview

**Endpoint**: `POST /graphql`  
**Subscriptions**: `wss://api.ide.kushnir.cloud/graphql` (WebSocket)  
**Authentication**: Bearer token (OAuth2) or API key  
**Schema Introspection**: Enabled for developer tools

---

## Core Schema Definition

```graphql
schema {
  query: Query
  mutation: Mutation
  subscription: Subscription
}

# ═══════════════════════════════════════════════════════════════════════════
# QUERIES - Reading data
# ═══════════════════════════════════════════════════════════════════════════

type Query {
  # User queries
  me: User! @auth
  user(id: ID!): User @auth
  users(first: Int = 20, after: String): UserConnection! @auth(role: ADMIN)
  
  # Organization queries
  organization(id: ID!): Organization! @auth
  organizations(first: Int = 20, after: String): OrganizationConnection! @auth
  organizationByName(name: String!): Organization @auth
  
  # Workspace queries
  workspace(id: ID!): Workspace! @auth
  workspaces(
    organizationId: ID!,
    first: Int = 20,
    after: String,
    status: WorkspaceStatus,
    sortBy: WorkspaceSortField = CREATED_AT,
    sortOrder: SortOrder = DESC
  ): WorkspaceConnection! @auth
  
  # File queries
  files(
    workspaceId: ID!,
    path: String = "/",
    recursive: Boolean = false
  ): [File!]! @auth
  
  file(workspaceId: ID!, path: String!): File @auth
  
  # API Key queries
  apiKeys(organizationId: ID!): [ApiKey!]! @auth
  apiKey(id: ID!): ApiKey @auth
  
  # Analytics queries
  usage(
    organizationId: ID!,
    period: UsagePeriod = MONTH,
    startDate: DateTime,
    endDate: DateTime
  ): UsageStats! @auth
  
  analytics(
    organizationId: ID!,
    metric: AnalyticsMetric!,
    granularity: Granularity = HOUR,
    startDate: DateTime,
    endDate: DateTime
  ): [AnalyticsDataPoint!]! @auth
  
  # Webhook queries
  webhooks(organizationId: ID!): [Webhook!]! @auth
  webhook(id: ID!): Webhook @auth
  webhookDeliveries(
    webhookId: ID!,
    status: WebhookStatus,
    first: Int = 20,
    after: String
  ): WebhookDeliveryConnection! @auth
  
  # Health & Status
  health: HealthStatus!
  status: SystemStatus!
  
  # Search
  search(
    query: String!,
    type: SearchType,
    organizationId: ID!,
    first: Int = 20
  ): SearchResults! @auth
}

# ═══════════════════════════════════════════════════════════════════════════
# MUTATIONS - Creating/updating data
# ═══════════════════════════════════════════════════════════════════════════

type Mutation {
  # User mutations
  createUser(input: CreateUserInput!): CreateUserPayload!
  updateUser(id: ID!, input: UpdateUserInput!): UpdateUserPayload! @auth
  deleteUser(id: ID!): DeleteUserPayload! @auth
  
  # Organization mutations
  createOrganization(input: CreateOrganizationInput!): CreateOrganizationPayload! @auth
  updateOrganization(id: ID!, input: UpdateOrganizationInput!): UpdateOrganizationPayload! @auth(role: ADMIN)
  deleteOrganization(id: ID!): DeleteOrganizationPayload! @auth(role: ADMIN)
  
  # Member mutations
  inviteMember(orgId: ID!, input: InviteMemberInput!): InviteMemberPayload! @auth(role: ADMIN)
  updateMember(orgId: ID!, memberId: ID!, input: UpdateMemberInput!): UpdateMemberPayload! @auth(role: ADMIN)
  removeMember(orgId: ID!, memberId: ID!): RemoveMemberPayload! @auth(role: ADMIN)
  acceptMemberInvite(token: String!): AcceptMemberInvitePayload!
  
  # Workspace mutations
  createWorkspace(input: CreateWorkspaceInput!): CreateWorkspacePayload! @auth
  updateWorkspace(id: ID!, input: UpdateWorkspaceInput!): UpdateWorkspacePayload! @auth
  deleteWorkspace(id: ID!): DeleteWorkspacePayload! @auth
  startWorkspace(id: ID!): StartWorkspacePayload! @auth
  stopWorkspace(id: ID!): StopWorkspacePayload! @auth
  restartWorkspace(id: ID!): RestartWorkspacePayload! @auth
  
  # File mutations
  writeFile(workspaceId: ID!, path: String!, content: String!): WriteFilePayload! @auth
  deleteFile(workspaceId: ID!, path: String!): DeleteFilePayload! @auth
  createDirectory(workspaceId: ID!, path: String!): CreateDirectoryPayload! @auth
  
  # API Key mutations
  createApiKey(orgId: ID!, input: CreateApiKeyInput!): CreateApiKeyPayload! @auth
  rotateApiKey(id: ID!): RotateApiKeyPayload! @auth
  revokeApiKey(id: ID!): RevokeApiKeyPayload! @auth
  
  # Webhook mutations
  createWebhook(orgId: ID!, input: CreateWebhookInput!): CreateWebhookPayload! @auth
  updateWebhook(id: ID!, input: UpdateWebhookInput!): UpdateWebhookPayload! @auth
  deleteWebhook(id: ID!): DeleteWebhookPayload! @auth
  testWebhook(id: ID!): TestWebhookPayload! @auth
}

# ═══════════════════════════════════════════════════════════════════════════
# SUBSCRIPTIONS - Real-time updates
# ═══════════════════════════════════════════════════════════════════════════

type Subscription {
  # Workspace subscriptions (real-time updates)
  workspaceStatus(id: ID!): WorkspaceStatusUpdate! @auth
  workspaceActivity(id: ID!): WorkspaceActivity! @auth
  
  # File subscriptions
  fileChanged(workspaceId: ID!, path: String!): FileChange! @auth
  
  # Organization subscriptions
  organizationUpdated(id: ID!): Organization! @auth
  
  # Analytics subscriptions
  usageUpdated(organizationId: ID!): UsageStats! @auth
}

# ═══════════════════════════════════════════════════════════════════════════
# TYPES
# ═══════════════════════════════════════════════════════════════════════════

type User {
  id: ID!
  email: String!
  name: String!
  avatarUrl: String
  organizations: [Organization!]!
  apiKeysCount: Int! @auth(requiresSelf: true)
  createdAt: DateTime!
  updatedAt: DateTime!
  lastLoginAt: DateTime
}

type Organization {
  id: ID!
  name: String!
  description: String
  tier: OrganizationTier!
  owner: User!
  members: [OrganizationMember!]!
  membersCount: Int!
  teams: [Team!]!
  teamsCount: Int!
  workspaces: [Workspace!]!
  workspacesCount: Int!
  apiKeysCount: Int!
  createdAt: DateTime!
  updatedAt: DateTime!
  deletedAt: DateTime
}

type OrganizationMember {
  id: ID!
  user: User!
  organization: Organization!
  role: OrganizationRole!
  joinedAt: DateTime!
  invitedAt: DateTime
  invitedBy: User
}

type Team {
  id: ID!
  name: String!
  organization: Organization!
  members: [TeamMember!]!
  membersCount: Int!
  createdAt: DateTime!
}

type TeamMember {
  id: ID!
  user: User!
  team: Team!
  role: TeamRole!
  joinedAt: DateTime!
}

type Workspace {
  id: ID!
  name: String!
  description: String
  url: String!
  status: WorkspaceStatus!
  organization: Organization!
  owner: User!
  image: String!
  resources: WorkspaceResources!
  usage: WorkspaceUsage!
  createdAt: DateTime!
  updatedAt: DateTime!
  startedAt: DateTime
  stoppedAt: DateTime
  lastActivityAt: DateTime
}

type WorkspaceResources {
  cpuAllocated: String!  # e.g., "2000m"
  memoryAllocated: String!  # e.g., "4Gi"
  cpuUsed: String!
  memoryUsed: String!
  networkBytesIn: Int!
  networkBytesOut: Int!
}

type WorkspaceUsage {
  hoursRunning: Float!
  cpuHours: Float!
  memoryGbHours: Float!
  networkGb: Float!
}

type File {
  id: ID!
  name: String!
  path: String!
  size: Int!  # bytes
  type: FileType!
  mimeType: String
  content: String  # Only if explicitly requested
  createdAt: DateTime!
  modifiedAt: DateTime!
  isExecutable: Boolean!
}

type ApiKey {
  id: ID!
  name: String!
  keyPrefix: String!  # "sk_live_4eC39Hq..."
  secret: String  # Only returned on creation
  permissions: [Permission!]!
  createdAt: DateTime!
  expiresAt: DateTime
  lastUsedAt: DateTime
}

type Webhook {
  id: ID!
  url: String!
  events: [WebhookEvent!]!
  active: Boolean!
  secret: String  # Only returned on creation
  organization: Organization!
  deliveriesTotal: Int!
  deliveriesFailed: Int!
  deliveriesSuccessful: Int!
  lastDeliveryAt: DateTime
  createdAt: DateTime!
}

type WebhookDelivery {
  id: ID!
  webhook: Webhook!
  event: WebhookEvent!
  payload: String!  # JSON
  status: WebhookDeliveryStatus!
  responseCode: Int
  responseBody: String
  error: String
  deliveredAt: DateTime
  retryCount: Int!
  createdAt: DateTime!
}

type UsageStats {
  organizationId: ID!
  period: UsagePeriod!
  startDate: DateTime!
  endDate: DateTime!
  workspaceHours: Float!
  cpuHours: Float!
  memoryGbHours: Float!
  networkGb: Float!
  apiRequests: ApiRequestStats!
  costEstimate: CostEstimate!
}

type ApiRequestStats {
  total: Int!
  byEndpoint: [EndpointStats!]!
  byMethod: [MethodStats!]!
  errorRate: Float!
  p50Latency: Int!  # milliseconds
  p95Latency: Int!
  p99Latency: Int!
}

type CostEstimate {
  amount: Float!
  currency: String!
  breakdown: [CostBreakdown!]!
}

type CostBreakdown {
  category: String!  # "compute", "storage", "network"
  amount: Float!
  percentage: Float!
}

type AnalyticsDataPoint {
  timestamp: DateTime!
  value: Float!
  p50: Float
  p95: Float
  p99: Float
}

type HealthStatus {
  status: ServiceStatus!
  uptime: Int!  # seconds
  version: String!
  services: [ServiceHealth!]!
  timestamp: DateTime!
}

type ServiceHealth {
  name: String!
  status: ServiceStatus!
  responseTime: Int  # milliseconds
}

type SystemStatus {
  apiStatus: ServiceStatus!
  databaseStatus: ServiceStatus!
  websocketStatus: ServiceStatus!
  responseTime: Int!  # milliseconds
  timestamp: DateTime!
}

type SearchResults {
  total: Int!
  results: [SearchResult!]!
}

type SearchResult {
  id: ID!
  type: SearchType!
  name: String!
  description: String
  preview: String
}

# ═══════════════════════════════════════════════════════════════════════════
# INPUT TYPES
# ═══════════════════════════════════════════════════════════════════════════

input CreateUserInput {
  email: String!
  name: String!
  password: String!
  organizationId: ID
}

input UpdateUserInput {
  name: String
  avatarUrl: String
}

input CreateOrganizationInput {
  name: String!
  description: String
  tier: OrganizationTier = PRO
}

input UpdateOrganizationInput {
  name: String
  description: String
  tier: OrganizationTier
}

input InviteMemberInput {
  email: String!
  role: OrganizationRole = DEVELOPER
}

input UpdateMemberInput {
  role: OrganizationRole!
}

input CreateWorkspaceInput {
  name: String!
  description: String
  organizationId: ID!
  image: String = "code-server:latest"
  resources: WorkspaceResourcesInput
}

input WorkspaceResourcesInput {
  cpu: String  # e.g., "2000m"
  memory: String  # e.g., "4Gi"
}

input UpdateWorkspaceInput {
  name: String
  description: String
  resources: WorkspaceResourcesInput
}

input CreateApiKeyInput {
  name: String!
  permissions: [Permission!]!
  expiresInDays: Int
}

input CreateWebhookInput {
  url: String!
  events: [WebhookEvent!]!
  secret: String
}

input UpdateWebhookInput {
  url: String
  events: [WebhookEvent!]
  active: Boolean
}

# ═══════════════════════════════════════════════════════════════════════════
# PAYLOAD TYPES (for mutations)
# ═══════════════════════════════════════════════════════════════════════════

type CreateUserPayload {
  user: User
  errors: [Error!]
}

type UpdateUserPayload {
  user: User
  errors: [Error!]
}

type DeleteUserPayload {
  success: Boolean!
  errors: [Error!]
}

type CreateWorkspacePayload {
  workspace: Workspace
  errors: [Error!]
}

type UpdateWorkspacePayload {
  workspace: Workspace
  errors: [Error!]
}

type DeleteWorkspacePayload {
  success: Boolean!
  errors: [Error!]
}

type StartWorkspacePayload {
  workspace: Workspace
  errors: [Error!]
}

type StopWorkspacePayload {
  workspace: Workspace
  errors: [Error!]
}

type RestartWorkspacePayload {
  workspace: Workspace
  errors: [Error!]
}

type WriteFilePayload {
  file: File
  errors: [Error!]
}

type DeleteFilePayload {
  success: Boolean!
  errors: [Error!]
}

type CreateApiKeyPayload {
  apiKey: ApiKey
  errors: [Error!]
}

type CreateWebhookPayload {
  webhook: Webhook
  errors: [Error!]
}

type TestWebhookPayload {
  success: Boolean!
  statusCode: Int
  response: String
  errors: [Error!]
}

# Remaining payload types follow same pattern...

# ═══════════════════════════════════════════════════════════════════════════
# ENUMS
# ═══════════════════════════════════════════════════════════════════════════

enum OrganizationTier {
  FREE
  PRO
  ENTERPRISE
}

enum OrganizationRole {
  ADMIN
  DEVELOPER
  AUDITOR
  VIEWER
}

enum TeamRole {
  LEAD
  MEMBER
}

enum WorkspaceStatus {
  PROVISIONING
  RUNNING
  STOPPING
  STOPPED
  ERROR
  DELETED
}

enum WorkspaceSortField {
  CREATED_AT
  UPDATED_AT
  NAME
  STATUS
}

enum SortOrder {
  ASC
  DESC
}

enum FileType {
  FILE
  DIRECTORY
  SYMLINK
}

enum Permission {
  WORKSPACES_READ
  WORKSPACES_WRITE
  FILES_READ
  FILES_WRITE
  ANALYTICS_READ
  SETTINGS_WRITE
}

enum ServiceStatus {
  OPERATIONAL
  DEGRADED
  UNAVAILABLE
}

enum UsagePeriod {
  DAY
  WEEK
  MONTH
  YEAR
}

enum Granularity {
  HOUR
  DAY
  WEEK
  MONTH
}

enum AnalyticsMetric {
  API_REQUESTS
  LATENCY
  ERRORS
  RESOURCE_USAGE
  WEBHOOK_DELIVERIES
}

enum WebhookEvent {
  WORKSPACE_CREATED
  WORKSPACE_STARTED
  WORKSPACE_STOPPED
  WORKSPACE_DELETED
  FILE_CREATED
  FILE_MODIFIED
  FILE_DELETED
  USER_JOINED
  USER_LEFT
  API_KEY_CREATED
  API_KEY_ROTATED
  API_KEY_REVOKED
}

enum WebhookDeliveryStatus {
  PENDING
  SUCCESS
  FAILED
  RETRYING
}

enum SearchType {
  WORKSPACE
  FILE
  USER
  ORGANIZATION
}

# ═══════════════════════════════════════════════════════════════════════════
# SCALAR TYPES & UNIONS
# ═══════════════════════════════════════════════════════════════════════════

scalar DateTime
scalar JSON
scalar BigInt

type Error {
  message: String!
  code: String!
  field: String
}

# Connections for pagination (GraphQL Relay spec)

type UserConnection {
  edges: [UserEdge!]!
  pageInfo: PageInfo!
}

type UserEdge {
  cursor: String!
  node: User!
}

type OrganizationConnection {
  edges: [OrganizationEdge!]!
  pageInfo: PageInfo!
}

type OrganizationEdge {
  cursor: String!
  node: Organization!
}

type WorkspaceConnection {
  edges: [WorkspaceEdge!]!
  pageInfo: PageInfo!
}

type WorkspaceEdge {
  cursor: String!
  node: Workspace!
}

type WebhookDeliveryConnection {
  edges: [WebhookDeliveryEdge!]!
  pageInfo: PageInfo!
}

type WebhookDeliveryEdge {
  cursor: String!
  node: WebhookDelivery!
}

type PageInfo {
  hasNextPage: Boolean!
  hasPreviousPage: Boolean!
  startCursor: String
  endCursor: String
}

# ═══════════════════════════════════════════════════════════════════════════
# REAL-TIME UPDATES
# ═══════════════════════════════════════════════════════════════════════════

type WorkspaceStatusUpdate {
  workspace: Workspace!
  previousStatus: WorkspaceStatus!
  newStatus: WorkspaceStatus!
  updatedAt: DateTime!
}

type WorkspaceActivity {
  workspaceId: ID!
  type: ActivityType!
  user: User!
  description: String
  timestamp: DateTime!
}

type FileChange {
  workspaceId: ID!
  path: String!
  changeType: FileChangeType!
  timestamp: DateTime!
}

enum ActivityType {
  CODE_EXECUTION
  FILE_SAVE
  WORKSPACE_START
  WORKSPACE_STOP
  COLLABORATION_JOIN
  COLLABORATION_LEAVE
}

enum FileChangeType {
  CREATED
  MODIFIED
  DELETED
}
```

---

## Query Examples

### Get current user with organizations
```graphql
{
  me {
    id
    name
    email
    organizations {
      id
      name
      tier
    }
  }
}
```

### List workspaces with usage
```graphql
{
  workspaces(
    organizationId: "org-abc123"
    status: RUNNING
    sortBy: CREATED_AT
  ) {
    edges {
      node {
        id
        name
        status
        usage {
          hoursRunning
          cpuHours
        }
      }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
```

### Get analytics data
```graphql
{
  analytics(
    organizationId: "org-abc123"
    metric: API_REQUESTS
    granularity: HOUR
    startDate: "2026-07-22T00:00:00Z"
    endDate: "2026-07-25T00:00:00Z"
  ) {
    timestamp
    value
    p99
  }
}
```

---

## Implementation Details

- ✅ Automatic schema validation on startup
- ✅ Query complexity analysis (prevent expensive queries)
- ✅ Batch loader for N+1 query prevention
- ✅ Apollo Server 4.x with ESM support
- ✅ DataLoader for connection pooling
- ✅ Field-level permissions via directives (@auth, @requiresSelf)
- ✅ Request/subscription middleware for auth
- ✅ Error handling with standardized error codes
- ✅ CORS configuration for client-side access

---

**Status**: Specification Complete - Ready for Implementation July 22, 2026  
**Next**: SDK Implementation (Python, TypeScript, Go, Java)  
**Owner**: Infrastructure Team
