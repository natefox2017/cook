export type AdminRole = "owner" | "admin" | "operator" | "readonly";

export type AdminAccount = {
  id: string;
  username: string;
  role: AdminRole;
  mustChangePassword: boolean;
};

export type AdminSession = {
  token: string;
  expiresAt: string;
  admin: AdminAccount;
};

export type DashboardData = {
  stats: {
    totalUsers: number;
    newUsersThisMonth: number;
    activePaidUsers: number;
    suspendedUsers: number;
    revenueTotal: number;
    revenueMrr: number;
    revenueApple: number;
    revenueAndroid: number;
    paymentTransactions: number;
    downloadsTotal: number;
    downloadsIos: number;
    downloadsAndroid: number;
  };
  growth: Array<{ month: string; users: number }>;
  series: Array<{
    month: string;
    users: number;
    revenue: number;
    revenueApple: number;
    revenueAndroid: number;
    downloadsIos: number;
    downloadsAndroid: number;
  }>;
  userBreakdown: {
    byRegistrationType: Array<{ key: string; label: string; value: number }>;
    byDeviceType: Array<{ key: string; label: string; value: number }>;
    byPlan: Array<{ key: string; label: string; value: number }>;
  };
};

export type AdminUser = {
  id: string;
  email: string;
  displayName: string;
  avatarUrl: string | null;
  subscription: "free" | "pro" | "lifetime";
  createdAt: string;
  status: "active" | "suspended" | "deleted";
  registrationProvider: "apple" | "google" | "email" | "unknown";
  deviceType: "ios" | "android" | "web" | "unknown";
  registrationCountryCode?: string | null;
};

export type AdminUserPage = {
  data: AdminUser[];
  total: number;
  page: number;
  pageSize: number;
};

export type AdminUserDetail = AdminUser & {
  lastLoginAt: string | null;
  payments: Array<{
    id: string;
    eventType: string;
    productId: string | null;
    store: string | null;
    amount: number | null;
    currency: string | null;
    environment: string | null;
    purchasedAt: string;
  }>;
};

export type LLMProvider = {
  id: string;
  name: string;
  baseUrl: string;
  model: string;
  active: boolean;
  apiKeyConfigured: boolean;
  updatedAt: string;
};

export type LLMProviderInput = {
  name: string;
  baseUrl: string;
  model: string;
  apiKey: string;
  active: boolean;
};

export type LLMUsageRange = "7d" | "30d" | "90d";

export type LLMUsage = {
  totals: {
    requests: number;
    inputTokens: number;
    outputTokens: number;
    totalTokens: number;
  };
  series: Array<{
    date: string;
    requests: number;
    inputTokens: number;
    outputTokens: number;
    totalTokens: number;
  }>;
  byModel: Array<{
    provider: string;
    model: string;
    requests: number;
    totalTokens: number;
  }>;
};

export type SubscriptionPlan = {
  id: string;
  planKey: string;
  displayName: string;
  platform: "app_store" | "play_store";
  productId: string;
  price: number;
  currency: string;
  billingPeriod: "monthly" | "yearly" | "lifetime";
  active: boolean;
  description: string | null;
  updatedAt: string;
};

export type SubscriptionRecord = {
  id: string;
  user: { id: string; displayName: string; email: string };
  plan: string;
  status: string;
  platform: "app_store" | "play_store" | null;
  productId: string | null;
  amount: number | null;
  currency: string | null;
  startDate: string;
  expirationDate: string | null;
};

export type RevenueData = {
  stats: {
    mrr: number;
    appleRevenue: number;
    androidRevenue: number;
    activePaid: number;
  };
  series: Array<{
    month: string;
    apple: number;
    android: number;
    total: number;
  }>;
};
