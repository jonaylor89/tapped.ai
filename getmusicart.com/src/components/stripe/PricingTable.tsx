'use client';

import { User } from 'firebase/auth';
import React, { useEffect } from 'react';

const pricingTableId = process.env.NEXT_PUBLIC_STRIPE_PRICING_TABLE_ID;
const publishableKey = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY;

interface StripePricingTableProps extends React.DetailedHTMLProps<React.HTMLAttributes<HTMLElement>, HTMLElement> {
  'pricing-table-id': string;
  'publishable-key': string;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace JSX {
    interface IntrinsicElements {
      'stripe-pricing-table': StripePricingTableProps;
    }
  }
}

export default function StripePricingTable({ user }: {
  user: User;
}) {
  useEffect(() => {
    const script = document.createElement('script');
    script.src = 'https://js.stripe.com/v3/pricing-table.js';
    script.async = true;

    document.body.appendChild(script);

    return () => {
      document.body.removeChild(script);
    };
  }, []);

  if (pricingTableId === undefined || publishableKey === undefined) {
    return (
      <div className='flex flex-1 flex-col w-full'>
        <h1 className='text-5xl tracking-tighter pb-10 font-bold'>
          no pricing table id or publishable key provided
        </h1>
      </div>
    );
  }

  return (
    <div className='flex flex-col w-full'>
      <stripe-pricing-table
        pricing-table-id={pricingTableId}
        publishable-key={publishableKey}
        client-reference-id={user.uid}
        customer-email={user.email}
      >
      </stripe-pricing-table>
    </div>
  );
}
