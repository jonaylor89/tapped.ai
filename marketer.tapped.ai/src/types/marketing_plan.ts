
export type MarketingPlan = {
    prompt?: string;
    content?: string;
    checkoutSessionId?: string;
    clientReferenceId: string;
    status: 'initial' | 'processing' | 'completed' | 'failed';
};
